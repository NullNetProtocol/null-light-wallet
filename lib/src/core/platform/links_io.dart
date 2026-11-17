import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// The channel `MainActivity` hands `null:` links over on.
const _channel = MethodChannel('sh.nullnet.lightwallet/links');

/// Nothing to prepare outside the web.
void preparePaymentLinks() {}

/// Calls `onLink` with each `null:` link Android opens the app with: the
/// one that started it, then any that arrive while it runs.
void listenForPaymentLinks(void Function(String link) onLink) {
  if (!Platform.isAndroid) return;
  _channel.setMethodCallHandler((call) async {
    final link = call.arguments;
    if (call.method == 'link' && link is String) onLink(link);
  });
  _channel.invokeMethod<String>('initialLink').then((link) {
    if (link != null) onLink(link);
  }, onError: (Object _) {});
}
