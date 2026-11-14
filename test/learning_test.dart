import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atalam_ma_akhi/main.dart';

void main() {
  test('Curriculum contains 200 unique words and exact spelling comparison', () {
    final words = wordGroups.expand((g) => g.words).toList();
    expect(words.length, 200);
    expect(words.map(normalizeAnswer).toSet().length, 200);
    expect(normalizeAnswer('كَتَبَ'), 'كتب');
    expect(normalizeAnswer('أَسَد'), isNot(normalizeAnswer('اسد')));
    expect(lessons.length, 128);
  });
  test('Existing lesson IDs remain in place', () {
    expect(lessons[0].title, 'حرف الباء');
    expect(lessons[9].title, 'المقارنة');
  });

  test('Progress persists without duplicating completed lessons', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ProgressStore();
    await store.load();
    await store.record(10, false);
    await store.record(10, true);
    await store.finish(10);
    await store.finish(10);
    await store.settings('أحمد', 3);
    final restored = ProgressStore();
    await restored.load();
    expect(restored.completed, {10});
    expect(restored.todayCount, 1);
    expect(restored.attempts['10'], 2);
    expect(restored.mistakes['10'], 1);
    expect(restored.name, 'أحمد');
    expect(restored.target, 3);
    store.dispose(); restored.dispose();
  });
  test('Every lesson has a valid answer', () {
    expect(lessons, isNotEmpty);
    for (final lesson in lessons) {
      if (lesson.kind == ExerciseKind.choice) {
        expect(lesson.correct, inInclusiveRange(0, lesson.choices.length - 1));
        expect(lesson.choices.toSet().length, lesson.choices.length);
      } else { expect(lesson.words.length, 10); }
      expect(lesson.explanation, isNotEmpty);
    }
  });
  testWidgets('Student and teacher open separate pages', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const LearningApp(foundationOnly: true));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('ادخل كطالب'));
    await tester.tap(find.text('ادخل كطالب'));
    await tester.pumpAndSettle();
    expect(find.text('دروسي الممتعة 📚'), findsOneWidget);
    expect(find.text('متابعة الطالب على هذا الجهاز'), findsNothing);
  });
  testWidgets('Progress counts only unique valid lesson IDs', (tester) async {
    SharedPreferences.setMockInitialValues({
      'completed_lessons': ['9', '9', '-1', '900', 'invalid']
    });
    await tester.pumpWidget(const LearningApp(foundationOnly: true));
    await tester.pumpAndSettle();
    expect(find.text('1 من ${lessons.length} دروس'), findsOneWidget);
  });
}
