import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:null_light_wallet/src/light/light_client.dart';
import 'package:null_light_wallet/src/light/network.dart';

final _info = {
  'network': 'main',
  'genesis': NullNetwork.main.genesis,
  'height': 19780,
  'best_block_hash': 'ab' * 32,
  'syncing': false,
  'coinbase_maturity': 100,
  'protocol_version': 3,
  'max_range': 100,
};

/// A server answering `method` with `result`, recording every request.
LightClient _serving(
  Map<String, Object?> results,
  List<Map<String, dynamic>> seen,
) {
  final mock = MockClient((request) async {
    final call = jsonDecode(request.body) as Map<String, dynamic>;
    seen.add(call);
    expect(request.headers['content-type'], startsWith('application/json'));
    expect(request.headers.containsKey('authorization'), isFalse);
    return http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        'result': results[call['method']],
        'id': call['id'],
      }),
      200,
    );
  });
  return LightClient(Uri.parse('https://light.example'), client: mock);
}

void main() {
  test('info is parsed and checked against the network', () async {
    final seen = <Map<String, dynamic>>[];
    final client = _serving({'getlightinfo': _info}, seen);
    final info = await client.infoOn(NullNetwork.main);
    expect(info.height, 19780);
    expect(info.maxRange, 100);
    expect(seen.single['method'], 'getlightinfo');
    expect(seen.single['jsonrpc'], '2.0');
  });

  test('a server on another chain is refused', () async {
    final other = {..._info, 'genesis': '00' * 32};
    final client = _serving({'getlightinfo': other}, []);
    expect(
      client.infoOn(NullNetwork.main),
      throwsA(
        isA<LightException>().having(
          (e) => e.message,
          'message',
          contains('not main'),
        ),
      ),
    );
  });

  test('ranges and submissions send only heights and raw bytes', () async {
    final seen = <Map<String, dynamic>>[];
    final client = _serving({
      'getblockhashes': ['aa' * 32],
      'getcompactblocks': ['0102ff'],
      'sendrawtransaction': 'cd' * 32,
    }, seen);
    expect(await client.blockHashes(5, 1), ['aa' * 32]);
    final blocks = await client.compactBlocks(5, 100);
    expect(blocks.single, Uint8List.fromList([1, 2, 255]));
    expect(await client.submit(Uint8List.fromList([0xde, 0xad])), 'cd' * 32);
    expect(seen.map((c) => c['params']), [
      [5, 1],
      [5, 100, 2],
      ['dead'],
    ]);
    expect(seen.map((c) => c['id']).toSet().length, 3, reason: 'fresh ids');
  });

  test(
    'RPC errors, HTTP errors and bad replies become LightException',
    () async {
      final errors = MockClient((request) async {
        final id = (jsonDecode(request.body) as Map)['id'];
        return http.Response(
          jsonEncode({
            'jsonrpc': '2.0',
            'error': {
              'code': -32602,
              'message': 'count must be between 1 and 100',
            },
            'id': id,
          }),
          200,
        );
      });
      final client = LightClient(Uri.parse('https://x'), client: errors);
      expect(
        client.compactBlocks(0, 101),
        throwsA(isA<LightException>().having((e) => e.code, 'code', -32602)),
      );
      for (final reply in [
        http.Response('busy', 503),
        http.Response('nope', 200),
      ]) {
        final bad = LightClient(
          Uri.parse('https://x'),
          client: MockClient((_) async => reply),
        );
        expect(bad.info(), throwsA(isA<LightException>()));
      }
      final wrongId = LightClient(
        Uri.parse('https://x'),
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'jsonrpc': '2.0', 'result': 1, 'id': 99}),
            200,
          ),
        ),
      );
      expect(wrongId.info(), throwsA(isA<LightException>()));
    },
  );

  test('hex round-trips and rejects garbage', () {
    final bytes = Uint8List.fromList([0, 15, 16, 255]);
    expect(toHex(bytes), '000f10ff');
    expect(fromHex('000F10ff'), bytes);
    expect(() => fromHex('abc'), throwsFormatException);
    expect(() => fromHex('zz'), throwsFormatException);
  });

  test('platform transport errors become a plain light error', () async {
    final client = LightClient(
      Uri.parse('https://light.example'),
      client: MockClient(
        (_) async => throw const FormatException('TLSV1_ALERT_INTERNAL_ERROR'),
      ),
    );
    await expectLater(
      client.info(),
      throwsA(
        isA<LightException>()
            .having((e) => e.code, 'code', isNull)
            .having(
              (e) => e.message,
              'message',
              'could not reach the server (getlightinfo)',
            ),
      ),
    );
  });
}
