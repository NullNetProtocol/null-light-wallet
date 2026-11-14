import 'package:flutter/material.dart';

/// The newest address with a QR code, once a wallet exists.
class ReceivePage extends StatelessWidget {
  const ReceivePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'Your receiving address appears here once you have a wallet.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
