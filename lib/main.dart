import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'curriculum.dart';
export 'curriculum.dart';

void main() => runApp(const LearningApp());

class LearningApp extends StatelessWidget {
  const LearningApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false, title: 'أتعلم مع أخي',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6956D9)), useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF7F5FF),
      textTheme: const TextTheme(bodyLarge: TextStyle(fontSize: 19), bodyMedium: TextStyle(fontSize: 17))),
    locale: const Locale('ar'), supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const HomePage());
}

class ProgressStore extends ChangeNotifier {
  SharedPreferences? prefs;
  Set<int> completed = {};
  Map<String, int> attempts = {};
  Map<String, int> mistakes = {};
  String name = 'بطل المعرفة';
  int target = 2;
  String today = '';
  int todayCount = 0;
  bool ready = false;
  Future<void> load() async {
    prefs = await SharedPreferences.getInstance();
    completed = (prefs!.getStringList('completed_lessons') ?? []).map(int.tryParse).whereType<int>()
      .where((i) => i >= 0 && i < lessons.length).toSet();
    Map<String, int> readMap(String key) {
      try { return Map<String, int>.from(jsonDecode(prefs!.getString(key) ?? '{}') as Map); }
      catch (_) { return {}; }
    }
    attempts = readMap('attempts_v2'); mistakes = readMap('mistakes_v2');
    name = prefs!.getString('student_name') ?? name;
    target = (prefs!.getInt('daily_target') ?? 2).clamp(1, 5).toInt();
    today = DateTime.now().toIso8601String().substring(0, 10);
    todayCount = prefs!.getString('day') == today ? prefs!.getInt('day_count') ?? 0 : 0;
    ready = true; notifyListeners();
  }
  Future<void> record(int id, bool correct) async {
    final key = '$id';
    attempts[key] = (attempts[key] ?? 0) + 1;
    if (!correct) mistakes[key] = (mistakes[key] ?? 0) + 1;
    notifyListeners();
    await prefs!.setString('attempts_v2', jsonEncode(attempts));
    await prefs!.setString('mistakes_v2', jsonEncode(mistakes));
  }
  Future<void> finish(int id) async {
    if (!completed.add(id)) return;
    final date = DateTime.now().toIso8601String().substring(0, 10);
    if (date != today) { today = date; todayCount = 0; }
    todayCount++;
    notifyListeners();
    await prefs!.setStringList('completed_lessons', completed.map((i) => '$i').toList());
    await prefs!.setString('day', today); await prefs!.setInt('day_count', todayCount);
  }
  Future<void> settings(String value, int goal) async {
    name = value.trim().isEmpty ? 'بطل المعرفة' : value.trim(); target = goal;
    notifyListeners();
    await prefs!.setString('student_name', name); await prefs!.setInt('daily_target', goal);
  }
  @override
  void dispose() { super.dispose(); }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  final store = ProgressStore();
  @override void initState() { super.initState(); store.load(); }
  @override void dispose() { store.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) => Scaffold(
    appBar: AppBar(title: const Text('🌟 أتعلم مع أخي'), centerTitle: true),
    body: !store.ready ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(22), children: [
      const Center(child: Text('🦉 ⭐ 📚', style: TextStyle(fontSize: 60))),
      Text('مرحبًا يا ${store.name}!', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10), const Text('رحلة صغيرة كل يوم… وإنجاز كبير مع الأيام.'),
      const SizedBox(height: 20),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('نجوم المعرفة', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        Text('⭐ ${store.completed.length}   •   هدف اليوم: ${store.todayCount} / ${store.target}'),
        const SizedBox(height: 12), LinearProgressIndicator(value: store.completed.length / lessons.length, minHeight: 10),
        const SizedBox(height: 8), Text('${store.completed.length} من ${lessons.length} دروس'),
      ]))),
      const SizedBox(height: 20),
      FilledButton.icon(style: FilledButton.styleFrom(padding: const EdgeInsets.all(22)), icon: const Icon(Icons.school),
        label: const Text('ادخل كطالب', style: TextStyle(fontSize: 23)),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentPage(store: store)))),
      const SizedBox(height: 12),
      OutlinedButton.icon(icon: const Icon(Icons.bar_chart), label: const Text('لوحة المعلم'),
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherPage(store: store)))),
      const SizedBox(height: 18), const Text('٢٠٠ كلمة • الحروف • تركيب الكلمات • الإملاء • الحساب', textAlign: TextAlign.center),
      const SizedBox(height: 12), const Text('دروس تأسيسية من إعداد التطبيق، وليست مطابقة لكتاب مدرسي محدد. المتابعة محفوظة على هذا الجهاز.',
        textAlign: TextAlign.center, style: TextStyle(color: Colors.black54, fontSize: 13)),
    ])));
}

