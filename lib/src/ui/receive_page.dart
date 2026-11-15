import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../wallet_model.dart';
import 'widgets.dart';

/// The newest receiving address as a QR code, with copy and "new address".
class ReceivePage extends StatelessWidget {
  const ReceivePage({super.key, required this.model});

  final WalletModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final address = model.address;
        if (address == null) {
          return const Center(child: CircularProgressIndicator());
        }
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Center(
              child: Container(
                padding: const EdgeInsets.all(16),
                color: Colors.white,
                child: QrImageView(
                  data: address,
                  size: 240,
                  backgroundColor: Colors.white,
                  semanticsLabel: 'QR code of your address',
                ),
              ),
            ),
            const SizedBox(height: 24),
            SelectableText(
              address,
              key: const Key('address'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.copy),
              label: const Text('Copy address'),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: address));
                if (context.mounted) showMessage(context, 'Address copied');
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
