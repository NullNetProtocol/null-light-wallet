import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:null_light_wallet/src/app.dart';
import 'package:null_light_wallet/src/core/payment_uri.dart';
import 'package:null_light_wallet/src/settings.dart';
import 'package:null_light_wallet/src/ui/receive_page.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'fakes.dart';

const pass = 'correct horse';
const addr = 'null1good1';

void main() {
  group('receiveData', () {
    test('nothing requested shows the bare address', () {
      final shown = receiveData(addr, '', '  ');
      expect(shown.data, addr);
      expect(shown.amountError, isNull);
      expect(shown.messageError, isNull);
    });

    test('an amount and a message make a payment URI', () {
      expect(
        receiveData(addr, ' 1.5 ', ' Rent ').data,
        'null:$addr?amount=1.5&message=Rent',
      );
      expect(receiveData(addr, '', 'hi').data, 'null:$addr?message=hi');
      expect(receiveData(addr, '2', '').data, 'null:$addr?amount=2');
    });

    test('a bad amount is left out and named', () {
      for (final bad in ['0', 'x', '1,5', '1.123456789', '99999999']) {
        final shown = receiveData(addr, bad, '');
        expect(shown.data, addr, reason: bad);
        expect(shown.amountError, isNotNull, reason: bad);
      }
      expect(receiveData(addr, 'x', 'hi').data, 'null:$addr?message=hi');
    });

    test('a message over the limit in code points is left out', () {
      final emoji = '👍' * maxPaymentMessageChars;
      expect(receiveData(addr, '', emoji).messageError, isNull);
      final long = '${emoji}a';
      final shown = receiveData(addr, '1', long);
      expect(shown.data, 'null:$addr?amount=1');
      expect(shown.messageError, isNotNull);
    });

    test('what it shows, the parser reads', () {
      final data = receiveData(addr, '0.25', 'café & co').data;
      final request = parsePaymentUri(
        data,
        checkAddress: FakeCore().checkAddress,
      ).request!;
      expect(request.address, addr);
      expect(request.amount, BigInt.from(25000000));
      expect(request.message, 'café & co');
    });
  });

  testWidgets('receive turns into a payment request and copies it', (
    tester,
  ) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    tester.view
      ..physicalSize = const Size(1080, 3200)
      ..devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    final core = FakeCore();
    await core.store.create(fakeWords.join(' '), pass);
    await tester.pumpWidget(
      NullWalletApp(
        core: core,
        settings: await AppSettings.load(),
        lightClient: FakeServer(['h0']).client,
        paymentLinks: (_) {},
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), pass);
    await tester.tap(find.text('Unlock'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Receive'));
    await tester.pumpAndSettle();
    expect(find.text(addr), findsOneWidget);
    expect(find.text('Copy address'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '3');
    await tester.enterText(
      find.widgetWithText(TextField, 'Message for the payer'),
      'Lunch',
    );
    await tester.pump();
    const uri = 'null:$addr?amount=3&message=Lunch';
    expect(find.text(uri), findsOneWidget);
    await tester.tap(find.text('Copy payment link'));
    await tester.pump();
    expect(copied, uri);
  });
}
