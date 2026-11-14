import 'package:flutter/material.dart';

import 'core/wallet_core.dart';
import 'light/light_client.dart';
import 'settings.dart';
import 'theme.dart';
import 'ui/home.dart';

/// Builds a client for a light server; tests pass a fake.
typedef LightClientFactory = LightClient Function(Uri endpoint);

LightClient _defaultClient(Uri endpoint) => LightClient(endpoint);

/// The app: Material 3, black and white, following the system theme.
class NullWalletApp extends StatelessWidget {
  const NullWalletApp({
    super.key,
    required this.core,
    required this.settings,
    this.lightClient = _defaultClient,
  });

  final WalletCore core;
  final AppSettings settings;
  final LightClientFactory lightClient;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NULL Wallet',
      debugShowCheckedModeBanner: false,
      theme: nullTheme(Brightness.light),
      darkTheme: nullTheme(Brightness.dark),
      home: HomeShell(core: core, settings: settings, lightClient: lightClient),
    );
  }
}
