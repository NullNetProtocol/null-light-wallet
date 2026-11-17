import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:null_light_wallet/src/app.dart';
import 'package:null_light_wallet/src/core/payment_uri.dart';
import 'package:null_light_wallet/src/settings.dart';
import 'package:null_light_wallet/src/wallet_model.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

const pass = 'correct horse';
const request = 'null:null1good7?amount=1.25&message=Invoice%20%2342';

void main() {
  late FakeServer server;
  late FakeCore core;
  void Function(String)? deliver;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = FakeServer(['h0', 'pay:250000000', 'h2']);
    core = FakeCore();
    await core.store.create(fakeWords.join(' '), pass);
    deliver = null;
  });

  void tallView(WidgetTester tester) {
    tester.view
      ..physicalSize = const Size(1080, 3200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
  }

  Future<void> start(WidgetTester tester) async {
    tallView(tester);
    await tester.pumpWidget(
      NullWalletApp(
        core: core,
        settings: await AppSettings.load(),
        lightClient: server.client,
        paymentLinks: (onLink) => deliver = onLink,
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> unlock(WidgetTester tester) async {
    await tester.enterText(find.byType(TextField), pass);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
  }

  String field(WidgetTester tester, int index) => tester
      .widget<TextField>(find.byType(TextField).at(index))
      .controller!
      .text;

  testWidgets('a link while locked opens Send after unlocking', (tester) async {
    await start(tester);
    deliver!(request);
    await tester.pumpAndSettle();
    expect(find.text('Unlock your wallet'), findsOneWidget);
    await unlock(tester);
    expect(find.text('Review payment'), findsOneWidget);
    expect(field(tester, 0), 'null1good7');
    expect(field(tester, 1), '1.25');
    expect(server.submitted, isEmpty);
  });

  testWidgets('a link while unlocked switches to Send', (tester) async {
    await start(tester);
    await unlock(tester);
    expect(find.text('Review payment'), findsNothing);
    deliver!(request);
    await tester.pumpAndSettle();
    expect(find.text('Review payment'), findsOneWidget);
    expect(field(tester, 1), '1.25');

    // The same link again still arrives.
    await tester.tap(find.text('Wallet'));
    await tester.pumpAndSettle();
    deliver!(request);
    await tester.pumpAndSettle();
    expect(find.text('Review payment'), findsOneWidget);
  });

  test('deleting the wallet drops a waiting link', () async {
    final model = WalletModel(
      core: core,
      settings: await AppSettings.load(),
      lightClient: server.client,
    );
    addTearDown(model.dispose);
    await model.load();
    model.openPaymentLink(request);
    await model.delete();
    expect(model.paymentLink.value, isNull);
  });

  test('a text longer than any payment URI is ignored', () async {
    final model = WalletModel(
      core: core,
      settings: await AppSettings.load(),
      lightClient: server.client,
    );
    addTearDown(model.dispose);
    model.openPaymentLink('null:${'a' * maxPaymentUriChars}');
    expect(model.paymentLink.value, isNull);
    model.openPaymentLink(request);
    expect(model.paymentLink.value, request);
  });
}
