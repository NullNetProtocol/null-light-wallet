import 'dart:js_interop';

import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:web/web.dart' as web;

import '../payment_uri.dart';

/// Keeps Flutter's router off the address bar: the wallet has no pages
/// to link to, and its hash strategy would read `#pay=` as a route.
void preparePaymentLinks() => setUrlStrategy(null);

/// Calls `onLink` with the payment URI in `#pay=` on start and whenever
/// the fragment changes, then clears the fragment so the request does
/// not stay in the address bar or the history entry.
void listenForPaymentLinks(void Function(String link) onLink) {
  void read() {
    final location = web.window.location;
    final hash = location.hash;
    if (hash.isEmpty) return;
    final link = paymentUriFromFragment(hash.substring(1));
    if (link == null) return;
    web.window.history.replaceState(
      null,
      '',
      '${location.pathname}${location.search}',
    );
    onLink(link);
  }

  read();
  web.window.addEventListener('hashchange', ((web.Event _) => read()).toJS);
}
