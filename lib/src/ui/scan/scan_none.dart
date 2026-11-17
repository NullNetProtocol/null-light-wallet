import 'package:flutter/widgets.dart';

/// Whether this build can scan a QR code.
bool get canScanQr => false;

/// Never called where [canScanQr] is false.
Future<String?> scanQr(BuildContext context) async => null;
