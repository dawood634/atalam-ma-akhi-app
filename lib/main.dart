import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const LearningApp());

class LearningApp extends StatelessWidget {
  const LearningApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'أتعلم مع أخي',
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF6856D9)), useMaterial3: true, scaffoldBackgroundColor: const Color(0xFFF8F7FF)),
    locale: const Locale('ar'),
    supportedLocales: const [Locale('ar')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    builder: (context, child) => Directionality(textDirection: TextDirection.rtl, child: child!),
    home: const HomePage(),
  );
}

class Lesson {
  final String title, explanation, question;
  final List<String> choices;
  final int correct;
  const Lesson(this.title, this.explanation, this.question, this.choices, this.correct);
}

const lessons = <Lesson>[
  Lesson('حرف الباء', 'هذا حرف الباء: ب. نقول: بَ، بِ، بُ. كلمة باب تبدأ بحرف الباء.', 'أي كلمة تبدأ بحرف الباء؟', ['قلم', 'باب', 'شمس'], 1),
  Lesson('نركّب كلمة', 'نقرأ الحروف معًا: كَ، تَ، بَ. كَتَبَ.', 'ما الكلمة الناتجة من كَ + تَ + بَ؟', ['كَتَبَ', 'لَعِبَ', 'شَرِبَ'], 0),
  Lesson('حرف الميم', 'هذا حرف الميم: م. نقول: مَ، مِ، مُ. كلمة موز تبدأ بالميم.', 'أي كلمة تبدأ بحرف الميم؟', ['بيت', 'قمر', 'موز'], 2),
  Lesson('الجمع البسيط', 'لدينا تفاحتان، وأضفنا تفاحة. أصبح لدينا ثلاث تفاحات.', '🍎 🍎 + 🍎 = ؟', ['٢', '٣', '٤'], 1),
  Lesson('الطرح البسيط', 'لدينا أربع كرات. أخذنا كرة واحدة. بقيت ثلاث كرات.', '٤ − ١ = ؟', ['٣', '٢', '١'], 0),
  Lesson('الإملاء: باب', 'استمع إلى الكلمة، ثم اختر كتابتها الصحيحة.', 'اختر كتابة كلمة «باب» الصحيحة.', ['تاب', 'باب', 'ناب'], 1),
  Lesson('القراءة: بيت', 'نقرأ: بَ + يْ + ت = بَيْت.', 'اختر الكلمة التي قرأناها.', ['بيت', 'بنت', 'زيت'], 0),
  Lesson('الأعداد', 'نتعلم ترتيب الأعداد: واحد، اثنان، ثلاثة، أربعة، خمسة.', 'ما العدد الذي يأتي بعد ٤؟', ['٣', '٦', '٥'], 2),
  Lesson('حرف السين', 'هذا حرف السين: س. كلمة سمك تبدأ بحرف السين.', 'أي كلمة تبدأ بحرف السين؟', ['سمك', 'قلم', 'وردة'], 0),
  Lesson('المقارنة', 'عندما يكون لدينا خمسة أقلام، فهي أكثر من ثلاثة أقلام.', 'أي العددين أكبر؟', ['٣', '٥', 'متساويان'], 1),
];

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String curriculum = 'صنعاء';
  int grade = 1;
  Set<int> completedLessons = {};
  int get completed => completedLessons.length;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    final stored = p.getStringList('completed_lessons') ?? <String>[];
    final valid = stored.map(int.tryParse).whereType<int>().where((i) => i >= 0 && i < lessons.length).toSet();
    if (mounted) setState(() => completedLessons = valid);
  }
  Future<void> _saveProgress(int index) async {
    if (index < 0 || index >= lessons.length || completedLessons.contains(index)) return;
    final updated = {...completedLessons, index};
    if (mounted) setState(() => completedLessons = updated);
    final p = await SharedPreferences.getInstance();
    await p.setStringList('completed_lessons', updated.map((i) => '$i').toList());
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('🌟 أتعلم مع أخي'), centerTitle: true),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('مرحبًا بك يا بطل! 👋', style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('نتعلم خطوة بخطوة، ونفرح بكل إنجاز.'),
      const SizedBox(height: 24),
      const Text('اختر المنهج', style: TextStyle(fontWeight: FontWeight.bold)),
      SegmentedButton<String>(segments: const [ButtonSegment(value: 'صنعاء', label: Text('صنعاء')), ButtonSegment(value: 'عدن', label: Text('عدن'))], selected: {curriculum}, onSelectionChanged: (v) => setState(() => curriculum = v.first)),
      const SizedBox(height: 18),
      const Text('اختر الصف', style: TextStyle(fontWeight: FontWeight.bold)),
      DropdownButtonFormField<int>(value: grade, items: List.generate(6, (i) => DropdownMenuItem(value: i + 1, child: Text('الصف ${i + 1}'))), onChanged: (v) => setState(() => grade = v ?? 1)),
      const SizedBox(height: 20),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('تقدمك في الدروس التجريبية', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 10), LinearProgressIndicator(value: completed / lessons.length, minHeight: 12, borderRadius: BorderRadius.circular(20)),
        const SizedBox(height: 8), Text('$completed من ${lessons.length} دروس'),
      ]))),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => StudentPage(onComplete: _saveProgress))), icon: const Icon(Icons.school), label: const Text('ادخل كطالب'), style: FilledButton.styleFrom(padding: const EdgeInsets.all(18))),
      const SizedBox(height: 10),
      OutlinedButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => TeacherPage(completed: completed))), icon: const Icon(Icons.bar_chart), label: const Text('لوحة المعلم')),
      const SizedBox(height: 18),
      const Text('تنبيه: هذه دروس تجريبية تأسيسية مشتركة، وليست محتوى رسميًا مطابقًا بعد لمنهجي صنعاء وعدن أو لجميع الصفوف.', style: TextStyle(color: Colors.black54, fontSize: 12)),
    ]),
  );
}

