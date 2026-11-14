import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atalam_ma_akhi/classroom_client.dart';
import 'package:atalam_ma_akhi/classroom_page.dart';
import 'package:flutter/material.dart';

class MemoryVault implements SessionVault {
  String? value;
  @override Future<String?> read() async => value;
  @override Future<void> write(String raw) async { value=raw; }
  @override Future<void> clear() async { value=null; }
}
class FakeTransport implements ClassroomTransport {
  final Future<Map<String,dynamic>> Function(String,Uri,Map<String,String>,Map<String,dynamic>?) handle;
  FakeTransport(this.handle);
  @override Future<Map<String,dynamic>> request(String method,Uri uri,Map<String,String> headers,Map<String,dynamic>? body) => handle(method,uri,headers,body);
}
String tokenOf(String value) => List.filled(43,value).join();
Map<String,dynamic> studentSession() => {'role':'student','token':tokenOf('s'),'room':{'id':'room-one','title':'اختبار','expires':2000000000},'student':{'id':'pupil-one','nickname':'طالب تجريبي'},'assignment':null};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('API rejects insecure origins credentials and path injection',() {
    for (final value in ['http://example.org','https://user:secret@example.org','https://example.org/path','https://example.org?q=secret','https://example.org#fragment']) {
      expect(() => ClassroomApi(value),throwsA(isA<ClassroomException>()));
    }
    expect(() => ClassroomApi('http://outside.example',allowLocalTest:true),throwsA(isA<ClassroomException>()));
    expect(ClassroomApi('http://127.0.0.1:9090',allowLocalTest:true).origin,'http://127.0.0.1:9090');
    final api=ClassroomApi('https://school.example');
    expect(() => api.call('GET','/v1/../report'),throwsArgumentError);
  });
  test('Session credentials use the vault and invitations are not saved',() async {
    SharedPreferences.setMockInitialValues({});
    final prefs=await SharedPreferences.getInstance();final vault=MemoryVault();
    final api=ClassroomApi('https://school.example',transport:FakeTransport((method,uri,headers,body) async {
      expect(uri.origin,'https://school.example');expect(uri.query,isEmpty);
      expect(headers['X-Teacher-Invite'],'private-test-invitation');
      return {'role':'teacher','token':tokenOf('t'),'room':{'id':'room-one','title':'فصل','join_code':'ABCD2345'}};
    }));
    final repo=ClassroomRepository(api,vault,prefs);
    await repo.create('فصل','private-test-invitation');
    expect(vault.value,contains('tttttt'));expect(vault.value,isNot(contains('private-test-invitation')));
    expect(prefs.getKeys(),isEmpty);
  });
  test('An origin change cannot silently send a saved token to another host',() async {
    SharedPreferences.setMockInitialValues({});final vault=MemoryVault();
    vault.value=jsonEncode({...studentSession(),'origin':'https://old.example'});
    final repo=ClassroomRepository(ClassroomApi('https://new.example'),vault,await SharedPreferences.getInstance());
    await expectLater(repo.load(),throwsA(isA<ClassroomException>()));
    expect(vault.value,isNotNull);
  });
  test('Offline queue survives restart and retries the same request identifier',() async {
    SharedPreferences.setMockInitialValues({'completed_lessons':['0']});final prefs=await SharedPreferences.getInstance();final vault=MemoryVault();
    var offline=true;final ids=<String>[];
    final api=ClassroomApi('https://school.example',transport:FakeTransport((method,uri,headers,body) async {
      expect(headers['Authorization'],'Bearer ${tokenOf('s')}');
      ids.add(body!['request_id'] as String);
      expect(body.containsKey('score'),false);
      if (offline) throw const ClassroomException('offline');
      return {'request_id':body['request_id'],'score':2,'total':3};
    }));
    final first=ClassroomRepository(api,vault,prefs);await first.saveSession(studentSession());
    expect(await first.enqueue('lesson-one',[0,1,2]),true);
    expect((await first.flush()).pending,1);
    final restarted=ClassroomRepository(api,vault,prefs);await restarted.load();offline=false;
    final synced=await restarted.flush();
    expect(synced.sent,1);expect(synced.pending,0);expect(ids[0],ids[1]);
    expect(prefs.getStringList('completed_lessons'),['0']);
  });
  test('An acknowledgment never erases a newer queued attempt',() async {
    SharedPreferences.setMockInitialValues({});final prefs=await SharedPreferences.getInstance();final vault=MemoryVault();
    final started=Completer<void>();final release=Completer<void>();var calls=0;
    final api=ClassroomApi('https://school.example',transport:FakeTransport((method,uri,headers,body) async {
      calls++;if (!started.isCompleted) started.complete();await release.future;
      return {'request_id':body!['request_id']};
    }));
    final repo=ClassroomRepository(api,vault,prefs);await repo.saveSession(studentSession());
    await repo.enqueue('first',[0,1,2]);final sending=repo.flush();await started.future;
    final duplicateFlush=repo.flush();await repo.enqueue('second',[1,1,1]);release.complete();
    expect((await sending).pending,1);expect((await duplicateFlush).sent,1);expect(calls,1);
    expect(await repo.pendingCount(),1);
  });
  test('Server confirmation is required before removing an attempt',() async {
    SharedPreferences.setMockInitialValues({});final prefs=await SharedPreferences.getInstance();final vault=MemoryVault();
    final repo=ClassroomRepository(ClassroomApi('https://school.example',transport:FakeTransport((m,u,h,b) async => {'request_id':'different'})),vault,prefs);
    await repo.saveSession(studentSession());await repo.enqueue('lesson',[0,0,0]);
    final result=await repo.flush();expect(result.pending,1);expect(result.error,isNotNull);
  });
  test('Corrupt queues are preserved and reported instead of being discarded',() async {
    SharedPreferences.setMockInitialValues({ClassroomRepository.queueKey:'broken-json'});final prefs=await SharedPreferences.getInstance();
    final repo=ClassroomRepository(ClassroomApi('https://school.example'),MemoryVault(),prefs);await repo.saveSession(studentSession());
    await expectLater(repo.enqueue('lesson',[0,0,0]),throwsA(isA<ClassroomException>()));
    expect(prefs.getString(ClassroomRepository.queueKey),'broken-json');
  });
  test('Expired-session deletion clears only that learner outbox after confirmation route',() async {
    SharedPreferences.setMockInitialValues({});final prefs=await SharedPreferences.getInstance();final vault=MemoryVault();
    final repo=ClassroomRepository(ClassroomApi('https://school.example',transport:FakeTransport((m,u,h,b) async {throw const ClassroomException('expired',401);})),vault,prefs);
    await repo.saveSession(studentSession());await repo.enqueue('lesson',[0,0,0]);
    final entries=jsonDecode(prefs.getString(ClassroomRepository.queueKey)!) as List;
    entries.add({'student_id':'another-pupil','request_id':'other'});await prefs.setString(ClassroomRepository.queueKey,jsonEncode(entries));
    await repo.deleteRemoteSession();expect(vault.value,isNull);expect(repo.session,isNull);
    final remaining=jsonDecode(prefs.getString(ClassroomRepository.queueKey)!) as List;expect(remaining.single['student_id'],'another-pupil');
  });
  testWidgets('Unconfigured public service is clearly unavailable',(tester) async {
    await tester.pumpWidget(const MaterialApp(home:ClassroomPage()));
    expect(find.text('خدمة الربط العامة لم تُفعّل بعد'),findsOneWidget);
    expect(find.text('انضم إلى الغرفة'),findsNothing);
  });
}
