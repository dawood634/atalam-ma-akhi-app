import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:atalam_ma_akhi/main.dart';
import 'package:atalam_ma_akhi/platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Source inventory never treats catalog labels as curriculum approval', () async {
    final data = jsonDecode(await rootBundle.loadString('content/source_ledger.json')) as Map;
    final books = data['books'] as List;
    expect(books.length, greaterThanOrEqualTo(114));
    expect(books.map((b) => b['id']).toSet().length, books.length);
    expect(books.map((b) => b['grade']).toSet(), {7, 8, 9, 10, 11, 12});
    for (final b in books) {
      expect(b['official_approval_verified'], false);
      expect(b['coverage_verified'], false);
    }
    expect(books.where((b) => b['pdf_inspected'] == true).length, 3);
  });
  testWidgets('Curriculum selection persists separately from foundation progress', (tester) async {
    SharedPreferences.setMockInitialValues({'completed_lessons': ['0']});
    await tester.pumpWidget(const LearningApp());
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('عدن'), 250);
    await tester.tap(find.text('عدن'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('curriculum_track'), 'aden');
    expect(prefs.getStringList('completed_lessons'), ['0']);
    await tester.scrollUntilVisible(find.textContaining('فهرس المصادر الأولي'), 250);
    expect(find.textContaining('فهرس المصادر الأولي'), findsOneWidget);
  });
  testWidgets('Interactive model explains answers and saves its own score', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const MaterialApp(home: SetsDemoPage()));
    await tester.pumpAndSettle();
    Future<void> tapText(String value) async {
      await tester.scrollUntilVisible(find.text(value), 250);
      await tester.tap(find.text(value));
      await tester.pumpAndSettle();
    }
    for (var i = 0; i < setsQuestions.length; i++) {
      final q = setsQuestions[i];
      await tapText(q.choices[q.correct]);
      expect(find.textContaining(q.feedback), findsOneWidget);
      await tapText(i == setsQuestions.length - 1 ? 'اعرض النتيجة' : 'السؤال التالي');
    }
    expect(find.text('⭐ نتيجتك: 5 من 5'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('sets_demo_score'), 5);
    expect(prefs.getStringList('completed_lessons'), isNull);
  });
}
