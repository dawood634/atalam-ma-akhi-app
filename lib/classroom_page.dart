import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'classroom_client.dart';
import 'unit_workspace.dart';

class ClassroomPage extends StatefulWidget {
  const ClassroomPage({super.key});
  @override State<ClassroomPage> createState() => _ClassroomPageState();
}
class _ClassroomPageState extends State<ClassroomPage> {
  ClassroomRepository? repository;
  List<Map<String,dynamic>> lessons = [];
  Map<String,dynamic>? report;
  final nickname = TextEditingController();
  final code = TextEditingController();
  final title = TextEditingController();
  final invitation = TextEditingController();
  bool teacherEntry = false; bool busy = false; String? error; String? notice;
  int pending = 0; String? chosenLesson;
  @override void initState() { super.initState(); if (ClassroomConnection.configured) initialize(); }
  @override void dispose() { nickname.dispose(); code.dispose(); title.dispose(); invitation.dispose(); super.dispose(); }
  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() { busy = true; error = null; notice = null; });
    try { await action(); }
    catch (e) { if (mounted) setState(() => error = e is ClassroomException ? e.message : 'تعذر إتمام العملية. بقيت النتائج المحلية محفوظة.'); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> initialize() => perform(() async {
    final data = jsonDecode(await rootBundle.loadString('content/sets_unit.json')) as Map;
    lessons = (data['lessons'] as List).map((l) => Map<String,dynamic>.from(l as Map)).toList();
    repository = await ClassroomConnection.repository();
    await update();
  });
  Future<void> update() async {
    final repo = repository!;
    if (repo.session == null) { report = null; pending = 0; return; }
    if (repo.session!['role'] == 'student') pending = await repo.pendingCount();
    await repo.refresh();
    if (repo.session!['role'] == 'student') {
      final result = await repo.flush(); pending = result.pending;
      notice = result.error ?? (result.sent > 0 ? 'تم إرسال ${result.sent} نتيجة إلى المعلم.' : null);
      report = null;
    } else { report = await repo.report(); }
    if (mounted) setState(() {});
  }
  Future<bool> confirmDeletion() async => await showDialog<bool>(context: context,builder: (context) => AlertDialog(
    title: const Text('حذف الربط والبيانات المتصلة؟'),
    content: Text(repository?.session?['role'] == 'teacher'
      ? 'سيُحذف الفصل المتصل مع الطلاب ونتائجهم، وتصبح رموز الدخول غير صالحة. تبقى التدريبات المحلية على كل جهاز. هذا الحذف لا يمكن التراجع عنه.'
      : 'سيُحذف ملفك ونتائجك من الغرفة، وتُزال النتائج المنتظرة للإرسال من هذا الجهاز. تبقى نتائج التدريبات المحلية. هذا الحذف لا يمكن التراجع عنه.'),
    actions: [TextButton(onPressed: () => Navigator.pop(context,false),child: const Text('إلغاء')),FilledButton(onPressed: () => Navigator.pop(context,true),child: const Text('حذف البيانات المتصلة'))],
  )) ?? false;
  String lessonTitle(String id) => lessons.where((l) => l['id'] == id).map((l) => l['title'] as String).firstOrNull ?? id;
  Future<void> openAssignment() async {
    final repo = repository!; final id = repo.session?['assignment'];
    final found = lessons.where((l) => l['id'] == id).toList();
    if (found.isEmpty) { setState(() => error = 'الدرس المكلّف غير موجود في حزمة هذا الإصدار.'); return; }
    await Navigator.push(context,MaterialPageRoute<void>(builder: (_) => UnitLessonPage(lesson: found.first,
      progress: UnitProgress(repo.prefs,onAttempt: repo.enqueue))));
    if (mounted) await perform(update);
  }
  @override Widget build(BuildContext context) {
    if (!ClassroomConnection.configured) return Scaffold(appBar: AppBar(title: const Text('غرف الطالب والمعلم')),body: const Padding(padding: EdgeInsets.all(24),child: Column(crossAxisAlignment: CrossAxisAlignment.start,children: [
      Icon(Icons.cloud_off_outlined,size:64),SizedBox(height:20),Text('خدمة الربط العامة لم تُفعّل بعد',style:TextStyle(fontSize:26,fontWeight:FontWeight.bold)),SizedBox(height:14),
      Text('تحتاج الغرف المتصلة إلى خادم مُهيأ. يمكنك متابعة الدروس والنتائج المحلية الآن؛ لا توجد متابعة من جهاز آخر في هذا الإصدار.',style:TextStyle(height:1.8)),
    ])));
    final session = repository?.session;
    return Scaffold(appBar: AppBar(title: Text(session?['role'] == 'teacher' ? 'غرفة المعلم' : session?['role'] == 'student' ? 'غرفتي الدراسية' : 'الانضمام إلى غرفة')),
      body: ListView(padding: const EdgeInsets.all(22),children: [
        const Text('نستخدم اسمًا مستعارًا، ولا نطلب بريد الطالب أو رقم هاتفه. تُحذف بيانات الغرفة عند انتهاء مدتها المحددة أو بحذفها من المعلم. خدمة الربط لا تجعل محتوى الدروس معتمدًا رسميًا.',style:TextStyle(fontSize:13,height:1.7)),
        const SizedBox(height:18), if (busy) const LinearProgressIndicator(),
        if (error != null) Padding(padding: const EdgeInsets.symmetric(vertical:12),child: Text(error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
        if (notice != null) Padding(padding: const EdgeInsets.symmetric(vertical:12),child: Text(notice!)),
        if (repository == null) OutlinedButton(onPressed: busy ? null : initialize,child: const Text('إعادة الاتصال')),
        if (repository != null && session == null) ...[
          SegmentedButton<bool>(segments: const [ButtonSegment(value:false,label:Text('طالب')),ButtonSegment(value:true,label:Text('معلم'))],selected:{teacherEntry},onSelectionChanged:busy ? null : (s) => setState(() => teacherEntry=s.first)),
          const SizedBox(height:18),
          if (!teacherEntry) ...[
            TextField(controller:code,maxLength:8,textCapitalization:TextCapitalization.characters,decoration:const InputDecoration(labelText:'رمز الغرفة',border:OutlineInputBorder())),
            const SizedBox(height:12),TextField(controller:nickname,maxLength:30,decoration:const InputDecoration(labelText:'اسمك المستعار في الغرفة',border:OutlineInputBorder())),
            FilledButton(onPressed:busy ? null : () => perform(() async {
              if (code.text.trim().length != 8 || nickname.text.trim().isEmpty) throw const ClassroomException('أدخل رمزًا من ثمانية أحرف واسمًا مستعارًا.');
              await repository!.join(code.text,nickname.text); await update();
            }),child:const Text('انضم إلى الغرفة')),
          ] else ...[
            TextField(controller:title,maxLength:60,decoration:const InputDecoration(labelText:'اسم الفصل',border:OutlineInputBorder())),
            const SizedBox(height:12),TextField(controller:invitation,obscureText:true,enableSuggestions:false,autocorrect:false,decoration:const InputDecoration(labelText:'دعوة إنشاء فصل للمعلم',border:OutlineInputBorder())),
            const Text('دعوة المعلم يصدرها مشرف المنصة. رمز غرفة الطالب لا يمنح صلاحيات المعلم.',style:TextStyle(fontSize:13,height:1.7)),
            FilledButton(onPressed:busy ? null : () => perform(() async {
              if (title.text.trim().isEmpty || invitation.text.length < 32) throw const ClassroomException('أدخل اسم الفصل ودعوة المعلم الصالحة.');
              await repository!.create(title.text.trim(),invitation.text); invitation.clear(); await update();
            }),child:const Text('إنشاء فصل')),
          ],
        ],
        if (session != null) ...[
          Text(session['room']['title'] as String,style:const TextStyle(fontSize:28,fontWeight:FontWeight.bold)),
          const SizedBox(height:12),
          Text('ينتهي ربط الغرفة في ${DateTime.fromMillisecondsSinceEpoch((session['room']['expires'] as num).toInt() * 1000).toLocal().toIso8601String().split('T').first}'),
          if (session['role'] == 'teacher') ...[
            const Text('شارك رمز الانضمام مع طلاب الفصل فقط.'),
            SelectableText(session['room']['join_code'] as String,style:const TextStyle(fontSize:32,letterSpacing:3),textDirection:TextDirection.ltr),
            OutlinedButton(onPressed:busy ? null : () => perform(() async { await repository!.rotateCode(); notice='تغير الرمز. الطلاب المرتبطون سابقًا يحتفظون بربطهم.'; }),child:const Text('تغيير رمز الانضمام')),
            const SizedBox(height:18),DropdownButtonFormField<String>(initialValue:chosenLesson,decoration:const InputDecoration(labelText:'اختر درسًا لتكليف الفصل',border:OutlineInputBorder()),
              items:lessons.map((l) => DropdownMenuItem(value:l['id'] as String,child:Text(l['title'] as String))).toList(),onChanged:busy ? null : (v) => setState(() => chosenLesson=v)),
            FilledButton(onPressed:busy || chosenLesson == null ? null : () => perform(() async { await repository!.assign(chosenLesson!); notice='تم تعيين الدرس للفصل.'; }),child:const Text('إرسال التكليف')),
            const SizedBox(height:18),const Text('نتائج الفصل',style:TextStyle(fontSize:24,fontWeight:FontWeight.bold)),
            if ((report?['students'] as List? ?? []).isEmpty) const Text('لم ينضم طلاب بعد.'),
            for (final student in (report?['students'] as List? ?? [])) Card(child:ExpansionTile(title:Text(student['nickname'] as String),children:[
              if ((student['lessons'] as Map).isEmpty) const ListTile(title:Text('لم تصل نتائج اختبارات بعد.')),
              for (final item in (student['lessons'] as Map).entries) ListTile(title:Text(lessonTitle(item.key as String)),subtitle:Text('الأخيرة ${item.value['last']}/${item.value['total']} • الأفضل ${item.value['best']}/${item.value['total']} • المحاولات ${item.value['attempts']}')),
            ])),
          ] else ...[
            Text('مرحبًا ${session['student']['nickname']}'),Text('نتائج تنتظر الإرسال: $pending'),
            const SizedBox(height:16),Text(session['assignment'] == null ? 'لا يوجد تكليف حاليًا.' : 'التكليف: ${lessonTitle(session['assignment'] as String)}'),
            if (session['assignment'] != null) FilledButton.icon(onPressed:busy ? null : openAssignment,icon:const Icon(Icons.play_arrow),label:const Text('ابدأ الدرس المكلّف')),
            const Text('يمكن حل الدروس دون اتصال. تُرسل النتائج المنتظرة عند فتح هذه الغرفة أو الضغط على المزامنة. لا تُرفع اختبارات سابقة لم تُحفظ إجاباتها مع الربط.',style:TextStyle(fontSize:13,height:1.7)),
          ],
          const SizedBox(height:20),OutlinedButton.icon(onPressed:busy ? null : () => perform(update),icon:const Icon(Icons.sync),label:const Text('تحديث ومزامنة')),
          TextButton(onPressed:busy ? null : () async { if (await confirmDeletion()) { await perform(() async { await repository!.deleteRemoteSession(); report=null; pending=0; }); } },child:Text(session['role'] == 'teacher' ? 'حذف الفصل وبياناته المتصلة' : 'حذف ملفي من الغرفة')),
          const Text('الجلسة محفوظة على هذا الجهاز. استعادة جلسة بعد حذف التطبيق أو فقد الجهاز غير متاحة بعد؛ نظام الاستعادة ضمن متطلبات الإطلاق النهائي.',style:TextStyle(fontSize:12,height:1.6)),
        ],
      ]));
  }
}
