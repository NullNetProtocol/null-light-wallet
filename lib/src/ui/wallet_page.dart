import 'package:flutter/material.dart';

import '../core/wallet_core.dart';

/// Balance and activity. Until wallets can be created, it explains what
/// is coming and offers nothing that would hold keys.
class WalletPage extends StatelessWidget {
  const WalletPage({super.key, required this.core});

  final WalletCore core;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('No wallet yet', style: text.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Create a new wallet or restore one from its 24-word recovery '
          'phrase. Keys never leave this device.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: 24),
        const FilledButton(onPressed: null, child: Text('Create wallet')),
        const SizedBox(height: 12),
        const OutlinedButton(onPressed: null, child: Text('Restore wallet')),
        const SizedBox(height: 24),
        if (!core.available)
          const _Notice(
            'This browser build does not include the wallet core yet. '
            'Use the Android app, or check back after the next release.',
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
