import 'package:flutter/material.dart';

import '../wallet_model.dart';
import 'widgets.dart';

/// The passphrase prompt for an existing wallet.
class UnlockPage extends StatefulWidget {
  const UnlockPage({super.key, required this.model});

  final WalletModel model;

  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final _passphrase = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.model.unlock(_passphrase.text);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _forgot() async {
    final delete = await confirmDelete(context);
    if (delete) await widget.model.delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 48),
            Text(
              'Unlock your wallet',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 24),
            PassphraseField(
              controller: _passphrase,
              errorText: _error,
              autofocus: true,
              onSubmitted: (_) => _unlock(),
            ),
            const SizedBox(height: 24),
            BusyButton(
              label: 'Unlock',
              busyLabel: 'Unlocking…',
              busy: _busy,
              onPressed: _unlock,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: _busy ? null : _forgot,
              child: const Text('Forgot the passphrase?'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Asks before deleting the wallet from this device.
Future<bool> confirmDelete(BuildContext context) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this wallet?'),
        content: const Text(
          'The wallet is removed from this device. Your coins are not lost '
          'if you have the 24-word recovery phrase: restore from it to get '
          'them back. Without the phrase, they are gone for good.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    ) ??
    false;