class StudentPage extends StatelessWidget {
  final Future<void> Function(int) onComplete;
  const StudentPage({super.key, required this.onComplete});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('دروسي الممتعة 📚')),
    body: ListView.builder(padding: const EdgeInsets.all(16), itemCount: lessons.length, itemBuilder: (context, index) => Card(child: ListTile(
      leading: CircleAvatar(child: Text('${index + 1}')),
      title: Text(lessons[index].title), subtitle: const Text('استمع، افهم، ثم جرّب'), trailing: const Icon(Icons.arrow_back_ios_new),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LessonPage(lesson: lessons[index], index: index, onComplete: onComplete))),
    ))),
  );
}

class LessonPage extends StatefulWidget {
  final Lesson lesson;
  final int index;
  final Future<void> Function(int) onComplete;
  const LessonPage({super.key, required this.lesson, required this.index, required this.onComplete});
  @override
  State<LessonPage> createState() => _LessonPageState();
}

class _LessonPageState extends State<LessonPage> {
  final FlutterTts tts = FlutterTts();
  int? selected;
  bool saved = false;
  @override
  void initState() { super.initState(); _prepareSpeech(); }
  late final Future<void> speechReady;
  void _prepareSpeech() { speechReady = _configureSpeech(); }
  Future<void> _configureSpeech() async {
    await tts.setLanguage('ar-SA');
    await tts.setSpeechRate(0.42);
  }
  Future<void> speak(String text) async {
    try {
      await speechReady;
      if (!mounted) return;
      await tts.stop();
      await tts.speak(text);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر تشغيل الصوت. تأكد من تثبيت صوت عربي في إعدادات الجهاز.')));
    }
  }
  @override
  void dispose() { tts.stop(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final l = widget.lesson;
    final correct = selected == l.correct;
    return Scaffold(appBar: AppBar(title: Text(l.title)), body: ListView(padding: const EdgeInsets.all(20), children: [
      const Text('🎧 استمع إلى الشرح', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      Card(child: Padding(padding: const EdgeInsets.all(20), child: Text(l.explanation, style: const TextStyle(fontSize: 23, height: 1.8)))),
      FilledButton.icon(onPressed: () => speak(l.explanation), icon: const Icon(Icons.volume_up), label: const Text('اسمع الشرح مرة أخرى')),
      const SizedBox(height: 30), Text(l.question, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const SizedBox(height: 14),
      ...List.generate(l.choices.length, (i) => Padding(padding: const EdgeInsets.only(bottom: 10), child: OutlinedButton(
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(17), backgroundColor: selected == i ? (correct ? Colors.green.shade100 : Colors.orange.shade100) : null),
        onPressed: () async {
          setState(() => selected = i);
          if (i == l.correct && !saved) { saved = true; await widget.onComplete(widget.index); }
        },
        child: Text(l.choices[i], style: const TextStyle(fontSize: 22)),
      ))),
      if (selected != null) Text(correct ? 'أحسنت! إجابة صحيحة ⭐' : 'حاول مرة أخرى، واستمع للشرح مجددًا 💪', style: TextStyle(color: correct ? Colors.green.shade800 : Colors.deepOrange, fontWeight: FontWeight.bold, fontSize: 19)),
      if (correct) FilledButton(onPressed: () => Navigator.pop(context), child: const Text('أكملت الدرس 🎉')),
    ]));
  }
}

class TeacherPage extends StatelessWidget {
  final int completed;
  const TeacherPage({super.key, required this.completed});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('لوحة المعلم 👩‍🏫')), body: ListView(padding: const EdgeInsets.all(20), children: [
    const Text('متابعة الطالب على هذا الجهاز', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
    const SizedBox(height: 12), Text('الدروس المكتملة: $completed من ${lessons.length}', style: const TextStyle(fontSize: 18)),
    const SizedBox(height: 15), LinearProgressIndicator(value: completed / lessons.length, minHeight: 14),
    const SizedBox(height: 22), const Text('هذه لوحة متابعة أولية. الربط بين أجهزة الطالب والمعلم يحتاج خدمة مزامنة آمنة في إصدار لاحق.'),
  ]));
}
