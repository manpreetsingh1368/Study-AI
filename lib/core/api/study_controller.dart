import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../storage/local_store.dart';

final studyProvider = Provider<StudyController>(
  (ref) => throw UnimplementedError('Override at startup'),
);

class ApiException implements Exception {
  final int status;
  final String message;
  ApiException(this.status, this.message);
  @override
  String toString() => message;
}

class StudyController extends ChangeNotifier {
  final LocalStore store;
  final FlutterSecureStorage secure;
  final String baseUrl;
  StudyController(
    this.store, {
    this.secure = const FlutterSecureStorage(
      mOptions: MacOsOptions(usesDataProtectionKeychain: false),
    ),
    this.baseUrl = const String.fromEnvironment(
      'API_URL',
      defaultValue: 'http://127.0.0.1:3000',
    ),
  });
  String? token, error;
  Map<String, dynamic>? user;
  Map<String, dynamic> catalog = {};
  Map<String, dynamic> plan = {}, analytics = {}, advanced = {};
  List<Map<String, dynamic>> failedOperations = [], uploadIssues = [];
  int get attentionCount =>
      conflicts.length + failedOperations.length + uploadIssues.length;
  List<Map<String, dynamic>> sets = [],
      attempts = [],
      reviews = [],
      conflicts = [],
      activeExams = [];
  bool loading = true, offline = false, syncing = false, onboarded = true;
  String syncLabel = 'Connecting', appearance = 'system';
  Timer? _timer;
  int _sessionVersion = 0;
  Future<void>? _syncTask;
  String get account => user!['id'] as String;
  Future<void> initialize() async {
    try {
      appearance = await store.read('_device', 'appearance') ?? 'system';
      onboarded = await store.read('_device', 'onboarded') ?? false;
      token = await secure.read(key: 'session');
      final saved = await secure.read(key: 'profile');
      if (token != null && saved != null) {
        user = Map<String, dynamic>.from(jsonDecode(saved));
        await _loadCache();
        await sync();
      }
    } catch (e) {
      error = 'Could not open local credentials or storage: $e';
    }
    loading = false;
    notifyListeners();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (user != null) unawaited(sync());
    });
  }

  Future<void> completeOnboarding() async {
    await store.write('_device', 'onboarded', true);
    onboarded = true;
    notifyListeners();
  }

  Future<void> setAppearance(String value) async {
    await store.write('_device', 'appearance', value);
    appearance = value;
    notifyListeners();
  }

  Future<dynamic> request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final req = http.Request(method, Uri.parse('$baseUrl$path'));
    req.headers['Content-Type'] = 'application/json';
    if (token != null) req.headers['Authorization'] = 'Bearer $token';
    if (body != null) req.body = jsonEncode(body);
    final response = await req
        .send()
        .then(http.Response.fromStream)
        .timeout(
          Duration(
            seconds: path.endsWith('/ask')
                ? 300
                : path.endsWith('/generate')
                ? 150
                : 12,
          ),
        );
    final dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      throw const FormatException('The backend returned an invalid response.');
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        response.statusCode,
        data['message'] ?? 'Request failed.',
      );
    }
    return data;
  }

  Future<void> authenticate({
    required bool register,
    required String email,
    required String password,
    String name = '',
  }) async {
    _sessionVersion++;
    final data = await request(
      'POST',
      register ? '/auth/register' : '/auth/login',
      {'email': email, 'password': password, if (register) 'name': name},
    );
    await secure.write(key: 'session', value: data['token']);
    await secure.write(key: 'profile', value: jsonEncode(data['user']));
    token = data['token'];
    user = Map<String, dynamic>.from(data['user']);
    sets = [];
    attempts = [];
    reviews = [];
    conflicts = [];
    analytics = {};
    plan = {};
    error = null;
    await _loadCache();
    await sync();
    notifyListeners();
  }

  bool socialSignInActive = false;
  String? _socialFlow, _socialProof;
  Future<void> socialSignIn(
    String provider, {
    bool link = false,
    String? password,
  }) async {
    if (socialSignInActive) return;
    final proof = base64Url
        .encode(List<int>.generate(32, (_) => Random.secure().nextInt(256)))
        .replaceAll('=', '');
    socialSignInActive = true;
    _socialProof = proof;
    notifyListeners();
    String? flow;
    var completed = false;
    try {
      final result = await request(
        'POST',
        link ? '/me/identities/$provider/start' : '/auth/oauth/$provider/start',
        {
          'challenge': sha256.convert(utf8.encode(proof)).toString(),
          'password': ?password,
        },
      );
      flow = result['flowId'];
      if (_socialProof != proof) return;
      _socialFlow = flow;
      if (!await launchUrl(
        Uri.parse(result['url']),
        mode: LaunchMode.externalApplication,
      )) {
        throw ApiException(503, 'Could not open your browser.');
      }
      for (var attempt = 0; attempt < 300 && _socialProof == proof; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 2));
        if (_socialProof != proof) return;
        final status = await request('POST', '/auth/oauth/complete', {
          'flowId': flow,
          'verifier': proof,
        });
        if (_socialProof != proof) return;
        if (status['status'] == 'failed') {
          throw ApiException(401, status['message']);
        }
        if (status['status'] == 'complete') {
          completed = true;
          await acceptSession(Map<String, dynamic>.from(status));
          return;
        }
      }
      if (_socialProof == proof) {
        throw ApiException(408, 'Browser sign-in expired. Please try again.');
      }
    } finally {
      if (!completed && flow != null) {
        try {
          await request('POST', '/auth/oauth/cancel', {
            'flowId': flow,
            'verifier': proof,
          });
        } catch (_) {}
      }
      if (_socialProof == proof) {
        socialSignInActive = false;
        _socialFlow = null;
        _socialProof = null;
        notifyListeners();
      }
    }
  }

  Future<void> cancelSocialSignIn() async {
    socialSignInActive = false;
    notifyListeners();
    final id = _socialFlow, proof = _socialProof;
    _socialFlow = null;
    _socialProof = null;
    if (id != null && proof != null) {
      try {
        await request('POST', '/auth/oauth/cancel', {
          'flowId': id,
          'verifier': proof,
        });
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> createShare(
    String notebookId, {
    required bool includeSourceNotes,
    required List<String> entryIds,
    required List<String> noteIds,
    int days = 7,
  }) async {
    final result = Map<String, dynamic>.from(
      await request('POST', '/notebooks/$notebookId/shares', {
        'includeSourceNotes': includeSourceNotes,
        'entryIds': entryIds,
        'noteIds': noteIds,
        'expiresInDays': days,
      }),
    );
    await secure.write(
      key: 'share:$account:${result['id']}',
      value: result['url'],
    );
  }

  Future<List<Map<String, dynamic>>> _readList(String key) async =>
      ((await store.read(account, key)) as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  Future<void> _loadCache() async {
    catalog = Map<String, dynamic>.from(
      await store.read(account, 'catalog') ?? {},
    );
    failedOperations = await _readList('failures');
    uploadIssues = await _readList('uploadIssues');
    sets = await _readList('sets');
    attempts = await _readList('attempts');
    reviews = await _readList('reviews');
    conflicts = await _readList('conflicts');
    activeExams = await _readList('exams');
    analytics = Map<String, dynamic>.from(
      await store.read(account, 'analytics') ?? {},
    );
    plan = Map<String, dynamic>.from(await store.read(account, 'plan') ?? {});
    advanced = Map<String, dynamic>.from(
      await store.read(account, 'advanced') ?? {},
    );
  }

  Future<void> sync() {
    if (user == null) return Future.value();
    return _syncTask ??= _synchronize().whenComplete(() => _syncTask = null);
  }

  Future<void> _synchronize() async {
    final epoch = _sessionVersion, uid = account;
    syncing = true;
    syncLabel = 'Syncing';
    notifyListeners();
    bool valid() => epoch == _sessionVersion && user != null;
    try {
      final me = await request('GET', '/me');
      if (!valid()) return;
      plan = Map<String, dynamic>.from(me['plan']);
      catalog = Map<String, dynamic>.from(await request('GET', '/plans'));
      if (!valid()) return;
      user = Map<String, dynamic>.from(me['user']);
      await secure.write(key: 'profile', value: jsonEncode(user));
      final blocked = <String>{};
      for (final operation in await store.pending(uid)) {
        if (!valid()) return;
        final body = Map<String, dynamic>.from(
          jsonDecode(operation['body'] as String),
        );
        if (blocked.contains(body['setId'])) continue;
        try {
          final result = await request(
            'POST',
            operation['path'] as String,
            body,
          );
          if (!valid()) return;
          if (operation['path'] == '/sync/mutate') {
            final remaining = (await store.pending(uid))
                .where((op) => op['id'] != operation['id'])
                .toList();
            final later = remaining.any(
              (op) =>
                  op['path'] == '/sync/mutate' &&
                  jsonDecode(op['body'] as String)['setId'] == body['setId'],
            );
            if (!later) {
              sets.removeWhere((s) => s['id'] == body['setId']);
              if (result['set'] != null) {
                sets.add(Map<String, dynamic>.from(result['set']));
              }
            }
          }
          if (result['notebook'] != null) {
            final match = RegExp(r'^/notebooks/([^/]+)/')
                .firstMatch(operation['path'] as String);
            final material = sets
                .where((s) => s['id'] == match?.group(1))
                .firstOrNull;
            if (material != null) {
              material['notebook'] = Map<String, dynamic>.from(
                result['notebook'],
              );
              _overlayNotebookOperations(
                material,
                (await store.pending(uid))
                    .where((op) => op['id'] != operation['id'])
                    .toList(),
              );
            }
          }
          await store.acknowledgeRecord(uid, operation['id'] as String, sets);
        } on ApiException catch (e) {
          if (operation['path'] == '/sync/mutate' &&
              [400, 403, 404, 409].contains(e.status)) {
            final related = (await store.pending(uid))
                .where(
                  (op) =>
                      op['path'] == '/sync/mutate' &&
                      jsonDecode(op['body'] as String)['setId'] ==
                          body['setId'],
                )
                .toList();
            final latest = related.isEmpty
                ? body
                : Map<String, dynamic>.from(
                    jsonDecode(related.last['body'] as String),
                  );
            conflicts.removeWhere((c) => c['local']['setId'] == body['setId']);
            conflicts.add({
              'id': body['id'],
              'local': latest,
              'message': e.message,
            });
            // Persist the local copy before dropping its rejected operation(s).
            await store.write(uid, 'conflicts', conflicts);
            for (final op in related) {
              await store.remove(op['id'] as String);
            }
            blocked.add(body['setId']);
            sets.removeWhere((s) => s['id'] == body['setId']);
          } else if ([400, 403, 404, 409].contains(e.status)) {
            failedOperations.removeWhere((op) => op['id'] == operation['id']);
            failedOperations.add({
              'id': operation['id'],
              'path': operation['path'],
              'body': body,
              'message': e.message,
            });
            await store.write(uid, 'failures', failedOperations);
            await store.remove(operation['id'] as String);
          } else {
            rethrow;
          }
        }
      }
      var cursor = await store.read(uid, 'cursor') as int? ?? 0;
      bool more;
      do {
        final page = await request('GET', '/sync?cursor=$cursor');
        if (!valid()) return;
        final pendingRecords = await store.pending(uid);
        final pending = pendingRecords
            .where((op) => op['path'] == '/sync/mutate')
            .map((op) => jsonDecode(op['body'] as String)['setId'])
            .toSet();
        for (final change in page['changes']) {
          if (pending.contains(change['set_id'])) continue;
          sets.removeWhere((s) => s['id'] == change['set_id']);
          if (change['set'] != null) {
            final incoming = Map<String, dynamic>.from(change['set']);
            _overlayNotebookOperations(incoming, pendingRecords);
            sets.add(incoming);
          }
        }
        cursor = page['cursor'];
        more = page['hasMore'];
        await store.writeSyncPage(uid, sets, cursor);
      } while (more);
      // If a conflict occurred without a new remote event, recover its current snapshot.
      if (blocked.isNotEmpty) {
        final remote = await request('GET', '/sets');
        if (!valid()) return;
        for (final s in remote['sets']) {
          if (blocked.contains(s['id'])) {
            sets.removeWhere((v) => v['id'] == s['id']);
            sets.add(Map<String, dynamic>.from(s));
          }
        }
      }
      for (final upload in await store.pendingUploads(uid)) {
        if (!valid()) return;
        if (conflicts.any((c) => c['local']['setId'] == upload['set_id']) ||
            uploadIssues.any((issue) => issue['id'] == upload['id'])) {
          continue;
        }
        try {
          final response = await _sendUpload(upload);
          if (!valid()) return;
          await store.removeUpload(upload['id'] as String);
          uploadIssues.removeWhere((e) => e['id'] == upload['id']);
          sets.removeWhere((s) => s['id'] == upload['set_id']);
          sets.add(Map<String, dynamic>.from(response['set']));
        } on ApiException catch (e) {
          if (![400, 403, 404, 409, 413].contains(e.status)) rethrow;
          uploadIssues.removeWhere((i) => i['id'] == upload['id']);
          uploadIssues.add({
            'id': upload['id'],
            'setId': upload['set_id'],
            'name': upload['name'],
            'message': e.message,
          });
          await store.write(uid, 'uploadIssues', uploadIssues);
        }
      }
      var learningCursor = await store.read(uid, 'learningCursor') as int? ?? 0;
      do {
        final page = await request(
          'GET',
          '/sync/learning?cursor=$learningCursor',
        );
        if (!valid()) return;
        for (final change in page['changes'] ?? []) {
          final list = change['kind'] == 'attempt' ? attempts : reviews;
          list.removeWhere((r) => r['id'] == change['record_id']);
          if (change['record'] != null) {
            list.add(Map<String, dynamic>.from(change['record']));
          }
        }
        learningCursor = page['cursor'] ?? learningCursor;
        more = page['hasMore'] ?? false;
        await store.writeLearningPage(uid, attempts, reviews, learningCursor);
      } while (more);
      final data = await request('GET', '/analytics');
      if (!valid()) return;
      analytics = Map<String, dynamic>.from(data);
      final exams = await request('GET', '/exams/active');
      if (!valid()) return;
      activeExams = ((exams['sessions'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (plan['pro'] == true) {
        advanced = Map<String, dynamic>.from(
          await request('GET', '/analytics/advanced'),
        );
      } else {
        advanced = {};
      }
      if (!valid()) return;
      sets.sort(
        (a, b) => (b['updated_at'] as int? ?? 0).compareTo(
          a['updated_at'] as int? ?? 0,
        ),
      );
      for (final e in {
        'sets': sets,
        'plan': plan,
        'catalog': catalog,
        'analytics': analytics,
        'advanced': advanced,
        'exams': activeExams,
        'uploadIssues': uploadIssues,
      }.entries) {
        await store.write(uid, e.key, e.value);
      }
      offline = false;
      error = null;
      syncLabel = attentionCount == 0
          ? 'Up to date'
          : '$attentionCount items need attention';
    } on ApiException catch (e) {
      if (!valid()) return;
      error = e.message;
      syncLabel = 'Sync needs attention';
      if (e.status == 401) await logout(remote: false);
    } catch (_) {
      if (!valid()) return;
      offline = true;
      syncLabel = 'Offline · changes saved on this device';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  void _overlayNotebookOperations(
    Map<String, dynamic> material,
    List<Map<String, Object?>> pendingRecords,
  ) {
    for (final pendingRecord in pendingRecords) {
      final match = RegExp(r'^/notebooks/([^/]+)/(notes|delete-note)$')
          .firstMatch(pendingRecord['path'] as String);
      if (match == null || match.group(1) != material['id']) continue;
      final body = Map<String, dynamic>.from(
        jsonDecode(pendingRecord['body'] as String),
      );
      final book = Map<String, dynamic>.from(material['notebook'] ?? {});
      final notes = List<dynamic>.from(book['notes'] ?? []);
      if (match.group(2) == 'notes') {
        notes.removeWhere((n) => n['id'] == body['id']);
        notes.add({
          ...body,
          'citations': [],
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'pending': true,
        });
      } else {
        notes.removeWhere((n) => n['id'] == body['noteId']);
      }
      book['notes'] = notes;
      material['notebook'] = book;
    }
  }

  Future<void> logout({bool remote = true, bool eraseCache = false}) async {
    _sessionVersion++;
    if (remote && token != null) {
      try {
        await request('POST', '/auth/logout');
      } on ApiException catch (e) {
        if (e.status != 401) rethrow;
      } on IOException catch (_) {
        /* Local sign-out remains available offline. */
      } on TimeoutException catch (_) {}
    }
    await secure.delete(key: 'session');
    await secure.delete(key: 'profile');
    if (user != null) {
      final pending =
          (await store.pending(account)).isNotEmpty ||
          (await store.pendingUploads(account)).isNotEmpty ||
          attentionCount > 0;
      if (eraseCache || !pending) await store.clear(account);
    }
    token = null;
    user = null;
    sets = [];
    reviews = [];
    attempts = [];
    conflicts = [];
    failedOperations = [];
    uploadIssues = [];
    activeExams = [];
    plan = {};
    analytics = {};
    advanced = {};
    notifyListeners();
  }

  Future<Map<String, dynamic>> saveSet(
    String title,
    String notes, {
    Map<String, dynamic>? existing,
    String folder = '',
    String? parentNotebookId,
  }) async {
    final sid = existing?['id'] ?? const Uuid().v4();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final local = <String, dynamic>{
      ...?existing,
      'id': sid,
      'title': title,
      'notes': notes,
      'folder': folder,
      'parent_notebook_id': existing?['parent_notebook_id'] ?? parentNotebookId,
      'version': existing == null ? 1 : (existing['version'] as int) + 1,
      'created_at': existing?['created_at'] ?? timestamp,
      'updated_at': timestamp,
      'questions': existing?['questions'] ?? [],
      'flashcards': existing?['flashcards'] ?? [],
      'collections': existing?['collections'] ?? [],
      'document': existing?['document'],
      'pending': true,
    };
    final operation = {
      'id': const Uuid().v4(),
      'kind': existing == null ? 'create' : 'update',
      'setId': sid,
      'baseVersion': existing?['version'] ?? 0,
      if (existing == null && parentNotebookId != null)
        'parentNotebookId': parentNotebookId,
      'title': title,
      'notes': notes,
      'folder': folder,
    };
    final next = [...sets.where((s) => s['id'] != sid), local];
    await store.queueMutation(account, operation, next);
    sets = next;
    notifyListeners();
    await sync();
    return sets.where((s) => s['id'] == sid).firstOrNull ?? local;
  }

  Future<void> deleteSet(Map<String, dynamic> set) async {
    final operation = {
      'id': const Uuid().v4(),
      'kind': 'delete',
      'setId': set['id'],
      'baseVersion': set['version'],
      'title': set['title'],
      'notes': set['notes'],
      'folder': set['folder'] ?? '',
    };
    final next = sets.where((s) => s['id'] != set['id']).toList();
    await store.queueMutation(account, operation, next);
    sets = next;
    notifyListeners();
    await sync();
  }

  Future<void> resolveConflict(
    Map<String, dynamic> conflict, {
    required String resolution,
    String? title,
    String? notes,
  }) async {
    final local = Map<String, dynamic>.from(conflict['local']);
    if (resolution == 'copy') {
      await saveSet(
        title ?? '${local['title']} (local copy)',
        notes ?? local['notes'] ?? '',
        folder: local['folder'] ?? '',
      );
    }
    if (resolution == 'merge') {
      final current = sets.where((s) => s['id'] == local['setId']).firstOrNull;
      if (current == null) {
        throw ApiException(
          409,
          'The server copy was deleted. Save a separate copy instead.',
        );
      }
      await saveSet(
        title ?? local['title'],
        notes ?? local['notes'] ?? '',
        folder: local['folder'] ?? '',
        existing: current,
      );
    }
    conflicts.removeWhere((c) => c['id'] == conflict['id']);
    await store.write(account, 'conflicts', conflicts);
    notifyListeners();
  }

  Future<void> retryFailedOperation(Map<String, dynamic> operation) async {
    await store.enqueue(
      account,
      operation['path'],
      Map<String, dynamic>.from(operation['body']),
    );
    await discardFailedOperation(operation['id']);
    await sync();
  }

  Future<void> discardFailedOperation(String id) async {
    failedOperations.removeWhere((op) => op['id'] == id);
    await store.write(account, 'failures', failedOperations);
    notifyListeners();
  }

  Future<void> retryUpload(String id) async {
    final issue = uploadIssues.where((op) => op['id'] == id).first;
    final current = sets.where((s) => s['id'] == issue['setId']).firstOrNull;
    if (current == null) {
      throw ApiException(
        404,
        'The study set was deleted. Save the PDF to disk before discarding this upload.',
      );
    }
    await store.db.update(
      'uploads',
      {'version': current['version']},
      where: 'id=? AND account=?',
      whereArgs: [id, account],
    );
    uploadIssues.removeWhere((op) => op['id'] == id);
    await store.write(account, 'uploadIssues', uploadIssues);
    await sync();
  }

  Future<void> discardUpload(String id) async {
    await store.removeUpload(id);
    uploadIssues.removeWhere((op) => op['id'] == id);
    await store.write(account, 'uploadIssues', uploadIssues);
    notifyListeners();
  }

  Future<Uint8List> pendingPdf(String id) async {
    final bytes = await store.pdf(account, id);
    if (bytes == null) throw ApiException(404, 'Local PDF unavailable.');
    return bytes;
  }

  Future<dynamic> _sendUpload(Map<String, Object?> upload) async {
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/sets/${upload['set_id']}/pdf'),
    );
    req.headers.addAll({
      'Authorization': 'Bearer $token',
      'x-document-id': upload['id'] as String,
      'x-set-version': '${upload['version']}',
    });
    if (upload['path'] != null) {
      final file = File(upload['path'] as String);
      req.files.add(
        http.MultipartFile(
          'file',
          file.openRead(),
          await file.length(),
          filename: upload['name'] as String,
          contentType: http.MediaType('application', 'pdf'),
        ),
      );
    } else {
      req.files.add(
        http.MultipartFile.fromBytes(
          'file',
          upload['bytes'] as Uint8List,
          filename: upload['name'] as String,
          contentType: http.MediaType('application', 'pdf'),
        ),
      );
    }
    final response = await req
        .send()
        .then(http.Response.fromStream)
        .timeout(const Duration(minutes: 5));
    final result = jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, result['message']);
    }
    return result;
  }

  Future<void> uploadStream(
    String setId,
    String name,
    Stream<List<int>> stream,
    int length,
  ) async {
    final set = sets.firstWhere((s) => s['id'] == setId),
        id = const Uuid().v4();
    await store.queueUploadStream(
      account,
      id,
      setId,
      name,
      stream,
      length,
      set['version'],
    );
    set['document'] = {
      'id': id,
      'filename': name,
      'bytes': length,
      'pending': true,
    };
    await store.write(account, 'sets', sets);
    notifyListeners();
    await sync();
  }

  Future<void> upload(String setId, String name, List<int> bytes) async {
    final set = sets.where((s) => s['id'] == setId).first;
    final id = const Uuid().v4();
    await store.queueUpload(account, id, setId, name, bytes, set['version']);
    set['document'] = {
      'id': id,
      'filename': name,
      'bytes': bytes.length,
      'pending': true,
    };
    await store.write(account, 'sets', sets);
    notifyListeners();
    await sync();
  }

  Future<Uint8List> documentBytes(String id) async {
    final uid = account, cached = await store.pdf(account, id);
    if (cached != null) return cached;
    final response = await http
        .get(
          Uri.parse('$baseUrl/documents/$id'),
          headers: {'Authorization': 'Bearer $token'},
        )
        .timeout(const Duration(seconds: 45));
    if (response.statusCode >= 400) {
      throw ApiException(response.statusCode, 'Could not download this PDF.');
    }
    if (uid != user?['id']) throw ApiException(401, 'Account changed.');
    await store.cachePdf(uid, id, response.bodyBytes);
    return response.bodyBytes;
  }

  Future<void> generate(
    String sid,
    String kind,
    int count,
    String difficulty,
  ) async {
    await sync();
    if (offline) {
      throw ApiException(
        503,
        'Connect to the backend to generate learning material.',
      );
    }
    if ((await store.pending(account)).any(
      (op) =>
          op['path'] == '/sync/mutate' &&
          jsonDecode(op['body'] as String)['setId'] == sid,
    )) {
      throw ApiException(
        409,
        'Finish syncing this study set before generating.',
      );
    }
    final configuration = '$kind:$count:$difficulty';
    final saved = await store.read(account, 'generation:$sid');
    final operationId = saved != null && saved['configuration'] == configuration
        ? saved['id']
        : const Uuid().v4();
    await store.write(account, 'generation:$sid', {
      'id': operationId,
      'configuration': configuration,
    });
    await request('POST', '/sets/$sid/generate', {
      'id': operationId,
      'kind': kind,
      'count': count,
      'difficulty': difficulty,
    });
    await store.write(account, 'generation:$sid', null);
    await sync();
  }

  Future<Map<String, dynamic>> askNotebook(
    String notebookId,
    String kind,
    String prompt,
    List<String> sourceIds,
  ) async {
    if (offline) {
      throw ApiException(
        503,
        'Reconnect to ask your sources. Saved answers and notes are available offline.',
      );
    }
    if (sourceIds.isEmpty) {
      throw ApiException(400, 'Select at least one source.');
    }
    await sync();
    if ((await store.pending(account)).any(
      (op) =>
          op['path'] == '/sync/mutate' &&
          sourceIds.contains(jsonDecode(op['body'] as String)['setId']),
    )) {
      throw ApiException(409, 'Finish syncing the selected sources first.');
    }
    final configuration = jsonEncode({
      'kind': kind,
      'prompt': prompt,
      'sources': sourceIds.toList()..sort(),
    });
    final previous = await store.read(account, 'notebookRequest:$notebookId');
    final requestId =
        previous != null && previous['configuration'] == configuration
        ? previous['id']
        : const Uuid().v4();
    await store.write(account, 'notebookRequest:$notebookId', {
      'id': requestId,
      'configuration': configuration,
    });
    final result = await request('POST', '/notebooks/$notebookId/ask', {
      'id': requestId,
      'kind': kind,
      'prompt': prompt,
      'sourceIds': sourceIds,
    });
    await store.write(account, 'notebookRequest:$notebookId', null);
    await sync();
    return Map<String, dynamic>.from(result['entry']);
  }

  Future<void> saveNotebookNote(
    String notebookId,
    String title,
    String text, {
    String? entryId,
  }) async {
    final set = sets.firstWhere((s) => s['id'] == notebookId);
    final id = const Uuid().v4();
    final body = {'id': id, 'title': title, 'text': text, 'entryId': ?entryId};
    final notebook = Map<String, dynamic>.from(set['notebook'] ?? {});
    final original = (notebook['entries'] as List? ?? [])
        .where((e) => e['id'] == entryId)
        .firstOrNull;
    final citations = original == null
        ? []
        : (original['content']['blocks'] as List)
              .expand((b) => b['citations'] as List)
              .toList();
    notebook['notes'] = [
      ...notebook['notes'] ?? [],
      {
        'id': id,
        'title': title,
        'text': text,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'citations': citations,
        'pending': true,
      },
    ];
    final next = sets
        .map((s) => s['id'] == notebookId ? {...s, 'notebook': notebook} : s)
        .toList();
    await store.queueNotebookRecord(
      account,
      '/notebooks/$notebookId/notes',
      body,
      next,
    );
    sets = next;
    notifyListeners();
    await sync();
  }

  Future<void> deleteNotebookNote(String notebookId, String noteId) async {
    final set = sets.firstWhere((s) => s['id'] == notebookId),
        notebook = Map<String, dynamic>.from(
          sets.firstWhere((s) => s['id'] == notebookId)['notebook'] ?? {},
        );
    notebook['notes'] = (notebook['notes'] as List? ?? [])
        .where((n) => n['id'] != noteId)
        .toList();
    final next = sets
        .map((s) => s['id'] == notebookId ? {...set, 'notebook': notebook} : s)
        .toList();
    await store.queueNotebookRecord(
      account,
      '/notebooks/$notebookId/delete-note',
      {'id': const Uuid().v4(), 'noteId': noteId},
      next,
    );
    sets = next;
    notifyListeners();
    await sync();
  }

  Future<void> loadEarlierNotebook(String notebookId) async {
    final set = sets.firstWhere((s) => s['id'] == notebookId),
        notebook = Map<String, dynamic>.from(
          sets.firstWhere((s) => s['id'] == notebookId)['notebook'] ?? {},
        );
    final entries = notebook['entries'] as List? ?? [];
    final data = await request(
      'GET',
      '/notebooks/$notebookId/entries?offset=${entries.length}',
    );
    final byId = {
      for (final e in [...entries, ...data['entries']]) e['id']: e,
    };
    notebook['entries'] = byId.values.toList();
    set['notebook'] = notebook;
    await store.write(account, 'sets', sets);
    notifyListeners();
  }

  Future<void> record(String path, Map<String, dynamic> body) async {
    await store.enqueue(account, path, body);
    if (path == '/attempts' && !attempts.any((a) => a['id'] == body['id'])) {
      final set = sets.where((s) => s['id'] == body['setId']).firstOrNull;
      if (set != null && (set['questions'] as List? ?? []).isNotEmpty) {
        final questions = (set['questions'] as List)
            .where(
              (q) =>
                  body['collectionId'] == null ||
                  q['collection_id'] == body['collectionId'],
            )
            .map(
              (q) => <String, dynamic>{
                ...Map<String, dynamic>.from(q),
                'selected': body['answers'][q['id']] ?? -1,
              },
            )
            .toList();
        final attempt = {
          'id': body['id'],
          'set_id': body['setId'],
          'title': set['title'],
          'questions': questions,
          'score': questions.where((q) => q['selected'] == q['answer']).length,
          'total': questions.length,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'pending': true,
        };
        attempts.removeWhere((a) => a['id'] == body['id']);
        attempts.add(attempt);
        await store.write(account, 'attempts', attempts);
      }
    }
    if (path == '/reviews' && !reviews.any((r) => r['id'] == body['id'])) {
      final previous = reviewFor(body['cardId']);
      final days = body['known'] == true
          ? (previous?['known'] == 1
                    ? (previous!['interval_days'] as int) * 2
                    : 1)
                .clamp(1, 180)
          : 1;
      reviews.add({
        ...body,
        'card_id': body['cardId'],
        'known': body['known'] == true ? 1 : 0,
        'reviewed_at': DateTime.now().millisecondsSinceEpoch,
        'due_at': DateTime.now()
            .add(Duration(days: days))
            .millisecondsSinceEpoch,
        'interval_days': days,
      });
      await store.write(account, 'reviews', reviews);
    }
    notifyListeners();
    await sync();
  }

  Map<String, dynamic>? reviewFor(String cardId) {
    final list = reviews.where((r) => r['card_id'] == cardId).toList()
      ..sort(
        (a, b) => (b['reviewed_at'] as int).compareTo(a['reviewed_at'] as int),
      );
    return list.firstOrNull;
  }

  bool isDue(String cardId) =>
      (reviewFor(cardId)?['due_at'] as int? ?? 0) <=
      DateTime.now().millisecondsSinceEpoch;
  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
