import 'package:flutter/material.dart';
import 'package:flutter_rust_bridge/flutter_rust_bridge.dart'
    show AnyhowException;

import '../light/light_client.dart';

/// A passphrase field with a show/hide toggle. Never autocorrected or
/// suggested, so the keyboard does not learn it.
class PassphraseField extends StatefulWidget {
  const PassphraseField({
    super.key,
    required this.controller,
    this.label = 'Passphrase',
    this.errorText,
    this.helperText,
    this.autofocus = false,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String label;
  final String? errorText;
  final String? helperText;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;

  @override
  State<PassphraseField> createState() => _PassphraseFieldState();
}

class _PassphraseFieldState extends State<PassphraseField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      enableIMEPersonalizedLearning: false,
      autofocus: widget.autofocus,
      keyboardType: TextInputType.visiblePassword,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        helperText: widget.helperText,
        helperMaxLines: 3,
        suffixIcon: IconButton(
          tooltip: _hidden ? 'Show' : 'Hide',
          icon: Icon(_hidden ? Icons.visibility : Icons.visibility_off),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

/// An outlined card with an icon and a message.
class Notice extends StatelessWidget {
  const Notice(this.message, {super.key, this.icon = Icons.info_outline});

  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

/// A filled button that shows a spinner and ignores taps while `busy`.
class BusyButton extends StatelessWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.busyLabel,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final String? busyLabel;

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: busy ? null : onPressed,
      child: busy
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(busyLabel ?? label),
              ],
            )
          : Text(label),
    );
  }
}

/// The message of an error for the user: the core's and the server's
/// errors are already sentences.
String describeError(Object error) => switch (error) {
  AnyhowException(:final message) => message.split('\n').first,
  LightException(:final message) => message,
  ArgumentError(:final message) => '$message',
  _ => '$error',
};

/// Shows `message` in a snack bar.
void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
