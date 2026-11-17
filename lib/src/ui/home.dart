import 'package:flutter/material.dart';

import '../app.dart';
import '../wallet_model.dart';
import 'receive_page.dart';
import 'send_page.dart';
import 'settings_page.dart';
import 'wallet_page.dart';

/// The four tabs of an unlocked wallet: Wallet, Receive, Send, Settings.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.model, required this.lightClient});

  final WalletModel model;
  final LightClientFactory lightClient;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _send = GlobalKey<SendPageState>();

  static const _sendTab = 2;

  @override
  void initState() {
    super.initState();
    widget.model.paymentLink.addListener(_onPaymentLink);
    // A link that arrived while the wallet was locked.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onPaymentLink());
  }

  @override
  void dispose() {
    widget.model.paymentLink.removeListener(_onPaymentLink);
    super.dispose();
  }

  /// Opens the Send tab with the link's fields filled. Never sends.
  void _onPaymentLink() {
    final link = widget.model.paymentLink.value;
    final send = _send.currentState;
    if (link == null || send == null || !mounted) return;
    widget.model.paymentLink.value = null;
    setState(() => _tab = _sendTab);
    send.fill(link);
  }

  static const _titles = ['Wallet', 'Receive', 'Send', 'Settings'];

  @override
  Widget build(BuildContext context) {
    final pages = [
      WalletPage(model: widget.model),
      ReceivePage(model: widget.model),
      SendPage(
        key: _send,
        model: widget.model,
        onSent: () => setState(() => _tab = 0),
      ),
      SettingsPage(model: widget.model, lightClient: widget.lightClient),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          IconButton(
            tooltip: 'Lock',
            icon: const Icon(Icons.lock_outline),
            onPressed: widget.model.lock,
          ),
        ],
      ),
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
