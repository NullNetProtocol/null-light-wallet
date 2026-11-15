import 'package:flutter/material.dart';

import '../../wallet_model.dart';
import '../widgets.dart';

/// Chooses the passphrase that seals the wallet on this device, then
/// calls `onCreate` with it. Shared by create and restore.
class PassphraseStep extends StatefulWidget {
  const PassphraseStep({
    super.key,
    required this.onCreate,
    this.action = 'Create wallet',
  });

  /// Creates the wallet; throws with a message on failure.
  final Future<void> Function(String passphrase) onCreate;
  final String action;

  @override
  State<PassphraseStep> createState() => _PassphraseStepState();
}

class _PassphraseStepState extends State<PassphraseStep> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _firstError;
  String? _secondError;
  bool _busy = false;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final firstError = passphraseProblem(_first.text);
    final secondError = _first.text == _second.text
        ? null
        : 'The passphrases differ';
    setState(() {
      _firstError = firstError;
      _secondError = firstError == null ? secondError : null;
    });
    if (firstError != null || secondError != null) return;
    setState(() => _busy = true);
    try {
      await widget.onCreate(_first.text);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Choose a passphrase',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        const Text(
          'It unlocks the wallet on this device. It is not a backup: if you '
          'forget it, restore the wallet from the recovery phrase.',
        ),
        const SizedBox(height: 24),
        PassphraseField(
          controller: _first,
          errorText: _firstError,
          helperText: 'At least $minPassphraseLength characters.',
          autofocus: true,
        ),
        const SizedBox(height: 16),
        PassphraseField(
          controller: _second,
          label: 'Repeat the passphrase',
          errorText: _secondError,
          onSubmitted: (_) => _submit(),
        ),
        const SizedBox(height: 24),
        BusyButton(
          label: widget.action,
          busyLabel: 'Sealing the wallet…',
          busy: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
