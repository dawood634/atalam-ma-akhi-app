import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

String normalizeArabic(String text) => text.toLowerCase()
    .replaceAll(RegExp(r'[\u064B-\u065F\u0670ـ]'), '')
    .replaceAll(RegExp('[أإآ]'), 'ا').replaceAll('ى', 'ي');

class UnitProgress {
  final SharedPreferences prefs;
  UnitProgress(this.prefs);
  Map<String, dynamic> get records {
    try { return Map<String, dynamic>.from(jsonDecode(prefs.getString('unit_progress_v1') ?? '{}') as Map); }
    catch (_) { return {}; }
  }
  Future<void> record(String id, int score, int total) async {
    if (total <= 0 || score < 0 || score > total) throw ArgumentError('Invalid score');
    final data = records;
    final previous = data[id] is Map ? Map<String, dynamic>.from(data[id] as Map) : <String,dynamic>{};
    data[id] = {'last': score, 'total': total,
      'best': (previous['best'] as int? ?? 0) > score ? previous['best'] : score,
      'attempts': (previous['attempts'] as int? ?? 0) + 1,
      'at': DateTime.now().toIso8601String()};
    await prefs.setString('unit_progress_v1', jsonEncode(data));
  }
  Set<String> get bookmarks => (prefs.getStringList('unit_bookmarks_v1') ?? []).toSet();
  Future<void> bookmark(String id) async {
    final items = bookmarks;
    if (!items.add(id)) items.remove(id);
    await prefs.setStringList('unit_bookmarks_v1', items.toList());
  }
  String? get assignment => prefs.getString('unit_assignment_v1');
  Future<void> assign(String id) async { await prefs.setString('unit_assignment_v1', id); }
}

