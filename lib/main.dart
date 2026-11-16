import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/api/study_controller.dart';
import 'core/storage/local_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = LocalStore();
  await store.open();
  final controller = StudyController(store);
  runApp(
    ProviderScope(
      overrides: [studyProvider.overrideWithValue(controller)],
      child: const StudyAIApp(),
    ),
  );
  await controller.initialize();
}
