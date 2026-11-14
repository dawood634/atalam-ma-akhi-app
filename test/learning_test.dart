import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atalam_ma_akhi/main.dart';

void main() {
  test('Every lesson has a valid answer', () {
    expect(lessons, isNotEmpty);
    for (final lesson in lessons) {
      expect(lesson.correct, inInclusiveRange(0, lesson.choices.length - 1));
      expect(lesson.explanation, isNotEmpty);
    }
  });
  testWidgets('Student and teacher open separate pages', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const LearningApp());
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
    await tester.pumpWidget(const LearningApp());
    await tester.pumpAndSettle();
    expect(find.text('1 من 10 دروس'), findsOneWidget);
  });
}
