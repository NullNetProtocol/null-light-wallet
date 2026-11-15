import 'package:flutter_test/flutter_test.dart';
import 'package:null_light_wallet/src/core/wallet_core.dart';
import 'package:null_light_wallet/src/light/light_client.dart';
import 'package:null_light_wallet/src/settings.dart';
import 'package:null_light_wallet/src/wallet_model.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

const pass = 'correct horse';

void main() {
  late FakeServer server;
  late FakeCore core;
  late DateTime now;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = FakeServer(['h0', 'pay:300000000', 'h2']);
    core = FakeCore();
    now = DateTime(2026, 11, 15, 12);
  });

  Future<WalletModel> model() async => WalletModel(
    core: core,
    settings: await AppSettings.load(),
    lightClient: server.client,
    clock: () => now,
    syncEvery: const Duration(hours: 1),
  );

  Future<WalletModel> unlocked() async {
    final m = await model();
    await m.load();
    await m.create(fakeWords.join(' '), pass);
    await m.sync();
    return m;
  }

  test('no wallet, then create, lock and unlock', () async {
    final m = await model();
    await m.load();
    expect(m.status, WalletStatus.none);
    expect(() => m.create(fakeWords.join(' '), 'short'), throwsArgumentError);
    await m.create(fakeWords.join(' '), pass);
    expect(m.status, WalletStatus.unlocked);
    await m.sync();
    expect(m.balance!.total, BigInt.from(300000000));
    expect(m.upToDate, isTrue);
    expect(m.address, 'null1good1');

    m.lock();
    expect(m.status, WalletStatus.locked);
    expect(m.balance, isNull);
    expect(core.store.wallet!.closed, isTrue);
    await expectLater(m.unlock('wrong'), throwsArgumentError);
    expect(m.status, WalletStatus.locked);
    await m.unlock(pass);
    expect(m.status, WalletStatus.unlocked);
    m.dispose();
  });

  test('an existing wallet starts locked', () async {
    await core.store.create('w', pass);
    final m = await model();
    await m.load();
    expect(m.status, WalletStatus.locked);
  });

  test('the wallet locks after a minute in the background', () async {
    final m = await unlocked();
    m.paused();
    now = now.add(const Duration(seconds: 30));
    m.resumed();
    expect(m.status, WalletStatus.unlocked);
    m.paused();
    now = now.add(const Duration(minutes: 1));
    m.resumed();
    expect(m.status, WalletStatus.locked);
  });

  test('a sync failure is reported and the next one recovers', () async {
    final m = await unlocked();
    server
      ..chain = [...server.chain, 'h3']
      ..down = true;
    await m.sync();
    expect(m.syncError, contains('connection refused'));
    server.down = false;
    await m.sync();
    expect(m.syncError, isNull);
    expect(m.syncNext, 4);
  });

  test('a delivered payment is pending in the activity', () async {
    final m = await unlocked();
    final amount = BigInt.from(100000000);
    expect(await m.quote('null1good9', amount), BigInt.from(10000));
    final result = await m.send('null1good9', amount, 'thanks');
    expect(result.delivered, isTrue);
    expect(server.submitted, hasLength(1));
    final sent = m.activity.first;
    expect(sent.kind, ActivityKind.sent);
    expect(sent.state, SendState.pending);
    expect(sent.memo, 'thanks');
  });

  test('a refused payment fails and frees its notes', () async {
    final m = await unlocked();
    server.rejectCode = -26;
    await expectLater(
      m.send('null1good9', BigInt.from(100000000), ''),
      throwsA(isA<LightException>()),
    );
    expect(m.activity.first.state, SendState.failed);
    expect(core.store.wallet!.pending, isEmpty);
    expect(m.balance!.total, BigInt.from(300000000));
  });

  test('a lost reply keeps the payment pending for the next sync', () async {
    final m = await unlocked();
    server.transportFailure = true;
    final result = await m.send('null1good9', BigInt.from(100000000), '');
    expect(result.delivered, isFalse);
    expect(m.activity.first.state, SendState.pending);
    server.transportFailure = false;
    await m.sync();
    expect(server.submitted, hasLength(1));
  });

  test(
    'the phrase shows only with the passphrase; delete forgets all',
    () async {
      final m = await unlocked();
      await expectLater(m.revealPhrase('nope'), throwsArgumentError);
      expect(await m.revealPhrase(pass), fakeWords.join(' '));
      await m.delete();
      expect(m.status, WalletStatus.none);
      expect(await core.store.exists(), isFalse);
    },
  );

  test('new wallets need a passphrase of eight characters', () {
    expect(passphraseProblem('1234567'), isNotNull);
    expect(passphraseProblem('12345678'), isNull);
  });
}