class UnitWorkspace extends StatefulWidget {
  const UnitWorkspace({super.key});
  @override State<UnitWorkspace> createState() => _UnitWorkspaceState();
}
class _UnitWorkspaceState extends State<UnitWorkspace> {
  Map<String,dynamic>? unit;
  UnitProgress? progress;
  String query = ''; bool teacher = false; bool savedOnly = false; bool failed = false;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final data = jsonDecode(await rootBundle.loadString('content/sets_unit.json')) as Map<String,dynamic>;
      final prefs = await SharedPreferences.getInstance();
      if (mounted) setState(() { unit = data; progress = UnitProgress(prefs); failed = false; });
    } catch (_) { if (mounted) setState(() => failed = true); }
  }
  List<Map<String,dynamic>> get lessons => (unit!['lessons'] as List).map((e) => Map<String,dynamic>.from(e as Map)).toList();
  Future<void> open(Map<String,dynamic> lesson) async {
    await Navigator.push(context, MaterialPageRoute<void>(builder: (_) => UnitLessonPage(lesson: lesson, progress: progress!)));
    if (mounted) setState(() {});
  }
  String report() {
    final lines = ['أتعلم مع أخي • تقرير هذا الجهاز', 'رياضيات السابع • الوحدة الأولى • مسودات تعليمية', 'هذه النتائج تخص اختبارات التطبيق الأصلية، ولا تمثل تغطية المنهج الرسمي.'];
    for (final l in lessons) {
      final r = progress!.records[l['id']];
      lines.add(r == null ? '${l['title']}: لم يختبر بعد' : '${l['title']}: آخر نتيجة ${r['last']}/${r['total']}، الأفضل ${r['best']}/${r['total']}، المحاولات ${r['attempts']}');
    }
    return lines.join('\n');
  }
  @override Widget build(BuildContext context) {
    if (unit == null) return Scaffold(appBar: AppBar(title: const Text('مساحة التعلم')), body: Center(child: failed
      ? FilledButton(onPressed: load, child: const Text('إعادة تحميل الوحدة')) : const CircularProgressIndicator()));
    final records = progress!.records;
    final done = lessons.where((l) => records.containsKey(l['id'])).length;
    final matches = lessons.where((l) => (!savedOnly || progress!.bookmarks.contains(l['id'])) &&
      normalizeArabic('${l['title']} ${l['objective']} ${l['explanation']}').contains(normalizeArabic(query))).toList();
    return Scaffold(appBar: AppBar(title: Text(teacher ? 'مساحة المعلم' : 'مساحة الطالب'), actions: [
      TextButton(onPressed: () => setState(() => teacher = !teacher), child: Text(teacher ? 'إلى الطالب' : 'إلى المعلم')),
    ]), body: ListView(padding: const EdgeInsets.all(20), children: [
      Text(teacher ? 'تابع الفهم… وحدد الخطوة التالية' : 'رحلتك مع المجموعات', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12), const Text('رياضيات السابع • ١٠ دروس • ٣٠ سؤالًا\nمتاح دون اتصال بعد التثبيت', style: TextStyle(height: 1.7)),
      const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('شروح أصلية وفق ترتيب موضوعات عينة قديمة. مطابقة طبعات صنعاء وعدن الحالية ومراجعة المعلم المستقل لم تعتمد بعد. هذه وحدة واحدة، وليست جميع المناهج.', style: TextStyle(height: 1.6)))),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('أنجزت اختبار $done من ${lessons.length} دروس'), const SizedBox(height: 10),
        LinearProgressIndicator(value: done / lessons.length), const SizedBox(height: 8),
        const Text('إنجاز الاختبار لا يعني إتقانه؛ راجع آخر نتيجة وأفضل نتيجة.'),
      ]))),
      if (teacher) ...[
        const Text('هذه لوحة محلية على الجهاز نفسه. لا يوجد حساب معلم أو رمز غرفة أو متابعة عن بُعد، وزر تبديل الواجهة ليس قفل صلاحيات.', style: TextStyle(fontSize: 13, height: 1.6)),
        const SizedBox(height: 10), OutlinedButton.icon(icon: const Icon(Icons.copy), label: const Text('نسخ تقرير النتائج'), onPressed: () async {
          await Clipboard.setData(ClipboardData(text: report()));
          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('نُسخ التقرير، ويمكنك لصقه في رسالة أو ملف.')));
        }),
      ],
      const SizedBox(height: 18), TextField(decoration: const InputDecoration(labelText: 'ابحث في دروس الوحدة', prefixIcon: Icon(Icons.search), border: OutlineInputBorder()), onChanged: (v) => setState(() => query = v)),
      const SizedBox(height: 10), FilterChip(label: const Text('المحفوظات فقط'), selected: savedOnly, onSelected: (v) => setState(() => savedOnly = v)),
      if (matches.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Text('لا توجد دروس مطابقة. غيّر البحث أو ألغِ تصفية المحفوظات.')),
      for (final lesson in matches) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(contentPadding: EdgeInsets.zero, title: Text(lesson['title'] as String, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text(lesson['objective'] as String), trailing: IconButton(tooltip: progress!.bookmarks.contains(lesson['id']) ? 'إزالة من المحفوظات' : 'حفظ الدرس',
            icon: Icon(progress!.bookmarks.contains(lesson['id']) ? Icons.bookmark : Icons.bookmark_border), onPressed: () async {
              await progress!.bookmark(lesson['id'] as String); if (mounted) setState(() {});
            })),
        if (progress!.assignment == lesson['id']) const Chip(avatar: Icon(Icons.assignment, size: 18), label: Text('الدرس المكلّف به حاليًا')),
        if (records[lesson['id']] != null) Text('آخر نتيجة: ${records[lesson['id']]['last']}/3 • أفضل نتيجة: ${records[lesson['id']]['best']}/3'),
        Wrap(spacing: 10, children: [FilledButton(onPressed: () => open(lesson), child: const Text('افتح الدرس')),
          if (teacher) OutlinedButton(onPressed: () async { await progress!.assign(lesson['id'] as String); if (mounted) setState(() {}); }, child: const Text('تكليف بهذا الدرس'))]),
      ]))),
      ExpansionTile(title: const Text('مرجع الوحدة وحدود المراجعة'), children: [SelectableText('${unit!['reference_edition']}\nمواضع الموضوعات من فهرس العينة، والشرح والأمثلة والأسئلة أصلية.\n${unit!['notes']}\n${unit!['reference_url']}')]),
    ]));
  }
}

