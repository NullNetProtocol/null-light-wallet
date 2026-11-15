import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:null_light_wallet/src/light/light_client.dart';
import 'package:null_light_wallet/src/light/sync.dart';

import 'fakes.dart';

final _endpoint = Uri.parse('https://light.example');

List<String> chain(int length, {String prefix = 'h'}) => [
  for (var i = 0; i < length; i++) '$prefix$i',
];

FakeWallet wallet() => FakeWallet(words: 'w', passphrase: 'p');

void main() {
  test('a new wallet scans the whole chain in server-sized ranges', () async {
    final server = FakeServer(chain(250)..[120] = 'pay:500', maxRange: 100);
    final w = wallet();
    final progress = <int>[];
    final outcome = await syncWallet(
      server.client(_endpoint),
      w,
      onProgress: (next, tip) => progress.add(next),
    );
    expect(w.scanned, server.chain);
    expect(outcome.tip, 249);
    expect(outcome.blocks, 250);
    expect(outcome.found, 1);
    expect(outcome.rolledBack, 0);
    expect(progress, [0, 100, 200, 250]);
    expect(w.saves, 3, reason: 'saved after each range');
    expect(w.balance().total, BigInt.from(500));
    expect(server.methods.where((m) => m == 'getcompactblocks').length, 3);
  });

  test('an up-to-date wallet asks for no blocks', () async {
    final server = FakeServer(chain(10));
    final w = wallet()..scanned.addAll(chain(10));
    final outcome = await syncWallet(server.client(_endpoint), w);
    expect(outcome.blocks, 0);
    expect(server.methods, isNot(contains('getcompactblocks')));
  });

  test('a reorganization rolls back to the fork and rescans', () async {
    final server = FakeServer([...chain(8), 'x8', 'x9', 'x10']);
    final w = wallet()..scanned.addAll(chain(10));
    final outcome = await syncWallet(server.client(_endpoint), w);
    expect(w.rollbacks, [7]);
    expect(outcome.rolledBack, 2);
    expect(w.scanned, server.chain);
  });

  test('a fork deeper than one range is still found', () async {
    final server = FakeServer([
      ...chain(5),
      ...chain(30, prefix: 'x').skip(5),
    ], maxRange: 10);
    final w = wallet()..scanned.addAll(chain(30));
    await syncWallet(server.client(_endpoint), w);
    expect(w.rollbacks, [4]);
    expect(w.scanned, server.chain);
  });

  test('a server behind the wallet undoes nothing', () async {
    final server = FakeServer(chain(5));
    final w = wallet()..scanned.addAll(chain(9));
    final outcome = await syncWallet(server.client(_endpoint), w);
    expect(w.rollbacks, isEmpty);
    expect(outcome.blocks, 0);
    expect(w.scanned, chain(9));
  });

  test('a server sharing no blocks is refused', () async {
    final server = FakeServer(chain(5, prefix: 'other'));
    final w = wallet()..scanned.addAll(chain(5));
    await expectLater(
      syncWallet(server.client(_endpoint), w),
      throwsA(isA<LightException>()),
    );
    expect(w.rollbacks, isEmpty);
  });

  test('a server on another network is refused before scanning', () async {
    final server = FakeServer(chain(5), network: 'test');
    final w = wallet();
    await expectLater(
      syncWallet(server.client(_endpoint), w),
      throwsA(isA<LightException>()),
    );
    expect(w.scanned, isEmpty);
    expect(server.methods, ['getlightinfo']);
  });

  test('pending payments are submitted again, refusals ignored', () async {
    final server = FakeServer(chain(3));
    final w = wallet()..pending.add(Uint8List.fromList(utf8.encode('tx1')));
    await syncWallet(server.client(_endpoint), w);
    expect(server.submitted, [toHex(Uint8List.fromList(utf8.encode('tx1')))]);

    server.rejectCode = -26;
    await syncWallet(server.client(_endpoint), w);
    expect(w.pending, hasLength(1), reason: 'a resubmit never fails it');
  });
}
