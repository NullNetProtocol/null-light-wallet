import 'package:flutter/material.dart';

import '../../wallet_model.dart';
import '../widgets.dart';
import 'create_flow.dart';
import 'restore_page.dart';

/// First launch: create a wallet or restore one.
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key, required this.model});

  final WalletModel model;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final available = model.core.available;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 48),
            Text('NULL Wallet', style: text.headlineMedium),
            const SizedBox(height: 12),
            Text(
              'A private wallet for the NULL network. Your keys stay on this '
              'device, sealed under your passphrase. No account, no tracking.',
              style: text.bodyLarge,
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: available
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => CreateFlow(model: model),
                      ),
                    )
                  : null,
              child: const Text('Create a new wallet'),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: available
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => RestorePage(model: model),
                      ),
                    )
                  : null,
              child: const Text('Restore from a recovery phrase'),
            ),
            if (!available) ...[
              const SizedBox(height: 24),
              const Notice(
                'This browser build does not include the wallet core yet. '
                'Use the Android app, or check back after the next release.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
