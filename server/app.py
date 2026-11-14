"""Private classroom API. Deploy behind HTTPS; no public service is provisioned here."""
import hashlib
import hmac
import json
import os
from pathlib import Path
import re
import secrets
import sqlite3
import time
from http import HTTPStatus

ROOT = Path(__file__).resolve().parents[1]
MAX_BODY = 16_384
CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'


class ApiError(Exception):
    def __init__(self, status, message):
        self.status, self.message = status, message


def digest(text):
    return hashlib.sha256(text.encode()).hexdigest()


def text_field(data, key, minimum=1, maximum=60):
    value = data.get(key)
    if not isinstance(value, str) or not minimum <= len(value.strip()) <= maximum or any(ord(c) < 32 for c in value):
        raise ApiError(400, f'Invalid {key}')
    return value.strip()


class ClassroomApp:
    def __init__(self, database, teacher_invite='', clock=time.time, content_path=None):
        self.database = str(database)
        self.teacher_invite = teacher_invite
        self.clock = clock
        unit = json.loads(Path(content_path or ROOT / 'content/sets_unit.json').read_text())
        self.lessons = {lesson['id']: lesson for lesson in unit['lessons']}
        with self.connect() as db:
            db.executescript('''
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS rooms(
                id TEXT PRIMARY KEY, title TEXT NOT NULL, code TEXT NOT NULL UNIQUE,
                teacher_hash TEXT NOT NULL UNIQUE, expires REAL NOT NULL,
                assignment TEXT);
            CREATE TABLE IF NOT EXISTS students(
                id TEXT PRIMARY KEY, room_id TEXT NOT NULL REFERENCES rooms(id) ON DELETE CASCADE,
                nickname TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE,
                UNIQUE(room_id,nickname));
            CREATE TABLE IF NOT EXISTS attempts(
                student_id TEXT NOT NULL REFERENCES students(id) ON DELETE CASCADE,
                request_id TEXT NOT NULL, lesson_id TEXT NOT NULL, fingerprint TEXT NOT NULL,
                score INTEGER NOT NULL, total INTEGER NOT NULL, result TEXT NOT NULL, created REAL NOT NULL,
                PRIMARY KEY(student_id,request_id));
            CREATE TABLE IF NOT EXISTS rate_windows(
                key TEXT PRIMARY KEY, starts REAL NOT NULL, count INTEGER NOT NULL);
            CREATE INDEX IF NOT EXISTS attempts_student_lesson ON attempts(student_id,lesson_id);
            ''')
        try:
            os.chmod(self.database, 0o600)
        except OSError:
            pass

    def connect(self):
        db = sqlite3.connect(self.database, timeout=10)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA foreign_keys=ON')
        return db

    def rate_limit(self, key, limit=120):
        now = self.clock()
        with self.connect() as db:
            db.execute('BEGIN IMMEDIATE')
            db.execute('DELETE FROM rate_windows WHERE starts < ?', (now - 120,))
            row = db.execute('SELECT starts,count FROM rate_windows WHERE key=?', (key,)).fetchone()
            if row and now - row['starts'] < 60:
                if row['count'] >= limit:
                    raise ApiError(429, 'Too many requests; retry later')
                db.execute('UPDATE rate_windows SET count=count+1 WHERE key=?', (key,))
            else:
                db.execute('INSERT OR REPLACE INTO rate_windows VALUES(?,?,1)', (key, now))

    def authenticate(self, db, authorization):
        if not authorization.startswith('Bearer ') or len(authorization) > 150:
            raise ApiError(401, 'A valid session is required')
        hashed = digest(authorization[7:])
        room = db.execute('SELECT * FROM rooms WHERE teacher_hash=? AND expires>?', (hashed, self.clock())).fetchone()
        if room:
            return 'teacher', room, None
        student = db.execute('SELECT * FROM students WHERE token_hash=?', (hashed,)).fetchone()
        if student:
            room = db.execute('SELECT * FROM rooms WHERE id=? AND expires>?', (student['room_id'], self.clock())).fetchone()
            if room:
                return 'student', room, student
        raise ApiError(401, 'Session expired or invalid')

    def room_payload(self, role, room, student):
        data = {'role': role, 'room': {'id': room['id'], 'title': room['title'], 'expires': room['expires']},
                'assignment': room['assignment'], 'curriculum_status': 'original_draft_not_officially_approved'}
        if role == 'teacher':
            data['room']['join_code'] = room['code']
        else:
            data['student'] = {'id': student['id'], 'nickname': student['nickname']}
        return data

    def dispatch(self, method, path, data, headers, address):
        # REMOTE_ADDR must come from a trusted HTTPS reverse proxy/server configuration.
        self.rate_limit('ip:' + digest(address))
        if method == 'GET' and path == '/health':
            return 200, {'status': 'ok', 'api_version': 1}
        if method == 'POST' and path == '/v1/rooms':
            if len(self.teacher_invite) < 32:
                raise ApiError(503, 'Teacher provisioning has not been configured')
            invite = headers.get('teacher_invite', '')
            if not hmac.compare_digest(invite.encode(), self.teacher_invite.encode()):
                raise ApiError(403, 'Teacher invitation is required')
            self.rate_limit('create:' + digest(invite), 10)
        if method == 'POST' and path == '/v1/join':
            self.rate_limit('join:' + digest(address), 60)
        now = self.clock()
        with self.connect() as cleanup:
            cleanup.execute('DELETE FROM rooms WHERE expires<=?', (now,))
        with self.connect() as db:
            if method == 'POST' and path in ('/v1/join', '/v1/attempts'):
                db.execute('BEGIN IMMEDIATE')
            if method == 'POST' and path == '/v1/rooms':
                if len(self.teacher_invite) < 32:
                    raise ApiError(503, 'Teacher provisioning has not been configured')
                invite = headers.get('teacher_invite', '')
                if not hmac.compare_digest(invite.encode(), self.teacher_invite.encode()):
                    raise ApiError(403, 'Teacher invitation is required')
                title = text_field(data, 'title', 1, 60)
                token = secrets.token_urlsafe(32)
                room_id = secrets.token_urlsafe(16)
                for _ in range(10):
                    code = ''.join(secrets.choice(CODE_ALPHABET) for _ in range(8))
                    try:
                        db.execute('INSERT INTO rooms VALUES(?,?,?,?,?,NULL)',
                                   (room_id, title, code, digest(token), now + 30 * 86400))
                        break
                    except sqlite3.IntegrityError:
                        continue
                else:
                    raise ApiError(503, 'Unable to create a room; retry later')
                room = db.execute('SELECT * FROM rooms WHERE id=?', (room_id,)).fetchone()
                return 201, {**self.room_payload('teacher', room, None), 'token': token}
            if method == 'POST' and path == '/v1/join':
                code = text_field(data, 'code', 8, 8).upper()
                nickname = text_field(data, 'nickname', 1, 30)
                room = db.execute('SELECT * FROM rooms WHERE code=? AND expires>?', (code, now)).fetchone()
                if room is None:
                    raise ApiError(404, 'Room code is invalid or expired')
                count = db.execute('SELECT COUNT(*) FROM students WHERE room_id=?', (room['id'],)).fetchone()[0]
                if count >= 50:
                    raise ApiError(409, 'Room capacity reached')
                token, student_id = secrets.token_urlsafe(32), secrets.token_urlsafe(16)
                try:
                    db.execute('INSERT INTO students VALUES(?,?,?,?)', (student_id, room['id'], nickname, digest(token)))
                except sqlite3.IntegrityError:
                    raise ApiError(409, 'Choose another nickname in this room') from None
                student = db.execute('SELECT * FROM students WHERE id=?', (student_id,)).fetchone()
                return 201, {**self.room_payload('student', room, student), 'token': token}
            role, room, student = self.authenticate(db, headers.get('authorization', ''))
            if method == 'GET' and path == '/v1/session':
                return 200, self.room_payload(role, room, student)
            if method == 'POST' and path == '/v1/assignment':
                if role != 'teacher':
                    raise ApiError(403, 'Teacher access is required')
                lesson_id = text_field(data, 'lesson_id', 1, 100)
                if lesson_id not in self.lessons:
                    raise ApiError(400, 'Unknown lesson')
                db.execute('UPDATE rooms SET assignment=? WHERE id=?', (lesson_id, room['id']))
                return 200, {'assignment': lesson_id}
            if method == 'GET' and path == '/v1/report':
                if role != 'teacher':
                    raise ApiError(403, 'Teacher access is required')
                roster = []
                for pupil in db.execute('SELECT id,nickname FROM students WHERE room_id=? ORDER BY nickname', (room['id'],)):
                    latest = {}
                    for attempt in db.execute('SELECT lesson_id,score,total,created FROM attempts WHERE student_id=? ORDER BY created,rowid', (pupil['id'],)):
                        key = attempt['lesson_id']
                        old = latest.get(key, {'best':0, 'attempts':0})
                        latest[key] = {'last':attempt['score'], 'best':max(old['best'], attempt['score']),
                                       'total':attempt['total'], 'attempts':old['attempts'] + 1, 'at':attempt['created']}
                    roster.append({'id':pupil['id'], 'nickname':pupil['nickname'], 'lessons':latest})
                return 200, {'room_id':room['id'], 'students':roster}
            if method == 'GET' and path.startswith('/v1/lessons/'):
                lesson = self.lessons.get(path.rsplit('/',1)[-1])
                if lesson is None:
                    raise ApiError(404, 'Unknown lesson')
                public = {k:v for k,v in lesson.items() if k != 'questions'}
                public['questions'] = [{k:q[k] for k in ('prompt','choices')} for q in lesson['questions']]
                return 200, public
            if method == 'POST' and path == '/v1/attempts':
                if role != 'student':
                    raise ApiError(403, 'Student access is required')
                if set(data) != {'request_id','lesson_id','answers'}:
                    raise ApiError(400, 'Only answers, lesson_id and request_id are accepted')
                request_id = text_field(data, 'request_id', 16, 80)
                if not re.fullmatch(r'[A-Za-z0-9_-]+', request_id):
                    raise ApiError(400, 'Invalid request_id')
                lesson_id = text_field(data, 'lesson_id', 1, 100)
                lesson = self.lessons.get(lesson_id)
                if lesson is None:
                    raise ApiError(400, 'Unknown lesson')
                answers = data.get('answers')
                questions = lesson['questions']
                if not isinstance(answers,list) or len(answers) != len(questions) or any(type(a) is not int or not 0 <= a < len(q['choices']) for a,q in zip(answers,questions)):
                    raise ApiError(400, 'Invalid answers')
                fingerprint = digest(json.dumps({'lesson_id':lesson_id,'answers':answers},sort_keys=True))
                old = db.execute('SELECT fingerprint,result FROM attempts WHERE student_id=? AND request_id=?', (student['id'], request_id)).fetchone()
                if old:
                    if old['fingerprint'] != fingerprint:
                        raise ApiError(409, 'Request identifier already used for different answers')
                    return 200, json.loads(old['result'])
                score = sum(a == q['correct'] for a,q in zip(answers,questions))
                result = {'request_id':request_id, 'lesson_id':lesson_id, 'score':score, 'total':len(questions),
                          'feedback':[{'correct':q['correct'],'explanation':q['feedback']} for q in questions],
                          'curriculum_status':'original_draft_not_officially_approved'}
                db.execute('INSERT INTO attempts VALUES(?,?,?,?,?,?,?,?)',
                           (student['id'],request_id,lesson_id,fingerprint,score,len(questions),json.dumps(result,ensure_ascii=False),now))
                return 201, result
            if method == 'POST' and path == '/v1/rotate-code':
                if role != 'teacher':
                    raise ApiError(403, 'Teacher access is required')
                code = ''.join(secrets.choice(CODE_ALPHABET) for _ in range(8))
                db.execute('UPDATE rooms SET code=? WHERE id=?', (code,room['id']))
                return 200, {'join_code':code}
            if method == 'DELETE' and path == '/v1/session':
                if role == 'teacher':
                    db.execute('DELETE FROM rooms WHERE id=?', (room['id'],))
                else:
                    db.execute('DELETE FROM students WHERE id=?', (student['id'],))
                return 200, {'deleted':True}
        raise ApiError(404, 'Unknown API route')

    def __call__(self, environ, start_response):
        try:
            method = environ.get('REQUEST_METHOD','GET')
            path = environ.get('PATH_INFO','/')
            if method not in ('GET','POST','DELETE'):
                raise ApiError(405, 'Method not allowed')
            try:
                length = int(environ.get('CONTENT_LENGTH') or 0)
            except ValueError:
                raise ApiError(400, 'Invalid content length') from None
            if not 0 <= length <= MAX_BODY:
                raise ApiError(413, 'Request body too large')
            data = {}
            if method == 'POST':
                if environ.get('CONTENT_TYPE','').split(';')[0] != 'application/json':
                    raise ApiError(415, 'JSON content is required')
                try:
                    data = json.loads(environ['wsgi.input'].read(length))
                except (ValueError, UnicodeError):
                    raise ApiError(400, 'Invalid JSON body') from None
                if not isinstance(data,dict):
                    raise ApiError(400, 'JSON object is required')
            status, payload = self.dispatch(method,path,data,
                {'authorization':environ.get('HTTP_AUTHORIZATION',''), 'teacher_invite':environ.get('HTTP_X_TEACHER_INVITE','')},
                environ.get('REMOTE_ADDR','unknown'))
        except ApiError as error:
            status, payload = error.status, {'error':error.message}
        except (sqlite3.Error, OSError):
            status, payload = 503, {'error':'Service temporarily unavailable'}
        except Exception:
            status, payload = 500, {'error':'Internal service error'}
        body = json.dumps(payload,ensure_ascii=False).encode()
        headers = [('Content-Type','application/json; charset=utf-8'),('Content-Length',str(len(body))),
                   ('Cache-Control','no-store'),('X-Content-Type-Options','nosniff')]
        if status == 429:
            headers.append(('Retry-After','60'))
        start_response(f'{status} {HTTPStatus(status).phrase}',headers)
        return [body]


def create_app():
    folder = Path(os.environ.get('CLASSROOM_DATA_DIR','/data'))
    folder.mkdir(parents=True,exist_ok=True,mode=0o700)
    return ClassroomApp(folder / 'classrooms.sqlite3', os.environ.get('TEACHER_INVITE',''))