const categories = ['البداية','الحروف','القراءة','تركيب الكلمات','الإملاء','الحساب','للمراجعة'];
class StudentPage extends StatefulWidget {
  final ProgressStore store;
  const StudentPage({super.key, required this.store});
  @override State<StudentPage> createState() => _StudentPageState();
}
class _StudentPageState extends State<StudentPage> {
  String category = 'البداية';
  @override Widget build(BuildContext context) => ListenableBuilder(listenable: widget.store, builder: (context, _) {
    final ids = List.generate(lessons.length, (i) => i).where((i) => category == 'للمراجعة'
      ? (widget.store.mistakes['$i'] ?? 0) > 0 : lessons[i].category == category).toList();
    return Scaffold(appBar: AppBar(title: const Text('دروسي الممتعة 📚')),
      body: Column(children: [
        Padding(padding: const EdgeInsets.all(12), child: Wrap(spacing: 6, children: [for (final c in categories)
          ChoiceChip(label: Text(c), selected: category == c, onSelected: (_) => setState(() => category = c))])),
        Expanded(child: ids.isEmpty ? const Center(child: Text('لا توجد دروس للمراجعة بعد. أحسنت! ⭐')) : ListView.builder(
          padding: const EdgeInsets.all(14), itemCount: ids.length, itemBuilder: (context, position) {
            final id = ids[position]; final lesson = lessons[id]; final done = widget.store.completed.contains(id);
            return Card(child: ListTile(contentPadding: const EdgeInsets.all(12),
              leading: CircleAvatar(backgroundColor: done ? Colors.green.shade100 : null, child: Text(done ? '⭐' : '${position + 1}')),
              title: Text(lesson.title), subtitle: Text(lesson.words.isEmpty ? 'استمع، افهم، ثم جرّب' : '١٠ كلمات • خطوة بخطوة'),
              trailing: Icon(done ? Icons.check_circle : Icons.chevron_left, color: done ? Colors.green : null),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonPage(lesson: lesson, index: id, store: widget.store)))));
          })),
      ]));
  });
}

