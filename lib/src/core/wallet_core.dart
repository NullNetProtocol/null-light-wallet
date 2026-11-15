import 'package:flutter/foundation.dart';

import '../rust/api/core.dart' as rust;
import '../rust/api/wallet.dart' as rw;
import '../rust/api/wallet.dart'
    show ActivityItem, Balance, PreparedSend, SyncStep;
import 'platform/init_io.dart'
    if (dart.library.js_interop) 'platform/init_web.dart';
import 'platform/store_io.dart'
    if (dart.library.js_interop) 'platform/store_web.dart';

export '../rust/api/wallet.dart'
    show ActivityItem, ActivityKind, Balance, PreparedSend, SendState, SyncStep;

/// Result of checking an address typed on the Send screen.
class AddressValidity {
  const AddressValidity(this.valid, [this.reason]);

  final bool valid;
  final String? reason;
}

/// Everything the app needs from the Rust core. Key derivation, note
/// decryption, the witness tree and proving stay in the null-chain
/// crates; Dart only calls through this.
abstract class WalletCore {
  /// Whether the core runs on this platform yet.
  bool get available;

  /// The core's version, for Settings.
  String get version;

  /// Whether `address` is a main-network address.
  AddressValidity checkAddress(String address);

  /// A new 24-word recovery phrase.
  String generatePhrase();

  /// Why `words` is not a recovery phrase, or `null` if it is one.
  String? checkPhrase(String words);

  /// Where this device keeps its wallet.
  WalletStore get store;

  /// Builds the proving key in the background, ahead of the first send.
  Future<void> warmUpProving();
}

/// The one wallet on this device.
abstract class WalletStore {
  /// Whether a wallet exists.
  Future<bool> exists();

  /// Creates the wallet from `words` under `passphrase`.
  Future<WalletHandle> create(String words, String passphrase);

  /// Unlocks the wallet.
  Future<WalletHandle> open(String passphrase);

  /// Deletes the wallet. Only the recovery phrase brings it back.
  Future<void> delete();
}

/// An unlocked wallet. [close] locks it: the keys are dropped.
abstract class WalletHandle {
  int nextHeight();
  String? scannedHash(int height);
  Future<SyncStep> applyBlocks(List<Uint8List> blocks);
  Future<void> rollbackTo(int height);
  Balance balance();
  Future<String> receiveAddress();
  Future<String> newAddress();
  List<ActivityItem> activity();
  Future<BigInt> quote(String to, BigInt amount);
  Future<PreparedSend> prepareSend(
    String to,
    BigInt amount,
    String memo,
    DateTime now,
  );
  Future<void> sendRejected(BigInt operation, String reason);
  List<Uint8List> pendingTransactions();
  Future<String> revealPhrase(String passphrase);

  /// Persists what changed (the browser image); a file saves itself.
  Future<void> save();

  /// Locks the wallet.
  void close();
}

/// The Rust core over flutter_rust_bridge: native on Android, WebAssembly
/// in the browser.
class RustCore implements WalletCore {
  RustCore._(this.store);

  /// Loads the core once, with this platform's wallet storage.
  static Future<RustCore> load() async {
    await initCore();
    return RustCore._(await platformStore());
  }

  @override
  final WalletStore store;

  @override
  bool get available => true;

  @override
  String get version => rust.coreVersion();

  @override
  AddressValidity checkAddress(String address) {
    final check = rust.checkAddress(address: address);
    return AddressValidity(check.valid, check.error);
  }

  @override
  String generatePhrase() => rw.generatePhrase();

  @override
  String? checkPhrase(String words) => rw.checkPhrase(words: words);

  @override
  Future<void> warmUpProving() => rw.warmUpProving();
}

/// [WalletHandle] over the Rust `LightWallet`.
class RustHandle implements WalletHandle {
  RustHandle(this._wallet, {this.onSave});

  final rw.LightWallet _wallet;

  /// Receives the byte image after a change, for browser storage.
  final Future<void> Function(Uint8List image)? onSave;

  @override
  int nextHeight() => _wallet.nextHeight();

  @override
  String? scannedHash(int height) => _wallet.scannedHash(height: height);

  @override
  Future<SyncStep> applyBlocks(List<Uint8List> blocks) =>
      _wallet.applyBlocks(blocks: blocks);

  @override
  Future<void> rollbackTo(int height) => _wallet.rollbackTo(height: height);

  @override
  Balance balance() => _wallet.balance();

  @override
  Future<String> receiveAddress() => _wallet.receiveAddress();

  @override
  Future<String> newAddress() => _wallet.newAddress();

  @override
  List<ActivityItem> activity() => _wallet.activity();

  @override
  Future<BigInt> quote(String to, BigInt amount) =>
      _wallet.quote(to: to, amount: amount);

  @override
  Future<PreparedSend> prepareSend(
    String to,
    BigInt amount,
    String memo,
    DateTime now,
  ) => _wallet.prepareSend(
    to: to,
    amount: amount,
    memo: memo,
    createdAt: BigInt.from(now.millisecondsSinceEpoch ~/ 1000),
  );

  @override
  Future<void> sendRejected(BigInt operation, String reason) =>
      _wallet.sendRejected(operation: operation, reason: reason);

  @override
  List<Uint8List> pendingTransactions() => _wallet.pendingTransactions();

  @override
  Future<String> revealPhrase(String passphrase) =>
      _wallet.revealPhrase(passphrase: passphrase);

  @override
  Future<void> save() async {
    final image = _wallet.image();
    if (image != null) await onSave?.call(image);
  }

  @override
  void close() => _wallet.dispose();
}

/// Stand-in when the core cannot load, for example a browser page served
/// without cross-origin isolation.
class UnavailableCore implements WalletCore {
  const UnavailableCore();

  @override
  bool get available => false;

  @override
  String get version => 'not available on this platform yet';

  @override
  AddressValidity checkAddress(String address) =>
      const AddressValidity(false, 'address checks need the wallet core');

  @override
  String generatePhrase() => throw UnsupportedError('no wallet core');

  @override
  String? checkPhrase(String words) => 'recovery phrases need the wallet core';

  @override
  WalletStore get store => const _NoStore();

  @override
  Future<void> warmUpProving() async {}
}

class _NoStore implements WalletStore {
  const _NoStore();

  @override
  Future<bool> exists() async => false;

  @override
  Future<WalletHandle> create(String words, String passphrase) =>
      throw UnsupportedError('no wallet core');

  @override
  Future<WalletHandle> open(String passphrase) =>
      throw UnsupportedError('no wallet core');

  @override
  Future<void> delete() async {}
}

/// The core for the platform the app runs on, or the stand-in if it does
/// not load.
Future<WalletCore> loadCore() async {
  try {
    return await RustCore.load();
  } catch (e) {
    debugPrint('wallet core did not load: $e');
    return const UnavailableCore();
  }
}
