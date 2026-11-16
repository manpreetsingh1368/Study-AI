import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:study_ai/app/app.dart';
import 'package:study_ai/core/api/study_controller.dart';
import 'package:study_ai/core/storage/local_store.dart';

Future<LocalStore> testStore() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(singleInstance: false),
  );
  await db.execute(
    'CREATE TABLE cache(account TEXT,key TEXT,value TEXT,PRIMARY KEY(account,key))',
  );
  await db.execute(
    'CREATE TABLE outbox(id TEXT PRIMARY KEY,account TEXT,path TEXT,body TEXT)',
  );
  final store = LocalStore()..db = db;
  await store.createDocumentTables(db);
  await store.write('_device', 'onboarded', true);
  return store;
}

Uint8List validPdf() {
  const stream = 'BT /F1 18 Tf 20 100 Td (Study AI native PDF test) Tj ET';
  final objects = [
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 200] /Resources << /Font << /F1 5 0 R >> >> /Contents 4 0 R >>',
    '<< /Length ${stream.length} >>\nstream\n$stream\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  var text = '%PDF-1.4\n';
  final offsets = <int>[0];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(text.length);
    text += '${i + 1} 0 obj\n${objects[i]}\nendobj\n';
  }
  final xref = text.length;
  text += 'xref\n0 6\n0000000000 65535 f \n';
  for (final offset in offsets.skip(1)) {
    text += '${offset.toString().padLeft(10, '0')} 00000 n \n';
  }
  text += 'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n$xref\n%%EOF\n';
  return Uint8List.fromList(utf8.encode(text));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native Linux learning flow, real HTTP/SQLite, second device and PDF rendering',
    (tester) async {
      final project = const String.fromEnvironment('PROJECT_ROOT');
      if (project.isEmpty) {
        throw StateError(
          'Pass --dart-define=PROJECT_ROOT=/absolute/project/path',
        );
      }
      final temp = await Directory.systemTemp.createTemp('study-native-test-');
      final process = await Process.start(
        const String.fromEnvironment('NODE_BINARY', defaultValue: 'node'),
        ['--import', 'tsx', 'test/fixture-server.ts', temp.path],
        workingDirectory: '$project/server',
      );
      final stderr = <String>[];
      process.stderr.transform(utf8.decoder).listen(stderr.add);
      addTearDown(() async {
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 10));
        if (await temp.exists()) await temp.delete(recursive: true);
      });
      final line = await process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(const Duration(seconds: 15))
          .catchError(
            (Object e) => throw StateError(
              'Fixture startup failed: ${stderr.join()} ($e)',
            ),
          );
      final port = jsonDecode(line)['port'];
      FlutterSecureStorage.setMockInitialValues(
        {},
      ); // Test-only credentials; never touches the user's keyring.
      final store = await testStore(), otherStore = await testStore();
      final c = StudyController(store, baseUrl: 'http://127.0.0.1:$port');
      final other = StudyController(
        otherStore,
        baseUrl: 'http://127.0.0.1:$port',
      );
      try {
        await c.initialize();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [studyProvider.overrideWithValue(c)],
            child: const StudyAIApp(),
          ),
        );
        await tester.pumpAndSettle();
        await c.authenticate(
          register: true,
          email: 'native-test@example.com',
          password: 'native-test-password',
          name: 'Native Test',
        );
        await tester.pumpAndSettle();
        expect(
          find.text('Your next breakthrough\nstarts here.'),
          findsOneWidget,
        );
        final set = await c.saveSet(