class LessonPage extends StatefulWidget {
  final Lesson lesson; final int index; final ProgressStore store;
  const LessonPage({super.key, required this.lesson, required this.index, required this.store});
  @override State<LessonPage> createState() => _LessonPageState();
}
class _LessonPageState extends State<LessonPage> {
  final tts = FlutterTts(); final answer = TextEditingController();
  late final Future<void> speechReady;
  int position = 0; int? selected; bool? correct; bool busy = false; bool completed = false;
  bool hint = false;
  List<int> order = []; List<int> picked = [];
  List<int> choiceOrder = [];
  @override void initState() {
    super.initState(); speechReady = configure();
    choiceOrder = List.generate(widget.lesson.choices.length, (i) => i)..shuffle(Random(widget.index + 73));
    prepareLetters();
  }
  Future<void> configure() async {
    try { await tts.setLanguage('ar-SA'); await tts.setSpeechRate(0.38); await tts.awaitSpeakCompletion(true); }
    catch (_) { /* Speech button will show a helpful message when pressed. */ }
  }
  String get word => widget.lesson.words[position];
  List<String> get letters => normalizeAnswer(word).split('');
  void prepareLetters() {
    if (widget.lesson.kind != ExerciseKind.blend) return;
    order = List.generate(letters.length, (i) => i)..shuffle(Random(widget.index * 23 + position));
    if (order.length > 1 && List.generate(order.length, (i) => i).every((i) => order[i] == i)) {
      order = [...order.skip(1), order.first];
    }
    picked = [];
  }
  Future<void> speak(String text) async {
    try {
      await speechReady;
      if (!mounted) return;
      await tts.stop();
      final result = await tts.speak(text);
      if (result != 1) throw StateError('speech unavailable');
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تشغيل الصوت. تحقق من الصوت العربي في إعدادات الجهاز.')));
    }
  }
  Future<void> check(bool result) async {
    if (busy || correct == true) return;
    setState(() { correct = result; busy = true; });
    await widget.store.record(widget.index, result);
    if (mounted) setState(() => busy = false);
  }
  Future<void> next() async {
    if (busy) return;
    if (widget.lesson.words.isNotEmpty && position + 1 < widget.lesson.words.length) {
      await tts.stop();
      if (!mounted) return;
      setState(() { position++; selected = null; correct = null; hint = false; answer.clear(); prepareLetters(); });
    } else {
      setState(() => busy = true);
      await widget.store.finish(widget.index);
      if (mounted) setState(() { completed = true; busy = false; });
    }
  }
  @override void dispose() { tts.stop(); answer.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) {
    final l = widget.lesson;
    if (completed) return Scaffold(appBar: AppBar(title: const Text('إنجاز جديد')),
      body: Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('🏆 ⭐ 🎉', style: TextStyle(fontSize: 60)), const SizedBox(height: 24),
        const Text('أحسنت! أكملت الدرس', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        const Text('كل محاولة تقرّبك من النجاح.'), const SizedBox(height: 24),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('العودة إلى دروسي')),
      ]))));
    final isChoice = l.kind == ExerciseKind.choice;
    final isReading = l.kind == ExerciseKind.reading;
    final isDictation = l.kind == ExerciseKind.dictation;
    return Scaffold(appBar: AppBar(title: Text(l.title)), body: ListView(padding: const EdgeInsets.all(20), children: [
      if (!isChoice) ...[
        Text('الكلمة ${position + 1} من ${l.words.length}', textAlign: TextAlign.center),
        const SizedBox(height: 10), LinearProgressIndicator(value: position / l.words.length),
      ],
      const SizedBox(height: 18), Text(l.explanation, style: const TextStyle(fontSize: 21, height: 1.6)),
      const SizedBox(height: 18),
      if (isChoice) ...[
        FilledButton.icon(onPressed: () => speak(l.explanation), icon: const Icon(Icons.volume_up), label: const Text('استمع إلى الشرح')),
        const SizedBox(height: 24), Text(l.question, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        const SizedBox(height: 14),
        for (final i in choiceOrder) Padding(padding: const EdgeInsets.only(bottom: 10), child: OutlinedButton(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(18), backgroundColor: selected == i ? (correct == true ? Colors.green.shade100 : Colors.orange.shade100) : null),
          onPressed: busy || correct == true ? null : () { setState(() => selected = i); check(i == l.correct); },
          child: Text(l.choices[i], style: const TextStyle(fontSize: 24)))),
      ] else ...[
        if (isReading || hint || correct == true) Card(child: Padding(padding: const EdgeInsets.all(26),
          child: Text(word, textAlign: TextAlign.center, style: const TextStyle(fontSize: 46, height: 1.5, fontWeight: FontWeight.bold)))),
        FilledButton.icon(onPressed: () => speak(word), icon: const Icon(Icons.volume_up), label: const Text('استمع إلى الكلمة', style: TextStyle(fontSize: 23))),
        const SizedBox(height: 20),
        if (isReading) ...[
          Text(normalizeAnswer(word).split('').join(' ـ '), textAlign: TextAlign.center, style: const TextStyle(fontSize: 30)),
          const SizedBox(height: 16),
          const Text('اقرأ بصوتك، ثم اضغط «قرأت الكلمة». التقييم هنا ذاتي ويمكن للمعلم مساعدتك.', style: TextStyle(fontSize: 15)),
          FilledButton(onPressed: busy ? null : () async { await check(true); if (mounted) await next(); }, child: const Text('قرأت الكلمة • التالي')),
        ] else if (isDictation) ...[
          TextField(controller: answer, enabled: correct != true, textAlign: TextAlign.center,
            autocorrect: false, enableSuggestions: false, style: const TextStyle(fontSize: 30),
            decoration: const InputDecoration(labelText: 'اكتب ما سمعت', border: OutlineInputBorder()),
            onSubmitted: (_) => check(normalizeAnswer(answer.text) == normalizeAnswer(word))),
          const SizedBox(height: 12), FilledButton(onPressed: busy || correct == true ? null : () => check(normalizeAnswer(answer.text) == normalizeAnswer(word)), child: const Text('تحقق من إجابتي')),
        ] else ...[
          Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
            child: Text(picked.isEmpty ? 'رتّب الحروف هنا' : picked.map((i) => letters[i]).join(), textAlign: TextAlign.center, style: const TextStyle(fontSize: 34))),
          const SizedBox(height: 18), Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [for (final i in order)
            FilledButton.tonal(onPressed: picked.contains(i) || correct == true ? null : () => setState(() { picked.add(i); correct = null; }),
              child: Text(letters[i], style: const TextStyle(fontSize: 30)))]),
          TextButton(onPressed: correct == true || picked.isEmpty ? null : () => setState(() { picked.removeLast(); correct = null; }), child: const Text('تراجع عن حرف')),
          FilledButton(onPressed: busy || correct == true || picked.length != letters.length ? null : () => check(picked.map((i) => letters[i]).join() == normalizeAnswer(word)), child: const Text('تحقق من الكلمة')),
        ],
        if (!isReading && correct != true) TextButton(onPressed: () => setState(() => hint = !hint), child: Text(hint ? 'إخفاء المساعدة' : 'أحتاج مساعدة: أظهر الكلمة')),
      ],
      if (correct != null && !isReading) Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Text(correct! ? 'أحسنت! إجابة صحيحة ⭐' : 'محاولة جميلة! جرّب مرة أخرى.',
        style: TextStyle(color: correct! ? Colors.green.shade800 : Colors.deepOrange, fontSize: 23, fontWeight: FontWeight.bold))),
      if (correct == true && !isReading) FilledButton(onPressed: busy ? null : next, child: Text(isChoice || position == l.words.length - 1 ? 'أكملت الدرس 🎉' : 'الكلمة التالية')),
      const SizedBox(height: 30),
    ]));
  }
}

