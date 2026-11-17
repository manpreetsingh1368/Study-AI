import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

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
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          RepaintBoundary(
            key: captureKey,
            child: ProviderScope(
              overrides: [studyProvider.overrideWithValue(c)],
              child: const StudyAIApp(),
            ),
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
          'Cell biology',
          'ATP transfers chemical energy.',
          folder: 'Biology',
        );
        await c.upload(set['id'], 'lecture.pdf', validPdf());
        await c.generate(set['id'], 'quiz', 1, 'easy');
        await c.generate(set['id'], 'flashcards', 1, 'easy');
        final material = c.sets.single;
        final quiz = (material['collections'] as List).firstWhere(
          (d) => d['kind'] == 'quiz',
        );
        final cards = (material['collections'] as List).firstWhere(
          (d) => d['kind'] == 'flashcards',
        );
        GoRouter.of(tester.element(find.byType(Scaffold).first))
            .go('/quiz/${set['id']}?collection=${quiz['id']}');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('A.  Energy'));
        await tester.tap(find.text('A.  Energy'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Finish quiz'));
        await tester.tap(find.text('Finish quiz'));
        for (
          var i = 0;
          i < 40 && find.text('Session complete.').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        expect(find.text('Session complete.'), findsOneWidget);
        expect(c.attempts.single['score'], 1);
        GoRouter.of(tester.element(find.byType(Scaffold).first))
            .go('/cards/${set['id']}?collection=${cards['id']}&due=true');
        await tester.pumpAndSettle();
        await tester.tap(find.text('ATP'));
        await tester.pumpAndSettle();
        expect(find.text('An energy carrier'), findsOneWidget);
        await tester.ensureVisible(find.text('I know this'));
        await tester.tap(find.text('I know this'));
        for (var i = 0; i < 40 && c.reviews.isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 250));
        }
        await c.sync();
        expect(c.reviews.length, 1);
        final response = await c.askNotebook(
          set['id'],
          'chat',
          'How does ATP help a cell?',
          [set['id']],
        );
        expect(
          response['content']['blocks'][0]['citations'][0]['quote'],
          contains('ATP transfers chemical energy.'),
        );
        await c.saveNotebookNote(
          set['id'],
          'Energy essentials',
          'ATP transfers chemical energy.',
          entryId: response['id'],
        );
        GoRouter.of(tester.element(find.byType(Scaffold).first))
            .go('/set/${set['id']}');
        await tester.pumpAndSettle();
        expect(find.text('How does ATP help a cell?'), findsOneWidget);
        await tester.ensureVisible(find.text('1 · Notes'));
        await tester.tap(find.text('1 · Notes'));
        await tester.pumpAndSettle();
        expect(find.text('“ATP transfers chemical energy.”'), findsOneWidget);
        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        final screenshotDirectory = const String.fromEnvironment(
          'SCREENSHOT_DIR',
        );
        if (screenshotDirectory.isNotEmpty) {
          tester.view.physicalSize = const Size(1600, 1000);
          tester.view.devicePixelRatio = 1;
          await tester.pumpAndSettle();
          await Directory(screenshotDirectory).create(recursive: true);
          for (final variant in ['light', 'dark', 'mobile']) {
            final appearance = variant == 'dark' ? 'dark' : 'light';
            if (variant == 'mobile') {
              tester.view.physicalSize = const Size(390, 900);
              await tester.pumpAndSettle();
            }
            await c.setAppearance(appearance);
            await tester.pumpAndSettle();
            final boundary =
                captureKey.currentContext!.findRenderObject()!
                    as RenderRepaintBoundary;
            final captured = await boundary.toImage(pixelRatio: 1.5);
            final png = await captured.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('$screenshotDirectory/notebook-$variant.png')
                .writeAsBytes(png!.buffer.asUint8List());
            captured.dispose();
          }
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
          await c.setAppearance('light');
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byTooltip('Share notebook'));
        await tester.pumpAndSettle();
        expect(find.text('Anyone with the link · read-only'), findsOneWidget);
        await tester.tap(find.text('Include notebook source notes'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Create read-only link'));
        await tester.tap(find.text('Create read-only link'));
        await tester.pumpAndSettle();
        expect(find.text('Your shareable link'), findsOneWidget);
        final shares = await c.request('GET', '/notebooks/${set['id']}/shares');
        expect(shares['shares'].length, 1);
        final shareId = shares['shares'][0]['id'];
        final shareUrl = await c.secure.read(
          key: 'share:${c.account}:$shareId',
        );
        // The fixture origin differs from the production public origin.
        final sharedUri = Uri.parse(shareUrl!)
            .replace(host: '127.0.0.1', port: port);
        final reader = HttpClient();
        try {
          final publicResponse = await (await reader.getUrl(sharedUri)).close();
          expect(publicResponse.statusCode, 200);
          expect(
            await utf8.decoder.bind(publicResponse).join(),
            contains('ATP transfers chemical energy.'),
          );
          await c.request('DELETE', '/notebooks/${set['id']}/shares/$shareId');
          final revoked = await (await reader.getUrl(sharedUri)).close();
          expect(revoked.statusCode, 404);
          await revoked.drain<void>();
        } finally {
          reader.close(force: true);
        }
        await tester.tap(find.byTooltip('Close sharing'));
        await other.initialize();
        expect(other.sets.single['title'], 'Cell biology');
        expect(other.attempts.single['score'], 1);
        expect(other.reviews.length, 1);
        expect(other.sets.single['notebook']['notes'].length, 1);
        expect(other.sets.single['notebook']['entries'].length, 1);
        final bytes = await other.documentBytes(
          other.sets.single['document']['id'],
        );
        await pdfrxFlutterInitialize();
        final pdf = await PdfDocument.openData(
          bytes,
          sourceName: 'native-acceptance',
        );
        expect(pdf.pages.length, 1);
        final image = await pdf.pages.first.render();
        expect(image, isNotNull);
        expect(image!.width, greaterThan(0));
        image.dispose();
        await pdf.dispose();
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 10));
        await other.sync();
        expect(other.offline, true);
        expect(
          await other.documentBytes(other.sets.single['document']['id']),
          bytes,
        );
        await other.saveSet('Offline addition', 'A genuinely offline note.');
        expect((await otherStore.pending(other.account)).length, 1);
        await other.saveNotebookNote(
          set['id'],
          'Offline thought',
          'ATP powers cellular work.',
          entryId: response['id'],
        );
        expect((await otherStore.pending(other.account)).length, 2);
        expect(
          other.sets
              .firstWhere((s) => s['id'] == set['id'])['notebook']['notes']
              .length,
          2,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        c.dispose();
        other.dispose();
        await store.clear(c.account);
        await store.db.close();
        await otherStore.db.close();
        process.kill();
        await process.exitCode.timeout(const Duration(seconds: 10));
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
