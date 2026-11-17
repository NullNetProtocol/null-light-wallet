import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:null_light_wallet/src/app.dart';
import 'package:null_light_wallet/src/settings.dart';
import 'package:null_light_wallet/src/ui/send_page.dart';
import 'package:null_light_wallet/src/wallet_model.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

const pass = 'correct horse';
const request = 'null:null1good7?amount=1.25&message=Invoice%20%2342';

void main() {
  late FakeServer server;
  late FakeCore core;

  setUp(() async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    server = FakeServer(['h0', 'pay:250000000', 'h2']);
    core = FakeCore();
    await core.store.create(fakeWords.join(' '), pass);
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

  Future<void> openSend(WidgetTester tester) async {
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
  }

  testWidgets('a pasted payment URI fills address and amount', (tester) async {
    await start(tester);
    await unlock(tester);
    await openSend(tester);
    await tester.enterText(find.byType(TextField).at(0), request);
    await tester.pump();
    expect(field(tester, 0), 'null1good7');
    expect(field(tester, 1), '1.25');
    expect(find.text('Invoice #42'), findsOneWidget);
    expect(field(tester, 2), isEmpty, reason: 'the memo stays the payer\'s');
    expect(server.submitted, isEmpty);

    // Typing an address of one's own drops the request's message.
    await tester.enterText(find.byType(TextField).at(0), 'null1good8');
    await tester.pump();
    expect(find.byKey(const Key('request-message')), findsNothing);
  });

  testWidgets('an invalid payment URI says why and fills nothing', (
    tester,
  ) async {
    await start(tester);
    await unlock(tester);
    await openSend(tester);
    await tester.enterText(
      find.byType(TextField).at(0),
      'null:null1good7?amount=1e3',
    );
    await tester.pump();
    expect(find.text('The payment link has an invalid amount'), findsOneWidget);
    expect(field(tester, 1), isEmpty);
  });

  testWidgets('Scan QR code fills the fields from the code', (tester) async {
    tallView(tester);
    final model = WalletModel(
      core: core,
      settings: await AppSettings.load(),
      lightClient: server.client,
      syncEvery: const Duration(hours: 1),
    );
    addTearDown(model.dispose);
    await model.load();
    await model.unlock(pass);
    var scans = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SendPage(
            model: model,
            scanner: (_) async {
              scans++;
              return scans == 1 ? null : request;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Backing out of the scanner changes nothing.
    await tester.tap(find.text('Scan QR code'));
    await tester.pumpAndSettle();
    expect(field(tester, 0), isEmpty);

    await tester.tap(find.text('Scan QR code'));
    await tester.pumpAndSettle();
    expect(field(tester, 0), 'null1good7');
    expect(field(tester, 1), '1.25');

    // A code holding a bare address fills only the address.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SendPage(
            key: UniqueKey(),
            model: model,
            scanner: (_) async => 'null1good9',
          ),
        ),
      ),
    );
    await tester.tap(find.text('Scan QR code'));
    await tester.pumpAndSettle();
    expect(field(tester, 0), 'null1good9');
    expect(field(tester, 1), isEmpty);
    model.lock();
  });

  testWidgets('no scanner, no button', (tester) async {
    await start(tester);
    await unlock(tester);
    await openSend(tester);
    expect(find.text('Scan QR code'), findsNothing);
  });
}