class TeacherPage extends StatefulWidget {
  final ProgressStore store;
  const TeacherPage({super.key, required this.store});
  @override State<TeacherPage> createState() => _TeacherPageState();
}
class _TeacherPageState extends State<TeacherPage> {
  late final TextEditingController name;
  late int goal;
  @override void initState() { super.initState(); name = TextEditingController(text: widget.store.name); goal = widget.store.target; }
  @override void dispose() { name.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => ListenableBuilder(listenable: widget.store, builder: (context, _) {
    final s = widget.store;
    final attempts = s.attempts.values.fold(0, (a, b) => a + b);
    final errors = s.mistakes.values.fold(0, (a, b) => a + b);
    final review = s.mistakes.keys.map(int.tryParse).whereType<int>().where((i) => i >= 0 && i < lessons.length).toList()
      ..sort((a, b) => (s.mistakes['$b'] ?? 0).compareTo(s.mistakes['$a'] ?? 0));
    final report = '${s.name}\nالدروس المكتملة: ${s.completed.length} من ${lessons.length}\nالمحاولات: $attempts\nالمحاولات غير الصحيحة: $errors\n' +
      [for (final c in categories.where((c) => c != 'للمراجعة')) '$c: ${s.completed.where((i) => lessons[i].category == c).length} من ${lessons.where((l) => l.category == c).length}'].join('\n');
    return Scaffold(appBar: AppBar(title: const Text('لوحة المعلم 👩‍🏫')), body: ListView(padding: const EdgeInsets.all(22), children: [
      const Text('متابعة الطالب على هذا الجهاز', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 16), TextField(controller: name, maxLength: 30, decoration: const InputDecoration(labelText: 'اسم الطالب', border: OutlineInputBorder())),
      DropdownButtonFormField<int>(initialValue: goal, decoration: const InputDecoration(labelText: 'هدف الدروس اليومي'),
        items: List.generate(5, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1} دروس'))), onChanged: (v) => setState(() => goal = v ?? 2)),
      const SizedBox(height: 12), FilledButton(onPressed: () async { await s.settings(name.text, goal); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('حُفظت الإعدادات'))); }, child: const Text('حفظ الإعدادات')),
      const SizedBox(height: 24), Card(child: Padding(padding: const EdgeInsets.all(18), child: Text('⭐ ${s.completed.length} درسًا مكتملًا\nمحاولات الإجابة: $attempts\nمحاولات تحتاج مراجعة: $errors', style: const TextStyle(height: 1.8)))),
      for (final c in categories.where((c) => c != 'للمراجعة')) ...[
        const SizedBox(height: 14), Text('$c: ${s.completed.where((i) => lessons[i].category == c).length} / ${lessons.where((l) => l.category == c).length}'),
        LinearProgressIndicator(value: s.completed.where((i) => lessons[i].category == c).length / lessons.where((l) => l.category == c).length),
      ],
      const SizedBox(height: 24), const Text('دروس يُنصح بمراجعتها', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      if (review.isEmpty) const Text('لم تسجل محاولات غير صحيحة بعد.'),
      for (final i in review.take(8)) ListTile(title: Text(lessons[i].title), subtitle: Text('${s.mistakes['$i']} محاولات غير صحيحة')),
      const SizedBox(height: 20), OutlinedButton.icon(icon: const Icon(Icons.description), label: const Text('عرض تقرير قابل للنسخ'),
        onPressed: () => showDialog<void>(context: context, builder: (_) => AlertDialog(title: const Text('تقرير الطالب'), content: SingleChildScrollView(child: SelectableText(report)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))]))),
      const SizedBox(height: 22), const Text('إرشادات: ابدأ بالحروف، ثم القراءة، فتركيب الكلمات والإملاء. يُنجز الطفل ١٠ كلمات في كل درس. استمع لقراءته؛ التطبيق لا يسجّل الصوت ولا يقيم النطق آليًا.\n\nالقراءة تقييم ذاتي. إحصاءات الأخطاء تراكمية حتى بعد إعادة الدرس بنجاح. الربط بين أجهزة مختلفة غير متاح في هذه النسخة.', style: TextStyle(fontSize: 15, height: 1.7)),
    ]));
  });
}
