import 'dart:convert';
import 'unit_workspace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

const gradeNames = {7: 'السابع الأساسي', 8: 'الثامن الأساسي', 9: 'التاسع الأساسي',
  10: 'الأول الثانوي', 11: 'الثاني الثانوي', 12: 'الثالث الثانوي'};

class CurriculumPortal extends StatefulWidget {
  final WidgetBuilder foundationBuilder;
  const CurriculumPortal({super.key, required this.foundationBuilder});
  @override State<CurriculumPortal> createState() => _CurriculumPortalState();
}
class _CurriculumPortalState extends State<CurriculumPortal> {
  String track = 'sanaa'; int grade = 7; String branch = 'science';
  List<Map<String, dynamic>> books = [];
  bool loaded = false; bool failed = false;
  @override void initState() { super.initState(); load(); }
  Future<void> load() async {
    try {
      final raw = jsonDecode(await rootBundle.loadString('content/source_ledger.json')) as Map<String, dynamic>;
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        books = (raw['books'] as List).map((b) => Map<String, dynamic>.from(b as Map)).toList();
        track = ['sanaa', 'aden'].contains(prefs.getString('curriculum_track')) ? prefs.getString('curriculum_track')! : 'sanaa';
        final savedGrade = prefs.getInt('curriculum_grade') ?? 7;
        grade = gradeNames.containsKey(savedGrade) ? savedGrade : 7;
        branch = prefs.getString('curriculum_branch') == 'literary' ? 'literary' : 'science';
        loaded = true;
      });
    } catch (_) { if (mounted) setState(() { loaded = true; failed = true; }); }
  }
  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('curriculum_track', track); await p.setInt('curriculum_grade', grade); await p.setString('curriculum_branch', branch);
  }
  @override Widget build(BuildContext context) {
    final filtered = books.where((b) => b['grade'] == grade && (b['claimed_track'] == track || b['claimed_track'] == 'common')).toList();
    final subjects = filtered.map((b) => '${b['subject_label']}').toSet().toList()..sort();
    return Scaffold(appBar: AppBar(title: const Text('أتعلم مع أخي • اليمن')),
      body: !loaded ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(20), children: [
        Container(padding: const EdgeInsets.all(26), decoration: BoxDecoration(borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(colors: [Color(0xFF123B48), Color(0xFF176B70)])), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.auto_stories_rounded, size: 46, color: Color(0xFFF0D18B)), const SizedBox(height: 16),
            const Text('تعلم اليوم…\nواصنع الغد', style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Colors.white, height: 1.4)),
            const SizedBox(height: 12), const Text('مساران للمناهج • ستة صفوف\nرحلة واحدة لكل طالب وطالبة في اليمن', style: TextStyle(color: Colors.white, height: 1.7)),
          ])),
        const SizedBox(height: 18), const Card(child: Padding(padding: EdgeInsets.all(16), child: Text(
          'نسخة تطوير للمناهج: الفهرس أولي، والدروس المدرسية لم تعتمد بعد. النموذج التفاعلي أدناه يوضح أسلوب التعلم المقترح.', style: TextStyle(fontSize: 15, height: 1.6)))),
        const SizedBox(height: 22), const Text('مسارك الدراسي', style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12), SegmentedButton<String>(segments: const [ButtonSegment(value: 'sanaa', label: Text('صنعاء')), ButtonSegment(value: 'aden', label: Text('عدن'))],
          selected: {track}, onSelectionChanged: (v) { setState(() => track = v.first); save(); }),
        const SizedBox(height: 16), DropdownButtonFormField<int>(key: ValueKey(grade), initialValue: grade,
          decoration: const InputDecoration(labelText: 'الصف', border: OutlineInputBorder()),
          items: gradeNames.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
          onChanged: (v) { if (v != null) { setState(() => grade = v); save(); } }),
        if (grade >= 11) ...[
          const SizedBox(height: 16), SegmentedButton<String>(segments: const [ButtonSegment(value: 'science', label: Text('علمي')), ButtonSegment(value: 'literary', label: Text('أدبي'))],
            selected: {branch}, onSelectionChanged: (v) { setState(() => branch = v.first); save(); }),
          const SizedBox(height: 8), const Text('نسبة كل كتاب إلى العلمي أو الأدبي ما زالت قيد التحقق؛ الفهرس أدناه غير مصنّف حسب الفرع بعد.', style: TextStyle(fontSize: 13)),
        ],
        const SizedBox(height: 22), FilledButton.icon(icon: const Icon(Icons.school),
          label: const Text('مساحة التعلم • وحدة المجموعات للسابع'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UnitWorkspace()))),
        const Text('١٠ دروس أصلية و٣٠ سؤالًا • مسودة غير معتمدة • متابعة محلية للطالب والمعلم', style: TextStyle(fontSize: 13, height: 1.7)),
        const SizedBox(height: 24), FilledButton.icon(icon: const Icon(Icons.play_circle_outline),
          style: FilledButton.styleFrom(padding: const EdgeInsets.all(18)), label: const Text('جرّب درسًا تفاعليًا: المجموعة والعنصر'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SetsDemoPage()))),
        const SizedBox(height: 22), Text('فهرس المصادر الأولي • ${filtered.length} عنوانًا', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8), const Text('هذه عناوين مرشّحة من فهرس مستقل، وليست إعلانًا عن اكتمال المواد أو اعتمادها. سنة عنوان الموقع قد تختلف عن الطبعة المطبوعة.', style: TextStyle(fontSize: 14, height: 1.6)),
        if (failed) OutlinedButton(onPressed: load, child: const Text('تعذر تحميل الفهرس • إعادة المحاولة')),
        if (filtered.isEmpty && !failed) const Padding(padding: EdgeInsets.all(18), child: Text('لم يتأكد توفر مصادر هذا الصف في الفهرس الحالي. لا يعني ذلك عدم وجود مواد مقررة.')),
        for (final subject in subjects) Card(child: ExpansionTile(title: Text(subject), subtitle: const Text('فحص المصادر قيد العمل'), children: [
          for (final book in filtered.where((b) => b['subject_label'] == subject)) ListTile(
            title: Text('${book['title'] ?? book['listing_title']}', style: const TextStyle(fontSize: 15)),
            subtitle: Text(book['pdf_inspected'] == true ? 'فُحصت بيانات عينة • مطابقة الطبعة الحالية لم تعتمد' : 'عنوان مرشّح • لم يُفحص الكتاب بعد', style: const TextStyle(fontSize: 12)),
            trailing: const Icon(Icons.info_outline), onTap: () => showDialog<void>(context: context, builder: (_) => AlertDialog(
              title: const Text('بيانات المصدر'), content: SingleChildScrollView(child: SelectableText(
                '${book['title']}\n\nالطبعة المرصودة داخل العينة: ${book['edition_year_observed'] ?? 'لم تُفحص'}\nالمطابقة الرسمية: غير معتمدة\n\nالفهرس المستقل:\n${book['listing_url']}\n\nرابط معاينة ملف المصدر:\n${book['public_preview_url'] ?? 'غير متوفر'}')),
              actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق'))]))),
        ])),
        const SizedBox(height: 24), OutlinedButton.icon(icon: const Icon(Icons.child_care), label: const Text('قسم التأسيس السابق • ٢٠٠ كلمة'),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: widget.foundationBuilder))),
        const SizedBox(height: 20), const Text('أتعلم مع أخي مشروع تعليمي مستقل، وليس تطبيقًا رسميًا تابعًا لوزارة التربية. لا يرفع بيانات الطالب إلى الإنترنت.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.black54)),
        const SizedBox(height: 20),
      ]));
  }
}

