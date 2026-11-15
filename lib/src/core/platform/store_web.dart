import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../image_store.dart';
import '../wallet_core.dart';

/// The browser: the wallet's byte image in IndexedDB, which belongs to this
/// origin alone.
Future<WalletStore> platformStore() async => ImageStore(IndexedDbBackend());

/// One record in one IndexedDB object store.
class IndexedDbBackend implements ImageBackend {
  static const _database = 'null-wallet';
  static const _store = 'wallet';
  static const _key = 'image';

  web.IDBDatabase? _db;

  Future<web.IDBDatabase> _open() async {
    final open = _db;
    if (open != null) return open;
    final request = web.window.indexedDB.open(_database, 1);
    request.onupgradeneeded = ((web.Event _) {
      (request.result as web.IDBDatabase).createObjectStore(_store);
    }).toJS;
    await _done(request);
    return _db = request.result as web.IDBDatabase;
  }

  Future<JSAny?> _run(
    web.IDBTransactionMode mode,
    web.IDBRequest Function(web.IDBObjectStore store) action,
  ) async {
    final db = await _open();
    final store = db.transaction(_store.toJS, mode).objectStore(_store);
    final request = action(store);
    await _done(request);
    return request.result;
  }

  @override
  Future<Uint8List?> read() async {
    final value = await _run('readonly', (s) => s.get(_key.toJS));
    if (value == null || value.isUndefinedOrNull) return null;
    return (value as JSUint8Array).toDart;
  }

  @override
  Future<void> write(Uint8List image) =>
      _run('readwrite', (s) => s.put(image.toJS, _key.toJS));

  @override
  Future<void> delete() => _run('readwrite', (s) => s.delete(_key.toJS));
}

/// Completes when `request` succeeds; throws its error otherwise.
Future<void> _done(web.IDBRequest request) {
  final done = Completer<void>();
  request.onsuccess = ((web.Event _) => done.complete()).toJS;
  request.onerror = ((web.Event _) => done.completeError(
    StateError('browser storage: ${request.error?.message ?? 'failed'}'),
  )).toJS;
  return done.future;
}
