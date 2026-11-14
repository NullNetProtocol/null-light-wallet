import 'package:flutter/material.dart';

import '../app.dart';
import '../core/wallet_core.dart';
import '../settings.dart';
import 'receive_page.dart';
import 'send_page.dart';
import 'settings_page.dart';
import 'wallet_page.dart';

/// The four tabs: Wallet, Receive, Send, Settings.
class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.core,
    required this.settings,
    required this.lightClient,
  });

  final WalletCore core;
  final AppSettings settings;
  final LightClientFactory lightClient;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  static const _titles = ['Wallet', 'Receive', 'Send', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      WalletPage(core: widget.core),
      const ReceivePage(),
      SendPage(core: widget.core),
      SettingsPage(
        core: widget.core,
        settings: widget.settings,
        lightClient: widget.lightClient,
      ),
    ];
    return Scaffold(
      appBar: AppBar(title: Text(_titles[_tab])),
      body: SafeArea(
        child: IndexedStack(index: _tab, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.account_balance_wallet_outlined),
            selectedIcon: Icon(Icons.account_balance_wallet),
            label: 'Wallet',
          ),
          NavigationDestination(
            icon: Icon(Icons.call_received),
            label: 'Receive',
          ),
          NavigationDestination(icon: Icon(Icons.call_made), label: 'Send'),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
