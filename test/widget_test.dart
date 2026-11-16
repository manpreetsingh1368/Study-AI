import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_ai/app/app.dart';
import 'package:study_ai/core/api/study_controller.dart';
import 'package:study_ai/core/storage/local_store.dart';

void main() {
  testWidgets('Registration switch and password validation', (tester) async {
    final controller = StudyController(LocalStore())..loading = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [studyProvider.overrideWithValue(controller)],
        child: const StudyAIApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Welcome back to Study AI.'), findsOneWidget);
    await tester.ensureVisible(find.text('New here? Create an account'));
    await tester.tap(find.text('New here? Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Your name'), findsOneWidget);
    await tester.ensureVisible(find.text('Create account'));
    await tester.tap(find.text('Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Use at least 12 characters'), findsOneWidget);
    expect(find.text('Enter your name'), findsOneWidget);
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets('Responsive empty workspace at $width', (tester) async {
      tester.view.physicalSize = Size(width, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = StudyController(LocalStore())
        ..loading = false
        ..user = {'id': 'test', 'name': 'Student', 'role': 'student'};
      await tester.pumpWidget(
        ProviderScope(
          overrides: [studyProvider.overrideWithValue(controller)],
          child: const StudyAIApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Your next breakthrough\nstarts here.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Create something to learn'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create something to learn'));
      await tester.pumpAndSettle();
      expect(find.text('Make space for a new idea.'), findsOneWidget);
    });
  }
}

class WidgetMemoryStore extends LocalStore {
  final values = <String, dynamic>{};
  @override
  Future<dynamic> read(String account, String key) async =>
      values['$account:$key'];
  @override
  Future<void> write(String account, String key, dynamic value) async {
    values['$account:$key'] = value;
