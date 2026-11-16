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
