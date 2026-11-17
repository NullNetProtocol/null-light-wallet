import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_zxing/flutter_zxing.dart';

/// Whether this build can scan a QR code: Android, through zxing-cpp on
/// the device. Nothing leaves the phone and Google Play services are not
/// needed.
bool get canScanQr => Platform.isAndroid;

/// Opens the camera and returns the text of the first QR code it reads,
/// or `null` if the user went back. Android asks for the camera
/// permission the first time.
Future<String?> scanQr(BuildContext context) =>
    Navigator.of(context)
        .push<String>(MaterialPageRoute(builder: (_) => const _ScanPage()));

class _ScanPage extends StatefulWidget {
  const _ScanPage();

  @override
  State<_ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<_ScanPage> {
  bool _done = false;

  void _onScan(Code code) {
    final text = code.text;
    if (_done || !code.isValid || text == null || text.isEmpty) return;
    _done = true;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan a QR code')),
    body: ReaderWidget(
      onScan: _onScan,
      codeFormat: Format.qrCode,
      showGallery: false,
      showToggleCamera: false,
      scanDelay: const Duration(milliseconds: 300),
      resolution: ResolutionPreset.medium,
    ),
  );
}
