import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ClassroomException implements Exception {
  final String message;
  final int? status;
  const ClassroomException(this.message, [this.status]);
  @override String toString() => message;
}

abstract class SessionVault {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> clear();
}
class SecureSessionVault implements SessionVault {
  final FlutterSecureStorage storage;
  SecureSessionVault({FlutterSecureStorage? storage}) : storage = storage ?? const FlutterSecureStorage();
  static const key = 'classroom_session_v1';
  @override Future<String?> read() => storage.read(key: key);
  @override Future<void> write(String value) => storage.write(key: key, value: value);
  @override Future<void> clear() => storage.delete(key: key);
}

abstract class ClassroomTransport {
  Future<Map<String,dynamic>> request(String method, Uri uri, Map<String,String> headers, Map<String,dynamic>? body);
}
class IoClassroomTransport implements ClassroomTransport {
  @override Future<Map<String,dynamic>> request(String method, Uri uri, Map<String,String> headers, Map<String,dynamic>? body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.openUrl(method,uri).timeout(const Duration(seconds: 12));
      request.followRedirects = false;
      headers.forEach(request.headers.set);
      request.headers.contentType = ContentType.json;
      if (body != null) request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 12));
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk);
        if (bytes.length > 512 * 1024) throw const ClassroomException('حجم استجابة الخادم غير متوقع.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        const messages = {400:'تحقق من البيانات المدخلة.',401:'انتهت جلسة الربط أو لم تعد صالحة.',403:'هذه العملية تحتاج صلاحية المعلم.',404:'رمز الغرفة غير صحيح أو انتهت صلاحيته.',409:'الاسم مستخدم في الغرفة أو تعارض الطلب. تحقق من البيانات.',429:'طلبات كثيرة؛ انتظر دقيقة ثم أعد المحاولة.',503:'خدمة الغرف غير متاحة الآن.'};
        throw ClassroomException(messages[response.statusCode] ?? 'تعذر إتمام الطلب.',response.statusCode);
      }
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<String,dynamic>) throw const ClassroomException('استجابة الخادم غير صالحة.');
      return decoded;
    } on ClassroomException { rethrow; }
    on SocketException { throw const ClassroomException('لا يوجد اتصال بالخادم. النتائج المحفوظة تبقى على الجهاز.'); }
    on TimeoutException { throw const ClassroomException('تأخر الاتصال بالخادم. أعد المحاولة لاحقًا.'); }
    on FormatException { throw const ClassroomException('استجابة الخادم غير صالحة.'); }
    finally { client.close(force: true); }
  }
}

class ClassroomApi {
  final Uri base;
  final ClassroomTransport transport;
  ClassroomApi(String endpoint,{ClassroomTransport? transport,bool allowLocalTest=false})
      : base = Uri.parse(endpoint), transport = transport ?? IoClassroomTransport() {
    final localTest = allowLocalTest && base.scheme == 'http' && ['127.0.0.1','localhost','::1'].contains(base.host);
    if ((base.scheme != 'https' && !localTest) || base.host.isEmpty || base.userInfo.isNotEmpty || base.hasQuery || base.hasFragment || !['','/'].contains(base.path)) {
      throw const ClassroomException('عنوان خدمة الغرف يجب أن يكون أصل HTTPS صالحًا.');
    }
  }
  String get origin => base.origin;
  Future<Map<String,dynamic>> call(String method,String path,{String? token,String? invite,Map<String,dynamic>? body}) {
    if (!path.startsWith('/v1/') || path.contains('..') || path.contains('?')) throw ArgumentError('Invalid API path');
    return transport.request(method,base.replace(path:path),{
      if (token != null) 'Authorization':'Bearer $token',
      if (invite != null) 'X-Teacher-Invite':invite,
    },body);
  }
}

class SyncResult {
  final int sent;
  final int pending;
  final String? error;
  const SyncResult(this.sent,this.pending,[this.error]);
}

class ClassroomRepository {
  final ClassroomApi api;
  final SessionVault vault;
  final SharedPreferences prefs;
  Map<String,dynamic>? session;
  bool _loaded = false;
  Future<void> _queueLock = Future<void>.value();
  Future<SyncResult>? _syncing;
  ClassroomRepository(this.api,this.vault,this.prefs);
  static const queueKey = 'classroom_outbox_v1';
  String? get studentId => session?['student']?['id'] as String?;

