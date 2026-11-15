import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'network.dart';

/// What `getlightinfo` reports: the tip and what identifies the chain.
class LightInfo {
  const LightInfo({
    required this.network,
    required this.genesis,
    required this.height,
    required this.bestBlockHash,
    required this.syncing,
    required this.coinbaseMaturity,
    required this.protocolVersion,
    required this.maxRange,
  });

  factory LightInfo.fromJson(Map<String, dynamic> json) => LightInfo(
    network: json['network'] as String,
    genesis: json['genesis'] as String,
    height: json['height'] as int,
    bestBlockHash: json['best_block_hash'] as String,
    syncing: json['syncing'] as bool,
    coinbaseMaturity: json['coinbase_maturity'] as int,
    protocolVersion: json['protocol_version'] as int,
    maxRange: json['max_range'] as int,
  );

  final String network;
  final String genesis;
  final int height;
  final String bestBlockHash;
  final bool syncing;
  final int coinbaseMaturity;
  final int protocolVersion;
  final int maxRange;

  /// Whether this server serves `expected`.
  bool isOn(NullNetwork expected) =>
      network == expected.name && genesis == expected.genesis;
}

/// A JSON-RPC error from the server, or a transport failure.
class LightException implements Exception {
  const LightException(this.message, {this.code});

  /// The JSON-RPC error code, or `null` for a transport failure.
  final int? code;
  final String message;

  @override
  String toString() => code == null
      ? 'LightException: $message'
      : 'LightException($code): $message';
}

/// A client for a node's public light-wallet listener
/// (`nulld run --light-listen`, `docs/rpc.md` Phase 5 in null-chain).
///
/// It only ever sends heights, raw transactions and txids: every wallet
/// asks for the same blocks, so the server cannot tell which notes are
/// ours.
class LightClient {
  LightClient(this.endpoint, {http.Client? client, this.timeout = _timeout})
    : _http = client ?? http.Client();

  static const _timeout = Duration(seconds: 30);

  final Uri endpoint;
  final Duration timeout;
  final http.Client _http;
  int _nextId = 1;

  /// The tip and the chain's identity.
  Future<LightInfo> info() async => LightInfo.fromJson(
    await _call('getlightinfo', []) as Map<String, dynamic>,
  );

  /// Fails unless the server is on `expected`, so nothing is scanned from
  /// another chain.
  Future<LightInfo> infoOn(NullNetwork expected) async {
    final got = await info();
    if (!got.isOn(expected)) {
      throw LightException(
        'server is on ${got.network} (${got.genesis}), not ${expected.name}',
      );
    }
    return got;
  }

  /// Main-chain hashes from `start`, ending early at the tip.
  Future<List<String>> blockHashes(int start, int count) async =>
      (await _call('getblockhashes', [start, count]) as List).cast<String>();

  /// Compact blocks from `start`, ending early at the tip or the
  /// server's byte cap. Ask again from the next height.
  Future<List<Uint8List>> compactBlocks(int start, int count) async =>
      (await _call('getcompactblocks', [start, count]) as List)
          .map((hex) => fromHex(hex as String))
          .toList();

  /// Submits a built transaction; returns its txid.
  Future<String> submit(Uint8List transaction) async =>
      await _call('sendrawtransaction', [toHex(transaction)]) as String;

  /// Where a transaction is: pooled, confirmed or unknown.
  Future<Map<String, dynamic>> transactionStatus(String txid) async =>
      await _call('gettransactionstatus', [txid]) as Map<String, dynamic>;

  Future<Object?> _call(String method, List<Object?> params) async {
    final id = _nextId++;
    final http.Response response;
    try {
      response = await _http
          .post(
            endpoint,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': method,
              'params': params,
              'id': id,
            }),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw LightException('$method timed out');
    } on http.ClientException catch (e) {
      throw LightException('$method: ${e.message}');
    } on Exception {
      // TLS and socket failures (no certificate yet, host down, offline)
      // carry platform detail the user cannot act on.
      throw LightException('could not reach the server ($method)');
    }
    if (response.statusCode != 200) {
      throw LightException('$method: HTTP ${response.statusCode}');
    }
    final Object? envelope;
    try {
      envelope = jsonDecode(response.body);
    } on FormatException {
      throw LightException('$method: not JSON');
    }
    if (envelope is! Map<String, dynamic> || envelope['id'] != id) {
      throw LightException('$method: malformed reply');
    }
    final error = envelope['error'];
    if (error is Map<String, dynamic>) {
      throw LightException(
        error['message'] as String? ?? 'error',
        code: error['code'] as int?,
      );
    }
    return envelope['result'];
  }

  void close() => _http.close();
}

/// Lowercase hex of `bytes`.
String toHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// Bytes of lowercase or uppercase hex; throws on anything else.
Uint8List fromHex(String hex) {
  if (hex.length.isOdd) throw const FormatException('odd hex length');
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final byte = int.tryParse(hex.substring(2 * i, 2 * i + 2), radix: 16);
    if (byte == null) throw FormatException('bad hex at ${2 * i}');
    out[i] = byte;
  }
  return out;
}
