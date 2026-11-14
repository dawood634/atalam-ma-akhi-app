import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atalam_ma_akhi/unit_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Unit has ten distinct original lessons, valid answers and honest review status', () async {
    final data = jsonDecode(await rootBundle.loadString('content/sets_unit.json')) as Map;
    expect(data['official_alignment_verified'], false);
    expect(data['independent_teacher_review'], false);
    final lessons = data['lessons'] as List;
    expect(lessons.length, 10);
    expect(lessons.map((l) => l['id']).toSet().length, 10);
    expect(lessons.map((l) => l['printed_page']), [9,13,17,20,23,26,29,32,34,37]);
    for (final lesson in lessons) {
      final questions = lesson['questions'] as List;
      expect(questions.length, 3);
      for (final q in questions) {
        expect(q['correct'], inInclusiveRange(0, (q['choices'] as List).length - 1));
        expect(q['feedback'], isNotEmpty);
        expect((q['choices'] as List).toSet().length, (q['choices'] as List).length);
      }
    }
  });
  test('Scores persist last and best independently; invalid results rejected', () async {
    SharedPreferences.setMockInitialValues({'completed_lessons':['0']});
    final prefs = await SharedPreferences.getInstance();
    final progress = UnitProgress(prefs);
    await progress.record('lesson', 3, 3);
    await progress.record('lesson', 1, 3);
    final restored = UnitProgress(await SharedPreferences.getInstance());
    expect(restored.records['lesson']['last'], 1);
    expect(restored.records['lesson']['best'], 3);
    expect(restored.records['lesson']['attempts'], 2);
    expect(prefs.getStringList('completed_lessons'), ['0']);
    await expectLater(progress.record('lesson', 4, 3), throwsArgumentError);
  });
  test('Bookmark toggles and teacher assignment persist without clearing results', () async {
    SharedPreferences.setMockInitialValues({});
    final p = UnitProgress(await SharedPreferences.getInstance());
    await p.record('one', 2, 3);
    await p.bookmark('one');
    expect(p.bookmarks, {'one'});
    await p.bookmark('one');
    expect(p.bookmarks, isEmpty);
    await p.assign('two');
    expect(p.assignment, 'two');
    expect(p.records['one']['last'], 2);
  });
  test('Arabic search ignores diacritics and alef variants', () {
    expect(normalizeArabic('إِتِّحَادُ المَجْمُوعَاتِ'), 'اتحاد المجموعات');
  });
  testWidgets('Lesson grades only the first answer and persists a complete attempt', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final progress = UnitProgress(await SharedPreferences.getInstance());
    final lesson = {'id':'test-lesson', 'title':'درس اختبار', 'objective':'هدف', 'hook':'موقف', 'explanation':'شرح', 'example':'مثال', 'pitfall':'تنبيه', 'printed_page':9,
      'questions': List.generate(3, (i) => {'prompt':'سؤال $i', 'choices':['صحيح $i','خطأ $i'], 'correct':0, 'feedback':'تفسير $i'})};
    await tester.pumpWidget(MaterialApp(home: UnitLessonPage(lesson: lesson, progress: progress)));
    for (var i=0;i<3;i++) {
      final choice = find.text(i==0 ? 'خطأ $i' : 'صحيح $i');
      await tester.scrollUntilVisible(choice, 200);
      await tester.tap(choice); await tester.pumpAndSettle();
      final next = find.text(i==2 ? 'حفظ النتيجة' : 'التالي');
      await tester.scrollUntilVisible(next, 150); await tester.tap(next); await tester.pumpAndSettle();
    }
    expect(progress.records['test-lesson']['last'],2);
    expect(progress.records['test-lesson']['attempts'],1);
    expect(find.textContaining('نتيجتك 2 من 3'), findsOneWidget);
  });
  testWidgets('Interactive lab distinguishes intersection from union', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SetOperationLab())));
    expect(find.text('الناتج: {3}'),findsOneWidget);
    await tester.tap(find.text('الاتحاد ∪')); await tester.pumpAndSettle();
    expect(find.text('الناتج: {1، 2، 3، 4}'),findsOneWidget);
  });
}
