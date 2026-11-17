import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/payment_uri.dart';
import '../wallet_model.dart';
import 'widgets.dart';

/// What the Receive screen shows for `address` with the optional request
/// fields: the bare address, or a payment URI once an amount or a
/// message is set. The errors say why a field was left out.
({String data, String? amountError, String? messageError}) receiveData(
  String address,
  String amountText,
  String message,
) {
  final amountTrimmed = amountText.trim();
  final amount = amountTrimmed.isEmpty ? null : parseUriAmount(amountTrimmed);
  final error = amountTrimmed.isNotEmpty && amount == null
      ? 'Enter an amount, like 1.5'
      : null;
  final trimmed = message.trim();
  // The parser counts code points; the text field counts what it shows.
  final tooLong = trimmed.runes.length > maxPaymentMessageChars;
  final note = tooLong ? '' : trimmed;
  final messageError = tooLong ? 'The message is too long' : null;
  if (amount == null && note.isEmpty) {
    return (data: address, amountError: error, messageError: messageError);
  }
  return (
    data: formatPaymentUri(
      PaymentRequest(
        address,
        amount: amount,
        message: note.isEmpty ? null : note,
      ),
    ),
    amountError: error,
    messageError: messageError,
  );
}

/// The newest receiving address as a QR code, with copy and "new address".
/// An amount or a message turns the code into a payment request.
class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key, required this.model});

  final WalletModel model;

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> {
  final _amount = TextEditingController();
  final _message = TextEditingController();

  @override
  void dispose() {
    _amount.dispose();
    _message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    return ListenableBuilder(
      listenable: Listenable.merge([model, _amount, _message]),
      builder: (context, _) {
        final address = model.address;
        if (address == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final shown = receiveData(address, _amount.text, _message.text);
        final isRequest = shown.data != address;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: QrImageView(
                  data: shown.data,
                  size: 240,
                  backgroundColor: Colors.white,
                  semanticsLabel: isRequest
                      ? 'QR code of your payment request'
                      : 'QR code of your address',
                ),
              ),
            ),
            const SizedBox(height: 24),
            SelectableText(
              shown.data,
              key: const Key('address'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: Text(isRequest ? 'Copy payment link' : 'Copy address'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: shown.data));
                if (context.mounted) {
                  showMessage(
                    context,
                    isRequest ? 'Payment link copied' : 'Address copied',
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('New address'),
              onPressed: () async {
                try {
                  await model.newAddress();
                } catch (e) {
                  if (context.mounted) showMessage(context, describeError(e));
                }
              },
            ),
            const SizedBox(height: 24),
            Text(
              'Request an amount (optional)',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount',
                suffixText: 'NULL',
                errorText: shown.amountError,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _message,
              maxLength: maxPaymentMessageChars,
              decoration: InputDecoration(
                labelText: 'Message for the payer',
                helperText: 'Part of the link, not of the payment.',
                errorText: shown.messageError,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Every address of this wallet receives to the same balance. A '
              'new one for each payer keeps them from linking their payments.',
            ),
          ],
        );
      },
    );
  }
}
