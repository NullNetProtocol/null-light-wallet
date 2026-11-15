import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:null_light_wallet/src/core/wallet_core.dart';
import 'package:null_light_wallet/src/light/light_client.dart';
import 'package:null_light_wallet/src/light/network.dart';

/// The phrase [FakeCore.generatePhrase] hands out: word1 … word24.
final fakeWords = [for (var i = 1; i <= 24; i++) 'word$i'];

/// A core that accepts addresses starting with `null1good` and phrases
/// of 24 words.
class FakeCore implements WalletCore {
  FakeCore({FakeStore? store}) : store = store ?? FakeStore();

  @override
  final FakeStore store;

  @override
  bool get available => true;

  @override
  String get version => '9.9.9';

  @override
  AddressValidity checkAddress(String address) =>
      address.startsWith('null1good')
      ? const AddressValidity(true)
      : const AddressValidity(false, 'invalid checksum');

  @override
  String generatePhrase() => fakeWords.join(' ');

  @override
  String? checkPhrase(String words) =>
      words.trim().split(RegExp(r'\s+')).length == 24
      ? null
      : 'a phrase has 24 words';

  @override
  Future<void> warmUpProving() async {}
}

/// A store holding at most one [FakeWallet].
class FakeStore implements WalletStore {
  FakeWallet? wallet;
  String? passphrase;
  String? words;

  @override
  Future<bool> exists() async => wallet != null;

  @override
  Future<WalletHandle> create(String words, String passphrase) async {
    if (wallet != null) throw StateError('a wallet exists');
    this.words = words;
    this.passphrase = passphrase;
    return wallet = FakeWallet(words: words, passphrase: passphrase);
  }

  @override
  Future<WalletHandle> open(String passphrase) async {
    final wallet = this.wallet;
    if (wallet == null) throw StateError('no wallet');
    if (passphrase != this.passphrase) {
      throw ArgumentError('wrong passphrase');
    }
    wallet.closed = false;
    return wallet;
  }

  @override
  Future<void> delete() async => wallet = null;
}

/// A wallet whose "blocks" are their hashes: it keeps the hashes it
/// scanned, and a block named `pay:<units>` pays it that much.
class FakeWallet implements WalletHandle {
  FakeWallet({required this.words, required this.passphrase});

  final String words;
  final String passphrase;
  final List<String> scanned = [];
  final List<int> rollbacks = [];
  final List<ActivityItem> sends = [];
  final List<Uint8List> pending = [];
  BigInt fee = BigInt.from(10000);
  bool closed = false;
  int saves = 0;
  int addresses = 1;

  BigInt get _received => scanned
      .where((h) => h.startsWith('pay:'))
      .map((h) => BigInt.parse(h.substring(4)))
      .fold(BigInt.zero, (a, b) => a + b);

  BigInt get _sent => sends
      .where((s) => s.state != SendState.failed)
      .map((s) => s.amount + fee)
      .fold(BigInt.zero, (a, b) => a + b);

  @override
  int nextHeight() => scanned.length;

  @override
  String? scannedHash(int height) =>
      height < scanned.length ? scanned[height] : null;

  @override
  Future<SyncStep> applyBlocks(List<Uint8List> blocks) async {
    var found = 0;
    for (final block in blocks) {
      final hash = utf8.decode(block);
      if (hash.startsWith('pay:')) found++;
      scanned.add(hash);
    }
    return SyncStep(
      blocks: blocks.length,
      found: found,
      spent: 0,
      nextHeight: scanned.length,
    );
  }

  @override
  Future<void> rollbackTo(int height) async {
    rollbacks.add(height);
    scanned.removeRange(height + 1, scanned.length);
  }

  @override
  Balance balance() {
    final total = _received - _sent;
    return Balance(total: total, spendable: total, pending: BigInt.zero);
  }

  @override
  Future<String> receiveAddress() async => 'null1good$addresses';

  @override
  Future<String> newAddress() async => 'null1good${++addresses}';

