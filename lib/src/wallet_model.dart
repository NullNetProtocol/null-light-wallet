import 'dart:async';

import 'package:flutter/foundation.dart';

import 'app.dart';
import 'core/wallet_core.dart';
import 'light/light_client.dart';
import 'light/sync.dart';
import 'settings.dart';

/// Where the wallet is.
enum WalletStatus {
  /// Looking for a wallet on the device.
  loading,

  /// No wallet yet: create or restore.
  none,

  /// A wallet exists and needs its passphrase.
  locked,

  /// Unlocked: keys in memory.
  unlocked,
}

/// Shortest passphrase accepted for a new wallet.
const minPassphraseLength = 8;

/// Why `passphrase` is too weak for a new wallet, or `null`.
String? passphraseProblem(String passphrase) =>
    passphrase.length < minPassphraseLength
    ? 'Use at least $minPassphraseLength characters'
    : null;

/// The wallet as the screens see it: status, balance, activity, sync.
/// Locks itself when the app has been in the background for the
/// [AppSettings.lockAfter] the user chose.
class WalletModel extends ChangeNotifier {
  WalletModel({
    required this.core,
    required this.settings,
    required this.lightClient,
    this.syncEvery = const Duration(minutes: 1),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final WalletCore core;
  final AppSettings settings;
  final LightClientFactory lightClient;
  final Duration syncEvery;
  final DateTime Function() _clock;

  WalletStatus _status = WalletStatus.loading;
  WalletHandle? _wallet;
  Balance? _balance;
  List<ActivityItem> _activity = const [];
  String? _address;
  bool _syncing = false;
  int? _syncNext;
  int? _tip;
  String? _syncError;
  DateTime? _backgroundedAt;
  Timer? _timer;
  Future<void>? _inflight;

  WalletStatus get status => _status;
  Balance? get balance => _balance;
  List<ActivityItem> get activity => _activity;
  String? get address => _address;
  bool get syncing => _syncing;

  /// The next height to scan, during and after a sync.
  int? get syncNext => _syncNext;

  /// The server's tip at the last sync.
  int? get tip => _tip;

  /// Why the last sync failed, if it did.
  String? get syncError => _syncError;

  /// Whether the wallet has scanned up to the server's tip.
  bool get upToDate => _tip != null && _syncNext != null && _syncNext! > _tip!;

  /// Finds out whether a wallet exists.
  Future<void> load() async {
    final exists = core.available && await core.store.exists();
    _setStatus(exists ? WalletStatus.locked : WalletStatus.none);
  }

  /// Creates a wallet from `words` and unlocks it.
  Future<void> create(String words, String passphrase) async {
    final problem = passphraseProblem(passphrase);
    if (problem != null) throw ArgumentError(problem);
    _open(await core.store.create(words, passphrase));
  }

  /// Unlocks the wallet; throws on a wrong passphrase.
  Future<void> unlock(String passphrase) async =>
      _open(await core.store.open(passphrase));

  void _open(WalletHandle wallet) {
    _wallet?.close();
    _wallet = wallet;
    _syncNext = wallet.nextHeight();
    _syncError = null;
    _refresh();
    _setStatus(WalletStatus.unlocked);
    unawaited(_loadAddress());
    unawaited(core.warmUpProving().catchError((Object _) {}));
    _timer?.cancel();
    _timer = Timer.periodic(syncEvery, (_) => sync());
    unawaited(sync());
  }

  /// Drops the keys from memory.
  void lock() {
    _timer?.cancel();
    _timer = null;
    _wallet?.close();
    _wallet = null;
    _balance = null;
    _activity = const [];
    _address = null;
    if (_status == WalletStatus.unlocked) _setStatus(WalletStatus.locked);
  }

  /// Deletes the wallet from the device.
  Future<void> delete() async {
    lock();
    await core.store.delete();
    _tip = null;
    _syncNext = null;
    _setStatus(WalletStatus.none);
  }

  /// Call when the app goes to the background.
  void paused() => _backgroundedAt = _clock();

  /// Call when the app comes back: locks if it was away too long, else
  /// syncs.
  void resumed() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (since != null && _clock().difference(since) >= settings.lockAfter) {
      lock();
    } else if (_wallet != null) {
      unawaited(sync());
    }
  }

  /// Scans up to the server's tip. One sync at a time: a call during a
  /// sync waits for that one.
  Future<void> sync() {
    final wallet = _wallet;
    if (wallet == null) return Future.value();
    return _inflight ??= _sync(wallet).whenComplete(() => _inflight = null);
  }

  Future<void> _sync(WalletHandle wallet) async {
    _syncing = true;
    _syncError = null;
    notifyListeners();
    final client = lightClient(settings.serverUri);
    try {
      final outcome = await syncWallet(
        client,
        wallet,
        onProgress: (next, tip) {
          _syncNext = next;
          _tip = tip;
          if (identical(_wallet, wallet)) _refresh();
          notifyListeners();
        },
      );
      _tip = outcome.tip;
    } on LightException catch (e) {
      _syncError = e.message;
    } catch (e) {
      _syncError = '$e';
    } finally {
      client.close();
      _syncing = false;
      if (identical(_wallet, wallet)) {
        _syncNext = wallet.nextHeight();
        _refresh();
      }
      notifyListeners();
    }
  }

  /// A fresh receiving address.
  Future<void> newAddress() async {
    final wallet = _requireWallet();
    _address = await wallet.newAddress();
    await wallet.save();
    notifyListeners();
  }

  /// The fee a payment would pay now.
  Future<BigInt> quote(String to, BigInt amount) =>
      _requireWallet().quote(to, amount);

  /// Builds, proves and submits a payment. A definite refusal by the
  /// server frees its notes and throws; a lost reply keeps it pending
  /// (`delivered: false`), and the next sync submits it again.
  Future<({String txid, bool delivered})> send(
    String to,
    BigInt amount,
    String memo,
  ) async {
    final wallet = _requireWallet();
    final prepared = await wallet.prepareSend(to, amount, memo, _clock());
    await wallet.save();
    _refresh();
    notifyListeners();
    final client = lightClient(settings.serverUri);
    try {
      await client.submit(prepared.transaction);
      return (txid: prepared.txid, delivered: true);
    } on LightException catch (e) {
      if (e.code == null) return (txid: prepared.txid, delivered: false);
      await wallet.sendRejected(prepared.operation, e.message);
      await wallet.save();
      _refresh();
      notifyListeners();
      rethrow;
    } finally {
      client.close();
    }
  }

  /// The recovery phrase, after the passphrase is entered again.
  Future<String> revealPhrase(String passphrase) =>
      _requireWallet().revealPhrase(passphrase);

  WalletHandle _requireWallet() {
    final wallet = _wallet;
    if (wallet == null) throw StateError('the wallet is locked');
    return wallet;
  }

  Future<void> _loadAddress() async {
    final wallet = _wallet;
    if (wallet == null) return;
    final address = await wallet.receiveAddress();
    await wallet.save();
    if (identical(_wallet, wallet)) {
      _address = address;
      notifyListeners();
    }
  }

  void _refresh() {
    final wallet = _wallet;
    if (wallet == null) return;
    _balance = wallet.balance();
    _activity = wallet.activity();
  }

  void _setStatus(WalletStatus status) {
    _status = status;
    notifyListeners();
  }

  bool _disposed = false;

  /// A sync or send can finish after the app is gone; drop its update.
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    lock();
    _disposed = true;
    super.dispose();
  }
}
