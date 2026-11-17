import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_ai/app/app.dart';
import 'package:study_ai/core/api/study_controller.dart';
import 'package:study_ai/core/storage/local_store.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final width in [320.0, 800.0, 1200.0]) {
    testWidgets('Sign-in and password recovery fit at $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = StudyController(WidgetMemoryStore())..loading = false;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [studyProvider.overrideWithValue(controller)],
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
  testWidgets('Onboarding persists completion and appearance preferences', (
    tester,
  ) async {
    final store = WidgetMemoryStore();
    final controller = StudyController(store)
      ..loading = false
      ..onboarded = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [studyProvider.overrideWithValue(controller)],
        child: const StudyAIApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A workspace for your next idea.'), findsOneWidget);
    for (var i = 0; i < 2; i++) {
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
    }
    await tester.ensureVisible(find.text('Open my workspace'));
    await tester.tap(find.text('Open my workspace'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(controller.onboarded, true);
    expect(await store.read('_device', 'onboarded'), true);
    await controller.setAppearance('dark');
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
      Brightness.dark,
    );
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
  });
  for (final width in [390.0, 1200.0]) {
    testWidgets(
      'Saved collections, quiz feedback and settings render at $width',
      (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final store = WidgetMemoryStore();
        final controller = StudyController(store)
          ..loading = false
          ..user = {'id': 'student', 'name': 'Student', 'role': 'student'}
          ..offline = true;
        controller.sets = [
          {
            'id': 'sample',
            'title': 'Cell biology',
            'notes': 'ATP carries chemical energy.',
            'folder': 'Biology',
            'version': 1,
            'collections': [
              {'id': 'quiz-one', 'kind': 'quiz', 'title': 'Biology quiz'},
              {
                'id': 'cards-one',
                'kind': 'flashcards',
                'title': 'Biology cards',
              },
            ],
            'questions': [
              {
                'id': 'q1',
                'collection_id': 'quiz-one',
                'question': 'What does ATP carry?',
                'choices': ['Energy', 'Oxygen', 'Water', 'DNA'],
                'answer': 0,
                'explanation': 'ATP stores and transfers chemical energy.',
                'topic': 'Biology',
                'difficulty': 'easy',
              },
            ],
            'flashcards': [
              {
                'id': 'card1',
                'collection_id': 'cards-one',
                'front': 'ATP',
                'back': 'An energy carrier',
                'topic': 'Biology',
                'difficulty': 'easy',
              },
            ],
            'document': null,
          },
        ];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [studyProvider.overrideWithValue(controller)],
            child: const StudyAIApp(),
          ),
        );
        await tester.pumpAndSettle();
        final ctx = tester.element(find.byType(Scaffold).first);
        GoRouter.of(ctx).go('/set/sample');
        await tester.pumpAndSettle();
        expect(find.text('Meet your material.'), findsOneWidget);
        final studio = find.text('Studio');
        if (width < 1250) {
          await tester.tap(studio.first);
          await tester.pumpAndSettle();
        }
        await tester.drag(
          find.text('Source overview').last,
          const Offset(0, -320),
        );
        await tester.pumpAndSettle();
        expect(find.text('Your learning collections'), findsOneWidget);
        expect(tester.takeException(), isNull);
        GoRouter.of(tester.element(find.byType(Scaffold).first))
            .go('/quiz/sample?collection=quiz-one');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(find.text('What does ATP carry?'), findsOneWidget);
        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('A.  Energy'));
        await tester.tap(find.text('A.  Energy'));
        await tester.pumpAndSettle();
        expect(
          find.text('ATP stores and transfers chemical energy.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        GoRouter.of(tester.element(find.byType(Scaffold).first))
            .go('/cards/sample?collection=cards-one&due=true');
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await tester.pumpAndSettle();
        expect(find.text('ATP'), findsOneWidget);
        await tester.tap(find.text('ATP'));
        await tester.pumpAndSettle();
        expect(find.text('An energy carrier'), findsOneWidget);
        expect(tester.takeException(), isNull);
        GoRouter.of(tester.element(find.byType(Scaffold).first))
            .go('/settings');
        await tester.pumpAndSettle();
        expect(find.text('Make yourself at home.'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      },
    );
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
  }
}