  @override
  List<ActivityItem> activity() => [
    ...sends,
    for (var h = scanned.length - 1; h >= 0; h--)
      if (scanned[h].startsWith('pay:'))
        ActivityItem(
          kind: ActivityKind.received,
          amount: BigInt.parse(scanned[h].substring(4)),
          height: h,
        ),
  ];

  @override
  Future<BigInt> quote(String to, BigInt amount) async {
    if (amount + fee > balance().spendable) {
      throw ArgumentError('insufficient funds');
    }
    return fee;
  }

  @override
  Future<PreparedSend> prepareSend(
    String to,
    BigInt amount,
    String memo,
    DateTime now,
  ) async {
    await quote(to, amount);
    final id = BigInt.from(sends.length + 1);
    final tx = Uint8List.fromList(utf8.encode('tx$id'));
    sends.insert(
      0,
      ActivityItem(
        kind: ActivityKind.sent,
        amount: amount,
        createdAt: BigInt.from(now.millisecondsSinceEpoch ~/ 1000),
        state: SendState.pending,
        address: to,
        txid: 'txid$id',
        memo: memo.isEmpty ? null : memo,
      ),
    );
    pending.add(tx);
    return PreparedSend(
      operation: id,
      txid: 'txid$id',
      transaction: tx,
      fee: fee,
    );
  }

  @override
  Future<void> sendRejected(BigInt operation, String reason) async {
    final index = sends.length - operation.toInt();
    final old = sends[index];
    sends[index] = ActivityItem(
      kind: old.kind,
      amount: old.amount,
      createdAt: old.createdAt,
      state: SendState.failed,
      address: old.address,
      txid: old.txid,
      error: reason,
    );
    pending.removeAt(operation.toInt() - 1);
  }

  @override
  List<Uint8List> pendingTransactions() => List.of(pending);

  @override
  Future<String> revealPhrase(String passphrase) async {
    if (passphrase != this.passphrase) throw ArgumentError('wrong passphrase');
    return words;
  }

  @override
  Future<void> save() async => saves++;

  @override
  void close() => closed = true;
}

/// A light server over a chain of block hashes (see [FakeWallet]).
class FakeServer {
  FakeServer(this.chain, {this.network = 'main', this.maxRange = 100});

  List<String> chain;
  String network;
  int maxRange;

  /// What `sendrawtransaction` does: `null` accepts, a code rejects with
  /// that JSON-RPC error, and [transportFailure] drops the reply.
  int? rejectCode;
  bool transportFailure = false;
  bool down = false;

  final List<String> submitted = [];
  final List<String> methods = [];

  LightClient client(Uri endpoint) =>
      LightClient(endpoint, client: MockClient(_handle));

  Future<http.Response> _handle(http.Request request) async {
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final method = body['method'] as String;
    final params = body['params'] as List;
    methods.add(method);
    if (down) throw http.ClientException('connection refused');
    Object? result;
    Map<String, Object?>? error;
    switch (method) {
      case 'getlightinfo':
        result = {
          'network': network,
          'genesis': network == 'main' ? NullNetwork.main.genesis : '00' * 32,
          'height': chain.length - 1,
          'best_block_hash': 'ab' * 32,
          'syncing': false,
          'coinbase_maturity': 100,
          'protocol_version': 3,
          'max_range': maxRange,
        };
      case 'getblockhashes':
        result = _range(params).toList();
      case 'getcompactblocks':
        result = _range(params)
            .map((h) => toHex(Uint8List.fromList(utf8.encode(h))))
            .toList();
      case 'sendrawtransaction':
        if (transportFailure) throw http.ClientException('reset');
        final code = rejectCode;
        if (code != null) {
          error = {'code': code, 'message': 'transaction rejected'};
        } else {
          submitted.add(params.first as String);
          result = 'txid';
        }
      default:
        error = {'code': -32601, 'message': 'method not found'};
    }
    return http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        if (error != null) 'error': error else 'result': result,
        'id': body['id'],
      }),
      200,
    );
  }

  Iterable<String> _range(List params) {
    final start = params[0] as int;
    final count = params[1] as int;
    if (count < 1 || count > maxRange) throw StateError('count $count');
    return chain.skip(start).take(count);
  }
}
