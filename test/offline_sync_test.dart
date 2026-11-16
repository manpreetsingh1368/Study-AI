import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:study_ai/core/api/study_controller.dart';
import 'package:study_ai/core/storage/local_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'cached material survives offline study, operations replay and accounts stay isolated',
    () => HttpOverrides.runWithHttpOverrides(() async {
      sqfliteFfiInit();
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute(
        'CREATE TABLE cache(account TEXT,key TEXT,value TEXT,PRIMARY KEY(account,key))',
      );
      await db.execute(
        'CREATE TABLE outbox(id TEXT PRIMARY KEY,account TEXT,path TEXT,body TEXT)',
      );
      final store = LocalStore()..db = db;
      await store.createDocumentTables(db);
      await store.write('account-a', 'sets', [
        {'id': 'set-a', 'title': 'Cached notes'},
      ]);
      await store.write('account-b', 'sets', [
        {'id': 'set-b', 'title': 'Private B'},
      ]);
      FlutterSecureStorage.setMockInitialValues({
        'session': 'secret',
        'profile': jsonEncode({'id': 'account-a', 'name': 'Student'}),
      });
      var online = false, received = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.headers.contentType = ContentType.json;
        if (!online) {
          await req.response.close();
          return;
        }
        Object payload = {};
        if (req.uri.path == '/me') {
          payload = {
            'user': {'id': 'account-a', 'name': 'Student'},
            'plan': {'name': 'Free'},
          };
        }
        if (req.uri.path == '/sync') {
          payload = {'changes': [], 'cursor': 0, 'hasMore': false};
        }
        if (req.uri.path == '/analytics') payload = {'completed': received};
        if (req.uri.path == '/attempts') {
          received++;
          await utf8.decoder.bind(req).join();
          payload = {'ok': true};
        }
        req.response.write(jsonEncode(payload));
        await req.response.close();
      });
      final controller = StudyController(
        store,
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      try {
        await controller.initialize();
        expect(controller.offline, true);
        expect(controller.sets.single['id'], 'set-a');
        await controller.record('/attempts', {
          'id': 'stable-operation',
          'setId': 'set-a',
          'answers': {},
        });
        expect((await store.pending('account-a')).length, 1);
        online = true;
        await controller.sync();
        expect(controller.offline, false);
        expect(received, 1);
        expect(await store.pending('account-a'), isEmpty);
        await controller.sync();
        expect(received, 1);
        expect((await store.read('account-b', 'sets'))[0]['id'], 'set-b');
        await controller.logout(remote: false);
        expect(controller.sets, isEmpty);
        expect(await store.read('account-a', 'sets'), isNull);
        expect(await store.read('account-b', 'sets'), isNotNull);
      } finally {
        controller.dispose();
        await server.close(force: true);
        await db.close();
      }
    }, _RealHttp()),
  );
}

class _RealHttp extends HttpOverrides {}
