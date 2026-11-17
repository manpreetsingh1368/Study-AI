import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;

class LocalStore {
  late Database db;
  Future<void> open() async {
    if (Platform.isLinux || Platform.isWindows) {
      ffi.sqfliteFfiInit();
      databaseFactory = ffi.databaseFactoryFfi;
    }
    final dir = await getApplicationSupportDirectory();
    db = await openDatabase(
      p.join(dir.path, 'study_cache.sqlite'),
      version: 2,
      onUpgrade: (db, oldVersion, _) async {
        if (oldVersion < 2) await createDocumentTables(db);
      },
      onCreate: (db, _) async {
        await db.execute(
          'CREATE TABLE cache (account TEXT, key TEXT, value TEXT, PRIMARY KEY(account,key))',
        );
        await db.execute(
          'CREATE TABLE outbox (id TEXT PRIMARY KEY, account TEXT, path TEXT, body TEXT)',
        );
        await createDocumentTables(db);
      },
    );
  }

  Future<void> createDocumentTables(Database db) async {
    await db.execute(
      'CREATE TABLE IF NOT EXISTS pdf_cache(account TEXT, id TEXT, bytes BLOB, PRIMARY KEY(account,id))',
    );
    await db.execute(
      'CREATE TABLE IF NOT EXISTS uploads(id TEXT PRIMARY KEY,account TEXT,set_id TEXT,name TEXT,bytes BLOB,version INTEGER)',
    );
  }

  Future<Uint8List?> pdf(String account, String id) async {
    final files = await db.query(
    final rows = await db.query(
      'pdf_cache',
      where: 'account=? AND id=?',
      whereArgs: [account, id],
    );
    return rows.isEmpty ? null : rows.first['bytes'] as Uint8List;
  }

  Future<void> cachePdf(String account, String id, List<int> bytes) async {
    await db.insert('pdf_cache', {
      'account': account,
      'id': id,
      'bytes': Uint8List.fromList(bytes),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> queueUpload(
    String account,
    String id,
    String setId,
    String name,
    List<int> bytes,
    int version,
  ) async {
    await db.insert('uploads', {
      'id': id,
      'account': account,
      'set_id': setId,
      'name': name,
      'bytes': Uint8List.fromList(bytes),
      'version': version,
    });
    await cachePdf(account, id, bytes);
  }

  Future<List<Map<String, Object?>>> pendingUploads(String account) => db.query(
    'uploads',
    where: 'account=?',
    whereArgs: [account],
    orderBy: 'rowid',
  );
  Future<void> removeUpload(String id) async {
    await db.delete('uploads', where: 'id=?', whereArgs: [id]);
  }

  Future<void> queueNotebookRecord(
    String account,
    String path,
    Map<String, dynamic> body,
    List<Map<String, dynamic>> sets,
  ) async {
    await db.transaction((txn) async {
      await txn.insert('outbox', {
        'id': body['id'],
        'account': account,
        'path': path,
        'body': jsonEncode(body),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('cache', {
        'account': account,
        'key': 'sets',
        'value': jsonEncode(sets),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> queueMutation(
    String account,
    Map<String, dynamic> operation,
    List<Map<String, dynamic>> sets,
  ) async {
    await db.transaction((txn) async {
      await txn.insert('outbox', {
        'id': operation['id'],
        'account': account,
        'path': '/sync/mutate',
        'body': jsonEncode(operation),
      });
      await txn.insert('cache', {
        'account': account,
        'key': 'sets',
        'value': jsonEncode(sets),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<dynamic> read(String account, String key) async {
    final rows = await db.query(
      'cache',
      where: 'account=? AND key=?',
      whereArgs: [account, key],
    );
    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }

  Future<void> write(String account, String key, dynamic value) async {
    await db.insert('cache', {
      'account': account,
      'key': key,
      'value': jsonEncode(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> writeSyncPage(
    String account,
    List<Map<String, dynamic>> sets,
    int cursor,
  ) async {
    await db.transaction((txn) async {
      for (final entry in {'sets': sets, 'cursor': cursor}.entries) {
        await txn.insert('cache', {
          'account': account,
          'key': entry.key,
          'value': jsonEncode(entry.value),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> writeLearningPage(
    String account,
    List<Map<String, dynamic>> attempts,
    List<Map<String, dynamic>> reviews,
    int cursor,
  ) async {
    await db.transaction((txn) async {
      for (final e in {
        'attempts': attempts,
        'reviews': reviews,
        'learningCursor': cursor,
      }.entries) {
        await txn.insert('cache', {
          'account': account,
          'key': e.key,
          'value': jsonEncode(e.value),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<void> enqueue(
    String account,
    String path,
    Map<String, dynamic> body,
  ) async {
    await db.insert('outbox', {
      'id': body['id'],
      'account': account,
      'path': path,
      'body': jsonEncode(body),
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<Map<String, Object?>>> pending(String account) => db.query(
    'outbox',
    where: 'account=?',
    whereArgs: [account],
    orderBy: 'rowid',
  );
  Future<void> acknowledgeRecord(
    String account,
    String id,
    List<Map<String, dynamic>> sets,
  ) async {
    await db.transaction((txn) async {
      await txn.delete(
        'outbox',
        where: 'id=? AND account=?',
        whereArgs: [id, account],
      );
      await txn.insert('cache', {
        'account': account,
        'key': 'sets',
        'value': jsonEncode(sets),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<void> remove(String id) async {
    await db.delete('outbox', where: 'id=?', whereArgs: [id]);
  }

  Future<void> clear(String account) async {
    final files = await db.query(
      'pdf_files',
      where: 'account=?',
      whereArgs: [account],
    );
    for (final row in files) {
      final file = File(row['path'] as String);
      if (await file.exists()) await file.delete();
    }
    await db.delete('pdf_files', where: 'account=?', whereArgs: [account]);
    await db.delete('pdf_cache', where: 'account=?', whereArgs: [account]);
    await db.delete('uploads', where: 'account=?', whereArgs: [account]);
    await db.delete('cache', where: 'account=?', whereArgs: [account]);
    await db.delete('outbox', where: 'account=?', whereArgs: [account]);
  }
}