class UnitLessonPage extends StatefulWidget {
  final Map<String,dynamic> lesson;
  final UnitProgress progress;
  const UnitLessonPage({super.key, required this.lesson, required this.progress});
  @override State<UnitLessonPage> createState() => _UnitLessonPageState();
}
class _UnitLessonPageState extends State<UnitLessonPage> {
  int index = 0; int? chosen; int score = 0; bool finished = false; bool saving = false; String? error;
  List get questions => widget.lesson['questions'] as List;
  Future<void> next() async {
    if (index < questions.length - 1) { setState(() { index++; chosen = null; }); return; }
    setState(() { saving = true; error = null; });
    try {
      await widget.progress.record(widget.lesson['id'] as String, score, questions.length);
      if (mounted) setState(() { finished = true; saving = false; });
    } catch (_) { if (mounted) setState(() { saving = false; error = 'تعذر حفظ النتيجة. أعد المحاولة.'; }); }
  }
  Widget section(String title, String text) => Padding(padding: const EdgeInsets.only(bottom: 20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold)), const SizedBox(height: 10), SelectableText(text, style: const TextStyle(height: 1.9)),
  ]));
  @override Widget build(BuildContext context) {
    final l = widget.lesson; final q = questions[index] as Map;
    return Scaffold(appBar: AppBar(title: Text(l['title'] as String)), body: ListView(padding: const EdgeInsets.all(22), children: [
      section('هدفك اليوم', l['objective'] as String), section('من حياتنا', l['hook'] as String),
      section('افهم الفكرة', l['explanation'] as String),
      Card(child: Padding(padding: const EdgeInsets.all(18), child: section('مثال محلول', l['example'] as String))),
      const SizedBox(height: 20), section('انتبه لهذا الفرق', l['pitfall'] as String),
      if (['intersection', 'union'].any((id) => '${l['id']}'.endsWith(id))) const SetOperationLab(),
      const SizedBox(height: 20), const Text('اختبر فهمك', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      if (!finished) ...[
        Text('السؤال ${index + 1} من ${questions.length}'), const SizedBox(height: 12),
        Text(q['prompt'] as String, style: const TextStyle(fontSize: 22, height: 1.7)),
        for (var i = 0; i < (q['choices'] as List).length; i++) Padding(padding: const EdgeInsets.only(top: 10), child: OutlinedButton(
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16), backgroundColor: chosen == i ? (chosen == q['correct'] ? Colors.green.shade100 : Colors.orange.shade100) : null),
          onPressed: chosen != null ? null : () => setState(() { chosen = i; if (i == q['correct']) score++; }),
          child: Text(q['choices'][i] as String, style: const TextStyle(fontSize: 20)))),
        if (chosen != null) ...[
          const SizedBox(height: 14), Text('${chosen == q['correct'] ? 'إجابة صحيحة' : 'لنراجع السبب'}\n${q['feedback']}\nالإجابة: ${q['choices'][q['correct']]}', style: const TextStyle(height: 1.8)),
          if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          FilledButton(onPressed: saving ? null : next, child: Text(saving ? 'جارٍ الحفظ…' : index == questions.length - 1 ? 'حفظ النتيجة' : 'التالي')),
        ],
      ] else ...[
        Card(child: Padding(padding: const EdgeInsets.all(20), child: Text('نتيجتك $score من ${questions.length}\nحُفظت على هذا الجهاز. راجع الشرح ثم أعد التدريب.', style: const TextStyle(fontSize: 22, height: 1.8)))),
        for (final item in questions) ListTile(title: Text(item['prompt'] as String), subtitle: Text('الإجابة: ${item['choices'][item['correct']]}\n${item['feedback']}')),
        OutlinedButton(onPressed: () => setState(() { index = 0; chosen = null; score = 0; finished = false; }), child: const Text('إعادة الاختبار')),
      ],
      const SizedBox(height: 26), Text('مرجع موضوع الدرس: الصفحة المطبوعة ${l['printed_page']} في عينة رياضيات السابع القديمة. الشرح والتدريب من إعداد التطبيق؛ المطابقة الحالية والمراجعة المستقلة غير معتمدتين.', style: const TextStyle(fontSize: 13, height: 1.6)),
    ]));
  }
}

class SetOperationLab extends StatefulWidget {
  const SetOperationLab({super.key});
  @override State<SetOperationLab> createState() => _SetOperationLabState();
}
class _SetOperationLabState extends State<SetOperationLab> {
  final a = <int>{1,2,3}; final b = <int>{3,4}; bool union = false;
  @override Widget build(BuildContext context) {
    final result = (union ? a.union(b) : a.intersection(b)).toList()..sort();
    return Card(child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
      const Text('مختبر المجموعات', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const Text('غيّر عناصر المجموعتين وراقب النتيجة.'),
      for (final isA in [true, false]) Column(children: [Text(isA ? 'المجموعة أ' : 'المجموعة ب'), Wrap(spacing: 6, children: [for (var n=1;n<=5;n++) FilterChip(label: Text('$n'), selected: (isA ? a : b).contains(n), onSelected: (v) => setState(() { final target = isA ? a : b; if (v) { target.add(n); } else { target.remove(n); } }))])]),
      const SizedBox(height: 12), SegmentedButton<bool>(segments: const [ButtonSegment(value: false,label: Text('التقاطع ∩')), ButtonSegment(value: true,label: Text('الاتحاد ∪'))], selected: {union}, onSelectionChanged: (v) => setState(() => union=v.first)),
      const SizedBox(height: 14), AnimatedSize(duration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 250), child: Text(result.isEmpty ? 'الناتج: ∅' : 'الناتج: {${result.join('، ')}}', style: const TextStyle(fontSize: 26))),
      Text(union ? 'كل عنصر موجود في أ أو ب أو كليهما، دون تكرار.' : 'العناصر الموجودة في أ وب معًا فقط.'),
    ])));
  }
}