class SetsQuestion {
  final String prompt; final List<String> choices; final int correct; final String feedback;
  const SetsQuestion(this.prompt, this.choices, this.correct, this.feedback);
}
const setsQuestions = [
  SetsQuestion('س = {٢، ٤، ٦}. أي عدد ينتمي إلى س؟', ['٣','٤','٥'], 1, 'العدد ٤ مكتوب بين قوسي المجموعة، لذلك هو عنصر فيها.'),
  SetsQuestion('أي وصف يحدد مجموعة بوضوح؟', ['الطلاب اللطفاء','الأعداد الزوجية الأقل من ١٠ والأكبر من صفر','الألوان الجميلة'], 1, 'الوصف العددي له شرط يمكن التحقق منه، بينما اللطف والجمال حكمان قد يختلف فيهما الأشخاص.'),
  SetsQuestion('ص = {قلم، كتاب}. ما العبارة الصحيحة؟', ['قلم ∈ ص','مسطرة ∈ ص','كتاب ∉ ص'], 0, 'القلم عنصر مكتوب داخل المجموعة ص، ونعبّر عن انتمائه بالرمز ∈.'),
  SetsQuestion('م = {١، ٢، ٣}. ما العبارة الصحيحة؟', ['٤ ∈ م','٢ ∉ م','٤ ∉ م'], 2, 'العدد ٤ ليس من عناصر م. الرمز ∉ يعني لا ينتمي.'),
  SetsQuestion('ن = {أحمر، أخضر، أزرق}. كم عنصرًا في ن؟', ['عنصران','ثلاثة عناصر','أربعة عناصر'], 1, 'نعد العناصر المختلفة: أحمر، أخضر، أزرق؛ المجموع ثلاثة.'),
];