  Map<String,dynamic> validateSession(Map<String,dynamic> data) {
    final role = data['role']; final token = data['token']; final room = data['room'];
    if (!['teacher','student'].contains(role) || token is! String || token.length < 32 || token.length > 120 || room is! Map || room['id'] is! String || (role == 'student' && (data['student'] is! Map || data['student']['id'] is! String))) {
      throw const ClassroomException('بيانات جلسة الربط غير صالحة.');
    }
    return data;
  }
  Future<void> load() async {
    if (_loaded) return;
    final raw = await vault.read();
    if (raw != null) {
      final saved = jsonDecode(raw) as Map<String,dynamic>;
      if (saved['origin'] != api.origin) throw const ClassroomException('الخادم المحفوظ يختلف عن خدمة هذا الإصدار؛ يلزم فصل الجلسة القديمة أولًا.');
      session = validateSession(saved);
    }
    _loaded = true;
  }
  Future<void> saveSession(Map<String,dynamic> data) async {
    final value = validateSession({...data,'origin':api.origin});
    await vault.write(jsonEncode(value));
    session = value; _loaded = true;
  }
  Future<void> create(String title,String invitation) async {
    if (session != null) throw const ClassroomException('هذا الجهاز مرتبط بالفعل بغرفة.');
    final data = await api.call('POST','/v1/rooms',invite:invitation,body:{'title':title});
    await saveSession(data);
  }
  Future<void> join(String code,String nickname) async {
    if (session != null) throw const ClassroomException('هذا الجهاز مرتبط بالفعل بغرفة.');
    final data = await api.call('POST','/v1/join',body:{'code':code.trim().toUpperCase(),'nickname':nickname.trim()});
    await saveSession(data);
  }
  Future<void> refresh() async {
    await load(); if (session == null) return;
    final result = await api.call('GET','/v1/session',token:session!['token'] as String);
    if (result['role'] != session!['role'] || result['room']?['id'] != session!['room']['id'] || (result['role'] == 'student' && result['student']?['id'] != studentId)) {
      throw const ClassroomException('تغيرت هوية الجلسة في استجابة الخادم.');
    }
    await saveSession({...result,'token':session!['token']});
  }
  Future<Map<String,dynamic>> report() => api.call('GET','/v1/report',token:session!['token'] as String);
  Future<void> assign(String lessonId) async {
    await api.call('POST','/v1/assignment',token:session!['token'] as String,body:{'lesson_id':lessonId});
    await refresh();
  }
  Future<void> rotateCode() async {
    final result = await api.call('POST','/v1/rotate-code',token:session!['token'] as String,body:{});
    await saveSession({...session!, 'room':{...Map<String,dynamic>.from(session!['room'] as Map), 'join_code':result['join_code']}});
  }
  Future<T> withQueue<T>(Future<T> Function() action) {
    final result = _queueLock.then((_) => action());
    _queueLock = result.then<void>((_) {},onError:(Object _,StackTrace __) {});
    return result;
  }
  List<Map<String,dynamic>> readQueue() {
    final raw = prefs.getString(queueKey);
    if (raw == null) return [];
    try { return (jsonDecode(raw) as List).map((e) => Map<String,dynamic>.from(e as Map)).toList(); }
    catch (_) { throw const ClassroomException('قائمة النتائج المنتظرة غير قابلة للقراءة؛ لم نحذفها.'); }
  }
  Future<int> pendingCount() => withQueue(() async => readQueue().where((e) => e['student_id'] == studentId).length);
  Future<bool> enqueue(String lessonId,List<int> answers) async {
    await load();
    if (session?['role'] != 'student') return false;
    return withQueue(() async {
      final queue = readQueue();
      if (queue.where((e) => e['student_id'] == studentId).length >= 200) throw const ClassroomException('وصلت النتائج المنتظرة إلى الحد المتاح. افتح الغرفة لمزامنتها.');
      final random = Random.secure();
      final requestId = base64Url.encode(List<int>.generate(18,(_) => random.nextInt(256))).replaceAll('=','');
      queue.add({'student_id':studentId,'request_id':requestId,'lesson_id':lessonId,'answers':List<int>.from(answers)});
      await prefs.setString(queueKey,jsonEncode(queue));
      return true;
    });
  }
  Future<SyncResult> flush() {
    final existing = _syncing; if (existing != null) return existing;
    final operation = _flush(); _syncing = operation;
    return operation.whenComplete(() { _syncing = null; });
  }
  Future<SyncResult> _flush() async {
    await load();
    if (studentId == null) return const SyncResult(0,0);
    final identity = studentId;
    final token = session!['token'] as String;
    final snapshot = await withQueue(() async => readQueue().where((e) => e['student_id'] == identity).toList());
    var sent = 0; String? error;
    for (final entry in snapshot) {
      try {
        final result = await api.call('POST','/v1/attempts',token:token,body:{'request_id':entry['request_id'],'lesson_id':entry['lesson_id'],'answers':entry['answers']});
        if (result['request_id'] != entry['request_id']) throw const ClassroomException('لم يؤكد الخادم حفظ هذه النتيجة.');
        await withQueue(() async {
          final current = readQueue()..removeWhere((e) => e['student_id'] == identity && e['request_id'] == entry['request_id']);
          await prefs.setString(queueKey,jsonEncode(current));
        });
        sent++;
      } catch (e) { error = e is ClassroomException ? e.message : 'تعذر إرسال النتيجة. ستبقى محفوظة للمحاولة التالية.'; break; }
    }
    final pending = await withQueue(() async => readQueue().where((e) => e['student_id'] == identity).length);
    return SyncResult(sent,pending,error);
  }
  Future<void> deleteRemoteSession() async {
    await load(); if (session == null) return;
    try { await api.call('DELETE','/v1/session',token:session!['token'] as String); }
    on ClassroomException catch (e) { if (e.status != 401) rethrow; }
    final identity = studentId;
    await withQueue(() async {
      final current = readQueue()..removeWhere((e) => e['student_id'] == identity);
      await prefs.setString(queueKey,jsonEncode(current));
    });
    await vault.clear(); session = null;
  }
}

class ClassroomConnection {
  static const endpoint = String.fromEnvironment('CLASSROOM_API_URL');
  static Future<ClassroomRepository>? _repository;
  static bool get configured => endpoint.isNotEmpty;
  static Future<ClassroomRepository> repository() {
    if (!configured) throw const ClassroomException('لم تُفعّل خدمة الغرف العامة بعد.');
    return _repository ??= _create();
  }
  static Future<ClassroomRepository> _create() async {
    final repo = ClassroomRepository(ClassroomApi(endpoint),SecureSessionVault(),await SharedPreferences.getInstance());
    await repo.load(); return repo;
  }
  static Future<bool> queueAnswers(String lesson,List<int> answers) async {
    if (!configured) return false;
    return (await repository()).enqueue(lesson,answers);
  }
}
