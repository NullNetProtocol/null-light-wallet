import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:null_light_wallet/src/app.dart';
import 'package:null_light_wallet/src/light/network.dart';
import 'package:null_light_wallet/src/settings.dart';
import 'package:null_light_wallet/src/core/wallet_core.dart';
import 'package:null_light_wallet/src/ui/onboarding/create_flow.dart';
import 'package:null_light_wallet/src/ui/wallet_page.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

const pass = 'correct horse';

/// Scrolls `finder` into view, then taps it.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late FakeServer server;

  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = FakeServer(['h0', 'pay:250000000', 'h2']);
  });

  Future<void> start(WidgetTester tester, FakeCore core) async {
    // A tall phone, so every list fits without scrolling.
    tester.view
      ..physicalSize = const Size(1080, 3200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      NullWalletApp(
        core: core,
        settings: await AppSettings.load(),
        lightClient: server.client,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the app on an unlocked wallet holding 2.5 NULL.
  Future<FakeCore> unlocked(WidgetTester tester) async {
    final core = FakeCore();
    await core.store.create(fakeWords.join(' '), pass);
    await start(tester, core);
    await tester.enterText(find.byType(TextField), pass);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    return core;
  }

  testWidgets('creating a wallet shows the phrase and asks words back', (
    tester,
  ) async {
    final core = FakeCore();
    await start(tester, core);
    await tester.tap(find.text('Create a new wallet'));
    await tester.pumpAndSettle();
    expect(find.text(' 1. word1'), findsOneWidget);
    expect(find.text('24. word24'), findsOneWidget);
    await tapVisible(tester, find.text('I have written it down'));

    final fields = find.byType(TextField);
    expect(fields, findsNWidgets(confirmCount));
    for (var i = 0; i < confirmCount; i++) {
      await tester.enterText(fields.at(i), 'wrong');
    }
    await tapVisible(tester, find.text('Continue'));
    expect(find.textContaining('does not match'), findsOneWidget);

    for (var i = 0; i < confirmCount; i++) {
      final label = tester
          .widget<TextField>(fields.at(i))
          .decoration!
          .labelText!; // "Word N"
      await tester.enterText(fields.at(i), 'word${label.split(' ').last}');
    }
    await tapVisible(tester, find.text('Continue'));

    await tester.enterText(find.byType(TextField).at(0), pass);
    await tester.enterText(find.byType(TextField).at(1), 'different');
    await tapVisible(tester, find.text('Create wallet'));
    expect(find.text('The passphrases differ'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(1), pass);
    await tapVisible(tester, find.text('Create wallet'));

    expect(core.store.words, fakeWords.join(' '));
    expect(core.store.passphrase, pass);
    expect(find.text('2.5 NULL'), findsOneWidget);
    expect(find.text('Up to date at block 2'), findsOneWidget);
    expect(find.text('Received'), findsOneWidget);
  });

  testWidgets('restoring checks the phrase first', (tester) async {
    final core = FakeCore();
    await start(tester, core);
    await tester.tap(find.text('Restore from a recovery phrase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'too few words');
    await tapVisible(tester, find.text('Continue'));
    expect(find.text('a phrase has 24 words'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      fakeWords.join('  ').toUpperCase(),
    );
    await tapVisible(tester, find.text('Continue'));
    await tester.enterText(find.byType(TextField).at(0), pass);
    await tester.enterText(find.byType(TextField).at(1), pass);
    await tapVisible(
      tester,
      find.widgetWithText(FilledButton, 'Restore wallet'),
    );
    expect(core.store.words, fakeWords.join(' '));
    expect(find.text('2.5 NULL'), findsOneWidget);
  });

  testWidgets('a wrong passphrase does not unlock', (tester) async {
    final core = FakeCore();
    await core.store.create('w', pass);
    await start(tester, core);
    await tester.enterText(find.byType(TextField), 'guess');
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    expect(find.text('wrong passphrase'), findsOneWidget);
    expect(find.text('Unlock your wallet'), findsOneWidget);
  });

  testWidgets('receive shows the address and hands out new ones', (
    tester,
  ) async {
    await unlocked(tester);
    await tester.tap(find.text('Receive'));
    await tester.pumpAndSettle();
    expect(find.text('null1good1'), findsOneWidget);
    await tester.tap(find.text('New address'));
    await tester.pumpAndSettle();
    expect(find.text('null1good2'), findsOneWidget);
  });

  testWidgets('send reviews the fee, then pays', (tester) async {
    final core = await unlocked(tester);
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'null1bad');
    await tester.pump();
    expect(find.text('invalid checksum'), findsOneWidget);
    await tester.enterText(fields.at(0), 'null1good7');
    await tester.enterText(fields.at(1), 'lots');
    await tester.tap(find.text('Review payment'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter an amount'), findsOneWidget);

    await tester.enterText(fields.at(1), '1.25');
    await tester.enterText(fields.at(2), 'for coffee');
    await tester.tap(find.text('Review payment'));
    await tester.pumpAndSettle();
    expect(find.text('0.0001 NULL'), findsOneWidget);
    expect(find.text('1.2501 NULL'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    expect(server.submitted, hasLength(1));
    expect(core.store.wallet!.sends.single.memo, 'for coffee');
    expect(find.text('Sending'), findsOneWidget);
    expect(find.text('1.2499 NULL'), findsOneWidget);
  });

  testWidgets('settings shows the phrase after the passphrase', (tester) async {
    await unlocked(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('9.9.9'), findsOneWidget);
    await tester.tap(find.text('Show recovery phrase'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'nope');
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('wrong passphrase'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, pass);
    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    expect(find.text('24. word24'), findsOneWidget);
  });

  testWidgets('settings saves a server and tests the connection', (
    tester,
  ) async {
    await unlocked(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    final url = find.widgetWithText(TextField, 'Server URL');
    await tester.enterText(url, 'http://evil.example');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('Use https'), findsOneWidget);

    await tester.enterText(url, 'https://node.example');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('main network at height 2'), findsOneWidget);
  });

  testWidgets('settings changes the auto-lock time', (tester) async {
    await unlocked(tester);
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('After 5 minutes in the background'), findsOneWidget);
    await tester.tap(find.text('Auto-lock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10 minutes'));
    await tester.pumpAndSettle();
    expect(find.text('After 10 minutes in the background'), findsOneWidget);
    expect((await AppSettings.load()).lockAfterMinutes, 10);
  });

  testWidgets('lock and delete', (tester) async {
    final core = await unlocked(tester);
    await tester.tap(find.byTooltip('Lock'));
    await tester.pumpAndSettle();
    expect(find.text('Unlock your wallet'), findsOneWidget);
    await tester.tap(find.text('Forgot the passphrase?'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(await core.store.exists(), isFalse);
    expect(find.text('Create a new wallet'), findsOneWidget);
  });

  test('server URLs must be https, or http on loopback', () {
    expect(validateServer('https://light.nullnet.sh'), isNull);
    expect(validateServer('http://127.0.0.1:18461'), isNull);
    expect(validateServer('http://light.nullnet.sh'), isNotNull);
    expect(validateServer('light.nullnet.sh'), isNotNull);
    expect(validateServer(''), isNotNull);
    expect(defaultServers, ['https://light.nullnet.sh']);
  });

  test('the words to confirm are distinct and in order', () {
    for (var seed = 0; seed < 50; seed++) {
      final picked = pickChallenge(Random(seed), 24, confirmCount);
      expect(picked.toSet(), hasLength(confirmCount));
      expect(picked, List.of(picked)..sort());
      expect(picked.every((i) => i >= 0 && i < 24), isTrue);
    }
  });

  testWidgets('a send known only from the chain says the fee is included', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 3200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ActivityTile(
            item: ActivityItem(
              kind: ActivityKind.sent,
              amount: BigInt.from(200020000),
              height: 120,
              state: SendState.confirmed,
              includesFee: true,
            ),
          ),
        ),
      ),
    );
    expect(find.text('Sent'), findsOneWidget);
    expect(find.text('−2.0002'), findsOneWidget);
    expect(find.text('block 120 · network fee included'), findsOneWidget);
  });
}