class SetsDemoPage extends StatefulWidget {
  const SetsDemoPage({super.key});
  @override State<SetsDemoPage> createState() => _SetsDemoPageState();
}
class _SetsDemoPageState extends State<SetsDemoPage> {
  final selected = <int>{}; int question = 0; int? chosen; int score = 0; bool finished = false; String help = '';
  bool get correct => chosen == setsQuestions[question].correct;
  @override Widget build(BuildContext context) {
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 280);
    return Scaffold(appBar: AppBar(title: const Text('المجموعة والعنصر')), body: ListView(padding: const EdgeInsets.all(22), children: [
      const Text('مختبر الأفكار', style: TextStyle(fontSize: 16, color: Color(0xFF176B70))),
      const SizedBox(height: 8), const Text('من أشياء متفرقة…\nإلى فكرة منظمة', style: TextStyle(fontSize: 31, height: 1.4, fontWeight: FontWeight.bold)),
      const SizedBox(height: 18), const Text('نموذج شرح أصلي لموضوع في رياضيات السابع. راجعنا موضع الموضوع في عينة كتاب قديمة؛ مطابقة طبعات صنعاء وعدن الحالية لم تعتمد بعد.', style: TextStyle(fontSize: 13, height: 1.6)),
      const SizedBox(height: 22), const Text('١ • افهم الفكرة', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12), const Text('تخيل أنك تنظّم ملفات جهازك. تضع ملفات الصور في مجلد، وملفات الصوت في مجلد آخر. ما يساعدك هنا هو قاعدة واضحة تحدد أين يوضع كل ملف.\n\nفي الرياضيات نختار أشياء وفق وصف محدد، ونسمي الناتج مجموعة. كل شيء داخلها يسمى عنصرًا. المهم أن نستطيع حسم السؤال: هل هذا الشيء منها أم لا؟', style: TextStyle(height: 1.8)),
      const SizedBox(height: 18), const Card(child: Padding(padding: EdgeInsets.all(18), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('لغة الرموز', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        SizedBox(height: 10), Text('س = {٢، ٤، ٦، ٨}\n٤ ∈ س : أربعة ينتمي إلى س\n٥ ∉ س : خمسة لا ينتمي إلى س', style: TextStyle(fontSize: 22, height: 1.9)),
      ]))),
      const SizedBox(height: 22), const Text('٢ • جرّب بنفسك', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const Text('اختر الأعداد الزوجية من ١ إلى ٨. اضغط العدد لإضافته أو إزالته.'),
      const SizedBox(height: 16), Wrap(alignment: WrapAlignment.center, spacing: 9, runSpacing: 10, children: [for (var n = 1; n <= 8; n++)
        AnimatedScale(scale: selected.contains(n) ? 1.08 : 1, duration: duration, child: FilterChip(
          label: Text('$n', style: const TextStyle(fontSize: 25)), selected: selected.contains(n),
          onSelected: (v) => setState(() { if (v) { selected.add(n); } else { selected.remove(n); } }))),
      ]),
      const SizedBox(height: 18), AnimatedContainer(duration: duration, padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(color: selected.length == 4 && selected.every((n) => n.isEven) ? Colors.green.shade100 : const Color(0xFFE2F1EF), borderRadius: BorderRadius.circular(24)),
        child: Column(children: [const Text('المجموعة التي كوّنتها'), const SizedBox(height: 10),
          Text('{ ${(selected.toList()..sort()).join('، ')} }', textAlign: TextAlign.center, style: const TextStyle(fontSize: 30)),
          const SizedBox(height: 8), Text(selected.isEmpty ? 'ابدأ باختيار عدد.' : selected.any((n) => n.isOdd) ? 'راجع الأعداد الفردية التي اخترتها؛ شرطنا هو الزوجية.' : selected.length == 4 ? 'رائع! اخترت جميع العناصر المطلوبة.' : 'كل ما اخترته صحيح. ابحث عن بقية الأعداد الزوجية.'),
        ])),
      const SizedBox(height: 22), const Text('٣ • اختبر فهمك', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      if (!finished) ...[
        Text('السؤال ${question + 1} من ${setsQuestions.length}'), const SizedBox(height: 10), Text(setsQuestions[question].prompt, style: const TextStyle(fontSize: 23, height: 1.6)),
        for (var i = 0; i < setsQuestions[question].choices.length; i++) Padding(padding: const EdgeInsets.only(top: 10), child: OutlinedButton(
          style: OutlinedButton.styleFrom(backgroundColor: chosen == i ? (correct ? Colors.green.shade100 : Colors.orange.shade100) : null, padding: const EdgeInsets.all(16)),
          onPressed: chosen != null ? null : () => setState(() { chosen = i; if (correct) score++; }), child: Text(setsQuestions[question].choices[i], style: const TextStyle(fontSize: 20)))),
        if (chosen != null) ...[
          const SizedBox(height: 12), Text('${correct ? 'صحيح ⭐' : 'لنتعلم من الإجابة'}\n${setsQuestions[question].feedback}', style: const TextStyle(height: 1.7)),
          FilledButton(onPressed: () async {
            if (question == setsQuestions.length - 1) {
              final p = await SharedPreferences.getInstance(); await p.setInt('sets_demo_score', score);
              if (mounted) setState(() => finished = true);
            } else { setState(() { question++; chosen = null; }); }
          }, child: Text(question == setsQuestions.length - 1 ? 'اعرض النتيجة' : 'السؤال التالي')),
        ],
      ] else Card(child: Padding(padding: const EdgeInsets.all(20), child: Column(children: [
        Text('⭐ نتيجتك: $score من ${setsQuestions.length}', style: const TextStyle(fontSize: 26)),
        const Text('راجع سبب كل إجابة. الفهم أهم من السرعة.'),
        TextButton(onPressed: () => setState(() { question = 0; chosen = null; score = 0; finished = false; }), child: const Text('إعادة التدريب')),
      ]))),
      const SizedBox(height: 24), const Text('٤ • مساعد الدرس', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      const Text('توضيحات معدّة لهذا الدرس، وليست محادثة ذكاء اصطناعي متصلة بالإنترنت.', style: TextStyle(fontSize: 13)),
      Wrap(spacing: 8, children: [
        ActionChip(label: const Text('اشرح أبسط'), onPressed: () => setState(() => help = 'فكّر في صندوق له قاعدة: لا نضع فيه إلا أعدادًا زوجية. العدد ٦ يحقق القاعدة فيدخل، والعدد ٧ لا يحققها فيبقى خارجًا.')),
        ActionChip(label: const Text('مثال من التقنية'), onPressed: () => setState(() => help = 'يمكن لبرنامج تنظيم الصور تكوين مجموعة من الملفات التي ينتهي اسمها بـ .png. الامتداد شرط واضح، بعكس وصف صور جميلة الذي يختلف من شخص إلى آخر.')),
        ActionChip(label: const Text('خطأ شائع'), onPressed: () => setState(() => help = 'اسم المجموعة مثل س يرمز إلى المجموعة كلها، أما العدد ٤ فهو عنصر منها. لا تخلط بين الصندوق وأحد الأشياء الموجودة داخله.')),
      ]),
      if (help.isNotEmpty) Card(child: Padding(padding: const EdgeInsets.all(18), child: Text(help, style: const TextStyle(height: 1.8)))),
      const SizedBox(height: 22), const Text('الخلاصة: ضع شرطًا واضحًا، حدّد العناصر، ثم استخدم ∈ و ∉ للتعبير عن الانتماء.', style: TextStyle(fontWeight: FontWeight.bold, height: 1.8)),
      const SizedBox(height: 24), ExpansionTile(title: const Text('مرجع الموضوع وحالة المراجعة'), children: [Padding(padding: const EdgeInsets.all(12), child: SelectableText(
        'رياضيات الصف السابع، عينة تحمل ١٤٣٨هـ/٢٠١٧م في صفحة بيانات الكتاب. الموضوع في الصفحة المطبوعة ٩، الصفحة ١١ من PDF.\nالشرح والأمثلة والتدريبات هنا من إعداد التطبيق.\nلم تعتمد مطابقة الطبعة الحالية ولم تتم مراجعة مستقلة من معلم بعد.\nhttps://yembooks.com/item/mathematics-grade-7-sanaa'))]),
      const SizedBox(height: 30),
    ]));
  }
}
