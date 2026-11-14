import 'package:flutter/material.dart';

import '../core/wallet_core.dart';

/// Recipient and amount. Sending needs a wallet; the address check
/// already runs through the core.
class SendPage extends StatefulWidget {
  const SendPage({super.key, required this.core});

  final WalletCore core;

  @override
  State<SendPage> createState() => _SendPageState();
}

class _SendPageState extends State<SendPage> {
  final _address = TextEditingController();
  AddressValidity? _check;

  @override
  void dispose() {
    _address.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    setState(() {
      _check = value.trim().isEmpty ? null : widget.core.checkAddress(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final check = _check;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: _address,
          onChanged: _onChanged,
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
        const TextField(
          enabled: false,
          decoration: InputDecoration(labelText: 'Amount (NULL)'),
        ),
        const SizedBox(height: 24),
        const FilledButton(onPressed: null, child: Text('Review payment')),
      ],
    );
  }
}
