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
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,options:OpenDatabaseOptions(singleInstance:false));
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
  test(
    'offline creates/edits, safe conflicts, merge, and deleted records across devices',
    () => HttpOverrides.runWithHttpOverrides(() async {
      FlutterSecureStorage.setMockInitialValues({
        'session': 'token',
        'profile': jsonEncode({'id': 'owner', 'name': 'Learner'}),
      });
      var online = false, seq = 0;
      Map<String, dynamic>? remote;
      final receipts = <String, Map<String, dynamic>>{};
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.headers.contentType = ContentType.json;
        if (!online) {
          await req.response.close();
          return;
        }
        Object body = {};
        if (req.uri.path == '/me')
          body = {
            'user': {'id': 'owner', 'name': 'Learner'},
            'plan': {'name': 'Free', 'pro': false, 'sets': 5},
          };
        if (req.uri.path == '/sync/mutate') {
          final op = Map<String, dynamic>.from(
            jsonDecode(await utf8.decoder.bind(req).join()),
          );
          if (receipts.containsKey(op['id'])) {
            body = receipts[op['id']]!;
          } else if (op['kind'] != 'create' &&
              (remote == null || remote!['version'] != op['baseVersion'])) {
            req.response.statusCode = 409;
            body = {'message': 'Changed on another device'};
          } else {
            remote = {
              'id': op['setId'],
              'title': op['title'],
              'notes': op['notes'],
              'folder': op['folder'],
              'version': op['kind'] == 'create'
                  ? 1
                  : (remote!['version'] as int) + 1,
              'deleted': op['kind'] == 'delete' ? 1 : 0,
              'updated_at': seq,
              'created_at': 0,
              'questions': [],
              'flashcards': [],
              'collections': [],
              'document': null,
            };
            seq++;
            body = {'set': remote!['deleted'] == 1 ? null : remote};
            receipts[op['id']] = Map<String, dynamic>.from(body as Map);
          }
        }
        if (req.uri.path == '/sync') {
          final cursor = int.parse(req.uri.queryParameters['cursor']!);
          body = {
            'changes': seq > cursor
                ? [
                    {
                      'set_id': remote!['id'],
                      'set': remote!['deleted'] == 1 ? null : remote,
                    },
                  ]
                : [],
            'cursor': seq,
            'hasMore': false,
          };
        }
        if (req.uri.path == '/sets')
          body = {
            'sets': remote == null || remote!['deleted'] == 1 ? [] : [remote],
          };
          body = {'changes': [], 'cursor': 0, 'hasMore': false};
        }
        if (req.uri.path == '/analytics') body = {'completed': 0};
        if (req.uri.path == '/exams/active') body = {'sessions': []};
        req.response.write(jsonEncode(body));
        await req.response.close();
      });
      final aStore = await memoryStore(), bStore = await memoryStore();
      final a = StudyController(
        aStore,
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      final b = StudyController(
        bStore,
        baseUrl: 'http://127.0.0.1:${server.port}',
      );
      try {
        await a.initialize();
        final created = await a.saveSet(
          'Offline lecture',
          'Original',
          folder: 'Biology',
        );
        await a.saveSet(
          'Offline lecture',
          'Edited offline',
          existing: created,
          folder: 'Biology',
        );
        expect((await aStore.pending('owner')).length, 2);
        expect(a.sets.single['notes'], 'Edited offline');
        online = true;
        await a.sync();
        expect(remote!['notes'], 'Edited offline');
        expect(await aStore.pending('owner'), isEmpty);
        await b.initialize();
        expect(b.sets.single['notes'], 'Edited offline');
        remote = {...remote!, 'version': 3, 'notes': 'Other device edit'};
        seq++;
        await a.saveSet(
          'Offline lecture',
          'My conflicting edit',
          existing: a.sets.single,
          folder: 'Biology',
        );
        expect(a.conflicts.single['local']['notes'], 'My conflicting edit');
        expect(a.sets.single['notes'], 'Other device edit');
        expect(remote!['notes'], 'Other device edit');
        await a.resolveConflict(
          a.conflicts.single,
          resolution: 'merge',
          notes: 'Both ideas combined',
        );
        expect(a.conflicts, isEmpty);
        expect(remote!['notes'], 'Both ideas combined');
        online = false;
        await a.deleteSet(a.sets.single);
        expect(a.sets, isEmpty);
        expect((await aStore.pending('owner')).length, 1);
        online = true;
        await a.sync();
        await b.sync();
        expect(b.sets, isEmpty);
        expect(remote!['deleted'], 1);
      } finally {
        a.dispose();
        b.dispose();
        await aStore.db.close();
        await bStore.db.close();
        await server.close(force: true);
      }
    }, _RealHttp()),
  );
}

class _RealHttp extends HttpOverrides {}

Future<LocalStore> memoryStore() async {
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
  return store;
}
