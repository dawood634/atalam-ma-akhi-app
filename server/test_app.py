import io
import os
from urllib.parse import urlparse
from server.database import DatabaseSession
import concurrent.futures
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import unittest
from unittest import mock
from urllib.error import HTTPError
from urllib.request import Request,urlopen
from wsgiref.simple_server import make_server, WSGIRequestHandler
from server.app import ClassroomApp, MAX_BODY, create_app

INVITE='test-only-creation-invitation-'+'x'*32


class ApiTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.now=100000.0
        self.path=Path(self.temp.name)/'db.sqlite3'
        self.app=ClassroomApp(self.path,INVITE,lambda:self.now)

    def call(self,path,method='GET',data=None,token=None,invite=None,address='test-device'):
        raw=json.dumps(data or {}).encode()
        env={'REQUEST_METHOD':method,'PATH_INFO':path,'REMOTE_ADDR':address,
             'CONTENT_LENGTH':str(len(raw)) if method=='POST' else '0',
             'CONTENT_TYPE':'application/json','wsgi.input':io.BytesIO(raw)}
        if token:env['HTTP_AUTHORIZATION']='Bearer '+token
        if invite:env['HTTP_X_TEACHER_INVITE']=invite
        captured={}
        def start(status,headers):captured.update(status=int(status.split()[0]),headers=dict(headers))
        body=b''.join(self.app(env,start))
        return captured['status'],json.loads(body)

    def room(self,title='فصل تجريبي'):
        status,result=self.call('/v1/rooms','POST',{'title':title},invite=INVITE)
        self.assertEqual(status,201,result)
        return result

    def pupil(self,room,nickname='متعلم'):
        status,result=self.call('/v1/join','POST',{'code':room['room']['join_code'],'nickname':nickname})
        self.assertEqual(status,201,result)
        return result

    def payload(self,number='one',answers=None):
        return {'request_id':'synthetic-attempt-'+number,'lesson_id':next(iter(self.app.lessons)),
                'answers':answers or [q['correct'] for q in next(iter(self.app.lessons.values()))['questions']]}

    def test_creation_requires_teacher_invitation_and_tokens_are_only_hashed(self):
        self.assertEqual(self.call('/v1/rooms','POST',{'title':'room'})[0],403)
        self.assertEqual(self.call('/v1/rooms','POST',{'title':'room'},invite='دعوة غير صحيحة')[0],403)
        room=self.room();pupil=self.pupil(room)
        with self.app.connect() as db:
            saved=db.execute('SELECT teacher_hash FROM rooms').fetchone()['teacher_hash']
            self.assertNotEqual(saved,room['token'])
            self.assertNotEqual(db.execute('SELECT token_hash FROM students').fetchone()['token_hash'],pupil['token'])
        unconfigured=ClassroomApp(Path(self.temp.name)/'no-invite.sqlite3')
        previous=self.app;self.app=unconfigured
        self.assertEqual(self.call('/v1/rooms','POST',{'title':'room'})[0],503)
        self.app=previous

    def test_student_cannot_assign_or_read_roster(self):
        room=self.room();student=self.pupil(room)
        self.assertEqual(self.call('/v1/report',token=student['token'])[0],403)
        self.assertEqual(self.call('/v1/assignment','POST',{'lesson_id':next(iter(self.app.lessons))},token=student['token'])[0],403)
        self.assertEqual(self.call('/v1/report')[0],401)
        self.assertEqual(self.call('/v1/session',token='invented')[0],401)

    def test_two_rooms_are_isolated_and_assignments_reach_only_their_students(self):
        a,b=self.room('أ'),self.room('ب');pa,pb=self.pupil(a,'طالب أ'),self.pupil(b,'طالب ب')
        lesson=next(iter(self.app.lessons))
        self.assertEqual(self.call('/v1/assignment','POST',{'lesson_id':lesson},token=a['token'])[0],200)
        self.assertEqual(self.call('/v1/session',token=pa['token'])[1]['assignment'],lesson)
        self.assertIsNone(self.call('/v1/session',token=pb['token'])[1]['assignment'])
        report=self.call('/v1/report',token=a['token'])[1]
        self.assertEqual([p['nickname'] for p in report['students']],['طالب أ'])
        self.assertNotIn('token',json.dumps(report))
        self.assertNotIn('join_code',self.call('/v1/session',token=pa['token'])[1]['room'])

    def test_server_grades_answers_and_duplicate_sync_does_not_double_count(self):
        room=self.room();student=self.pupil(room);payload=self.payload()
        first=self.call('/v1/attempts','POST',payload,token=student['token'])
        self.assertEqual(first[0],201,first)
        self.assertEqual(first[1]['score'],3)
        retry=self.call('/v1/attempts','POST',payload,token=student['token'])
        self.assertEqual(retry,(200,first[1]))
        report=self.call('/v1/report',token=room['token'])[1]
        self.assertEqual(report['students'][0]['lessons'][payload['lesson_id']]['attempts'],1)
        changed=dict(payload,answers=[0,0,0])
        self.assertEqual(self.call('/v1/attempts','POST',changed,token=student['token'])[0],409)
        self.assertEqual(self.call('/v1/attempts','POST',dict(payload,score=3),token=student['token'])[0],400)

    def test_teacher_cannot_submit_student_scores(self):
        room=self.room()
        self.assertEqual(self.call('/v1/attempts','POST',self.payload(),token=room['token'])[0],403)

    def test_last_and_best_results_and_restart_persistence(self):
        room=self.room();student=self.pupil(room);payload=self.payload()
        self.call('/v1/attempts','POST',payload,token=student['token'])
        self.now+=1
        wrong=[(q['correct']+1)%len(q['choices']) for q in self.app.lessons[payload['lesson_id']]['questions']]
        self.call('/v1/attempts','POST',self.payload('two',wrong),token=student['token'])
        self.app=ClassroomApp(self.path,INVITE,lambda:self.now)
        stats=self.call('/v1/report',token=room['token'])[1]['students'][0]['lessons'][payload['lesson_id']]
        self.assertEqual((stats['last'],stats['best'],stats['attempts']),(0,3,2))

    def test_rotation_closes_old_invite_without_revoking_existing_student(self):
        room=self.room();student=self.pupil(room)
        result=self.call('/v1/rotate-code','POST',token=room['token'])
        self.assertEqual(result[0],200)
        self.assertNotEqual(result[1]['join_code'],room['room']['join_code'])
        self.assertEqual(self.call('/v1/join','POST',{'code':room['room']['join_code'],'nickname':'new'})[0],404)
        self.assertEqual(self.call('/v1/session',token=student['token'])[0],200)
        self.assertEqual(self.call('/v1/rotate-code','POST',token=student['token'])[0],403)

    def test_deleting_pupil_and_room_cascades_and_does_not_touch_other_rooms(self):
        a,b=self.room(),self.room('other');pa,pb=self.pupil(a),self.pupil(b)
        self.call('/v1/attempts','POST',self.payload(),token=pa['token'])
        self.assertEqual(self.call('/v1/session','DELETE',token=pa['token'])[0],200)
        self.assertEqual(self.call('/v1/session',token=pa['token'])[0],401)
        with self.app.connect() as db:self.assertEqual(db.execute('SELECT COUNT(*) AS n FROM attempts').fetchone()['n'],0)
        self.assertEqual(self.call('/v1/session','DELETE',token=a['token'])[0],200)
        self.assertEqual(self.call('/v1/session',token=a['token'])[0],401)
        self.assertEqual(self.call('/v1/session',token=pb['token'])[0],200)

    def test_expiry_removes_room_roster_and_attempts(self):
        room=self.room();student=self.pupil(room)
        self.call('/v1/attempts','POST',self.payload(),token=student['token'])
        self.now+=31*86400
        self.assertEqual(self.call('/v1/session',token=student['token'])[0],401)
        with self.app.connect() as db:
            for table in ['rooms','students','attempts']:
                self.assertEqual(db.execute('SELECT COUNT(*) AS n FROM '+table).fetchone()['n'],0)

    def test_bad_input_and_unknown_lessons_are_rejected(self):
        room=self.room();student=self.pupil(room)
        self.assertEqual(self.call('/v1/join','POST',{'code':room['room']['join_code'],'nickname':'متعلم'})[0],409)
        for answers in [[],[True,1,1],[-1,1,1],[99,0,0],['1',1,1]]:
            self.assertEqual(self.call('/v1/attempts','POST',dict(self.payload(),answers=answers),token=student['token'])[0],400)
        self.assertEqual(self.call('/v1/assignment','POST',{'lesson_id':'missing'},token=room['token'])[0],400)
        public=self.call('/v1/lessons/'+next(iter(self.app.lessons)),token=student['token'])[1]
        self.assertNotIn('correct',public['questions'][0])
        self.assertNotIn('feedback',public['questions'][0])

    def test_rate_limit_is_shared_by_new_service_instances(self):
        for _ in range(120):self.assertEqual(self.call('/v1/session',address='limited')[0],401)
        self.app=ClassroomApp(self.path,INVITE,lambda:self.now)
        self.assertEqual(self.call('/v1/session',address='limited')[0],429)
        self.now+=61
        self.assertEqual(self.call('/v1/session',address='limited')[0],401)

    def test_concurrent_retries_create_one_attempt(self):
        room=self.room();student=self.pupil(room);payload=self.payload()
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results=list(pool.map(lambda _:self.call('/v1/attempts','POST',payload,token=student['token']),range(4)))
        self.assertEqual(sorted(r[0] for r in results),[200,200,200,201])
        report=self.call('/v1/report',token=room['token'])[1]
        self.assertEqual(report['students'][0]['lessons'][payload['lesson_id']]['attempts'],1)

    def test_room_capacity_is_enforced(self):
        room=self.room()
        for n in range(50):self.pupil(room,'nickname-'+str(n))
        self.assertEqual(self.call('/v1/join','POST',{'code':room['room']['join_code'],'nickname':'extra'})[0],409)

    def test_transport_validation_and_no_store_headers(self):
        def request(env):
            captured={}
            self.app(env,lambda status,headers:captured.update(status=int(status.split()[0]),headers=dict(headers)))
            return captured
        base={'REQUEST_METHOD':'POST','PATH_INFO':'/v1/join','REMOTE_ADDR':'body-tests',
              'CONTENT_LENGTH':'2','CONTENT_TYPE':'application/json','wsgi.input':io.BytesIO(b'[]')}
        self.assertEqual(request(base)['status'],400)
        self.assertEqual(request(dict(base,CONTENT_LENGTH=str(MAX_BODY+1)))['status'],413)
        self.assertEqual(request(dict(base,CONTENT_TYPE='text/plain'))['status'],415)
        self.assertEqual(request(dict(base,REQUEST_METHOD='PUT'))['status'],405)
        health=request(dict(base,REQUEST_METHOD='GET',PATH_INFO='/health',CONTENT_LENGTH='0'))
        self.assertEqual(health['headers']['Cache-Control'],'no-store')

    def test_real_http_teacher_student_round_trip(self):
        class Quiet(WSGIRequestHandler):
            def log_message(self,*args):pass
        server=make_server('127.0.0.1',0,self.app,handler_class=Quiet)
        worker=threading.Thread(target=server.serve_forever,daemon=True);worker.start()
        self.addCleanup(server.server_close);self.addCleanup(server.shutdown)
        base='http://127.0.0.1:'+str(server.server_port)
        def request(path,data=None,token=None,invite=None):
            headers={'Content-Type':'application/json'}
            if token:headers['Authorization']='Bearer '+token
            if invite:headers['X-Teacher-Invite']=invite
            req=Request(base+path,data=json.dumps(data).encode() if data is not None else None,headers=headers)
            with urlopen(req,timeout=5) as result:return json.load(result)
        room=request('/v1/rooms',{'title':'HTTP test'},invite=INVITE)
        pupil=request('/v1/join',{'code':room['room']['join_code'],'nickname':'HTTP student'})
        result=request('/v1/attempts',self.payload(),token=pupil['token'])
        self.assertEqual(result['score'],3)
        roster=request('/v1/report',token=room['token'])
        self.assertEqual(len(roster['students']),1)


