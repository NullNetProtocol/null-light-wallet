import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:null_light_wallet/src/app.dart';
import 'package:null_light_wallet/src/core/wallet_core.dart';
import 'package:null_light_wallet/src/light/light_client.dart';
import 'package:null_light_wallet/src/light/network.dart';
import 'package:null_light_wallet/src/settings.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

/// A core that accepts addresses starting with `null1good`.
class FakeCore implements WalletCore {
  @override
  bool get available => true;

  @override
  String get version => '9.9.9';

  @override
  AddressValidity checkAddress(String address) =>
      address.startsWith('null1good')
      ? const AddressValidity(true)
      : const AddressValidity(false, 'invalid checksum');
}

LightClient _server(Uri endpoint) => LightClient(
  endpoint,
  client: MockClient((request) async {
    final id = (jsonDecode(request.body) as Map)['id'];
    return http.Response(
      jsonEncode({
        'jsonrpc': '2.0',
        'result': {
          'network': 'main',
          'genesis': NullNetwork.main.genesis,
          'height': 19780,
          'best_block_hash': 'ab' * 32,
          'syncing': false,
          'coinbase_maturity': 100,
          'protocol_version': 3,
          'max_range': 100,
        },
        'id': id,
      }),
      200,
    );
  }),
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  Future<AppSettings> settings() => AppSettings.load();

  testWidgets('tabs switch and the wallet offers nothing that holds keys yet', (
    tester,
  ) async {
    await tester.pumpWidget(
      NullWalletApp(core: FakeCore(), settings: await settings()),
    );
    expect(find.text('No wallet yet'), findsOneWidget);
    final create = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Create wallet'),
    );
    expect(create.onPressed, isNull);
    await tester.tap(find.text('Receive'));
    await tester.pumpAndSettle();
    expect(find.textContaining('receiving address'), findsOneWidget);
  });

  testWidgets('the send screen checks addresses through the core', (
    tester,
  ) async {
    await tester.pumpWidget(
      NullWalletApp(core: FakeCore(), settings: await settings()),
    );
    await tester.tap(find.text('Send'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'null1bad');
    await tester.pump();
    expect(find.text('invalid checksum'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'null1good');
    await tester.pump();
    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('settings saves a server and tests the connection', (
    tester,
  ) async {
    final s = await settings();
    await tester.pumpWidget(
      NullWalletApp(core: FakeCore(), settings: s, lightClient: _server),
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('9.9.9'), findsOneWidget);

    final url = find.widgetWithText(TextField, 'Server URL');
    await tester.enterText(url, 'http://evil.example');
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.textContaining('Use https'), findsOneWidget);
    expect(s.server, defaultServers.first);

    await tester.enterText(url, 'https://node.example');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(s.server, 'https://node.example');

    await tester.tap(find.text('Test connection'));
    await tester.pumpAndSettle();
    expect(find.textContaining('height 19780'), findsOneWidget);
  });

  test('server URLs must be https, or http on loopback', () {
    expect(validateServer('https://light.nullnet.sh'), isNull);
    expect(validateServer('http://127.0.0.1:18461'), isNull);
    expect(validateServer('http://light.nullnet.sh'), isNotNull);
    expect(validateServer('light.nullnet.sh'), isNotNull);
    expect(validateServer(''), isNotNull);
  });
}
