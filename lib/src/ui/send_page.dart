import 'package:flutter/material.dart';

import '../core/amount.dart';
import '../core/wallet_core.dart';
import '../wallet_model.dart';
import 'widgets.dart';

/// Longest memo, in bytes of UTF-8, as the chain allows.
const maxMemoBytes = 512;

/// Recipient, amount and memo, then a review with the exact fee.
class SendPage extends StatefulWidget {
  const SendPage({super.key, required this.model, this.onSent});

  final WalletModel model;

  /// Called after a payment went out, to show the activity.
  final VoidCallback? onSent;

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final _address = TextEditingController();
  final _amount = TextEditingController();
  final _memo = TextEditingController();
  AddressValidity? _check;
  String? _amountError;
  bool _busy = false;
  String? _busyLabel;

  @override
  void dispose() {
    _address.dispose();
    _amount.dispose();
    _memo.dispose();
    super.dispose();
  }

  void _onAddress(String value) => setState(() {
    _check = value.trim().isEmpty
        ? null
        : widget.model.core.checkAddress(value);
  });

  Future<void> _review() async {
    final to = _address.text.trim();
    final check = widget.model.core.checkAddress(to);
    final amount = parseAmount(_amount.text);
    setState(() {
      _check = check;
      _amountError = amount == null || amount == BigInt.zero
          ? 'Enter an amount, like 1.5'
          : null;
    });
    if (!check.valid || _amountError != null) return;
    final fee = await _run('Checking…', () => widget.model.quote(to, amount!));
    if (fee == null || !mounted) return;
    final go = await _confirm(to, amount!, fee);
    if (go != true || !mounted) return;
    final result = await _run(
      'Proving the payment…',
      () => widget.model.send(to, amount, _memo.text),
    );
    if (result == null || !mounted) return;
    _address.clear();
    _amount.clear();
    _memo.clear();
    setState(() => _check = null);
    showMessage(
      context,
      result.delivered
          ? 'Payment sent. It confirms in the next blocks.'
          : 'Payment built, but the server did not answer. It is sent '
                'again on the next sync.',
    );
    widget.onSent?.call();
  }

  /// Runs `task` with the button busy; shows its error and returns `null`
  /// if it fails.
  Future<T?> _run<T>(String label, Future<T> Function() task) async {
    setState(() {
      _busy = true;
      _busyLabel = label;
    });
    try {
      return await task();
    } catch (e) {
      if (mounted) showMessage(context, describeError(e));
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(String to, BigInt amount, BigInt fee) =>
      showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Review payment'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('To'),
              SelectableText(
                to,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
              const SizedBox(height: 12),
              _row('Amount', '${formatAmount(amount)} NULL'),
              _row('Network fee', '${formatAmount(fee)} NULL'),
              const Divider(),
              _row('Total', '${formatAmount(amount + fee)} NULL', bold: true),
              if (_memo.text.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Memo: ${_memo.text}'),
              ],
              const SizedBox(height: 12),
              const Text('Payments cannot be undone.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Send'),
            ),
          ],
        ),
      );

  static Widget _row(String label, String value, {bool bold = false}) {
    final style = bold ? const TextStyle(fontWeight: FontWeight.bold) : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: style),
          const Spacer(),
          Text(value, style: style),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final spendable = widget.model.balance?.spendable;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextField(
              controller: _address,
              onChanged: _onAddress,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Recipient address',
                hintText: 'null1…',
                errorText: check != null && !check.valid ? check.reason : null,
                suffixIcon: check != null && check.valid
                    ? const Icon(Icons.check, semanticLabel: 'Valid address')
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                suffixText: 'NULL',
                errorText: _amountError,
                helperText: spendable == null
                    ? null
                    : '${formatAmount(spendable)} NULL spendable',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _memo,
              maxLength: maxMemoBytes,
              decoration: const InputDecoration(
                labelText: 'Memo (optional)',
                helperText: 'Encrypted: only the recipient can read it.',
              ),
            ),
            const SizedBox(height: 24),
            BusyButton(
              label: 'Review payment',
              busyLabel: _busyLabel,
              busy: _busy,
              onPressed: _review,
            ),
          ],
        );
      },
    );
  }
}