class DatabaseConfigurationTests(unittest.TestCase):
    def test_external_storage_requirement_cannot_fall_back_to_ephemeral_sqlite(self):
        with mock.patch.dict(os.environ, {'REQUIRE_EXTERNAL_DATABASE':'1','DATABASE_URL':''}):
            with self.assertRaisesRegex(RuntimeError,'External database is required'):
                create_app()

    def test_unknown_database_urls_are_rejected(self):
        with mock.patch.dict(os.environ, {'DATABASE_URL':'mysql://not-an-accepted-database'}):
            with self.assertRaisesRegex(RuntimeError,'PostgreSQL'):
                create_app()

    def test_public_database_tls_cannot_be_disabled_even_with_local_test_flag(self):
        import server.database as module
        fake = mock.Mock()
        with mock.patch.object(module,'psycopg',fake):
            with mock.patch.dict(os.environ, {'CLASSROOM_ALLOW_LOCAL_DATABASE':'1'}):
                with self.assertRaisesRegex(RuntimeError,'TLS-protected'):
                    with DatabaseSession('postgresql://u:p@database.example/db?sslmode=disable'):
                        pass
        fake.connect.assert_not_called()


@unittest.skipUnless(os.environ.get('CLASSROOM_TEST_DATABASE_URL'), 'PostgreSQL integration database not configured')
class PostgresApiTests(ApiTests):
    def setUp(self):
        super().setUp()
        target = os.environ['CLASSROOM_TEST_DATABASE_URL']
        parsed = urlparse(target)
        if parsed.hostname not in ('127.0.0.1','localhost') or parsed.path != '/atalam_test':
            raise RuntimeError('Destructive integration setup is allowed only on the dedicated local atalam_test database')
        with DatabaseSession(target) as db:
            db.execute('DROP TABLE IF EXISTS attempts,students,rooms,rate_windows CASCADE')
        self.path = target
        self.app = ClassroomApp(target,INVITE,lambda:self.now)


if __name__=='__main__':unittest.main()
