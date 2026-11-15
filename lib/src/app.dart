import 'package:flutter/material.dart';

import 'core/wallet_core.dart';
import 'light/light_client.dart';
import 'settings.dart';
import 'theme.dart';
import 'ui/home.dart';
import 'ui/onboarding/welcome_page.dart';
import 'ui/unlock_page.dart';
import 'wallet_model.dart';

/// Builds a client for a light server; tests pass a fake.
typedef LightClientFactory = LightClient Function(Uri endpoint);

LightClient _defaultClient(Uri endpoint) => LightClient(endpoint);

/// The app: Material 3, black and white, following the system theme.
class NullWalletApp extends StatefulWidget {
  const NullWalletApp({
    super.key,
    required this.core,
    required this.settings,
    this.lightClient = _defaultClient,
    this.model,
  });

  final WalletCore core;
  final AppSettings settings;
  final LightClientFactory lightClient;

  /// The wallet state; built from the other fields when not given.
  final WalletModel? model;

  @override
  State<NullWalletApp> createState() => _NullWalletAppState();
}

class _NullWalletAppState extends State<NullWalletApp>
    with WidgetsBindingObserver {
  late final WalletModel _model =
      widget.model ??
      WalletModel(
        core: widget.core,
        settings: widget.settings,
        lightClient: widget.lightClient,
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _model.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.model == null) _model.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _model.paused();
      case AppLifecycleState.resumed:
        _model.resumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NULL Wallet',
      debugShowCheckedModeBanner: false,
      theme: nullTheme(Brightness.light),
      darkTheme: nullTheme(Brightness.dark),
      home: ListenableBuilder(
        listenable: _model,
        builder: (context, _) => switch (_model.status) {
          WalletStatus.loading => const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          ),
          WalletStatus.none => WelcomePage(model: _model),
          WalletStatus.locked => UnlockPage(model: _model),
          WalletStatus.unlocked => HomeShell(
            model: _model,
            lightClient: widget.lightClient,
          ),
        },
      ),
    );
  }
}
