import 'dart:js_interop';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated_web.dart'
    show ExternalLibrary;

import '../../rust/frb_generated.dart';

@JS('wasm_bindgen')
external JSFunction? get _wasmBindgen;

/// Starts the core that index.html loaded as plain scripts, then hands it
/// to the bridge. The bridge's own loader would inject the script and run
/// a string as code, which a strict Content-Security-Policy forbids.
Future<void> initCore() async {
  final start = _wasmBindgen;
  if (start == null) throw StateError('the wallet core script is missing');
  await (start.callAsFunction(
    null,
    'pkg/null_light_core_bg.wasm'.toJS,
  ) as JSPromise).toDart;
  await RustLib.init(
    // Only compiled for the web, where this is the bridge's web type; the
    // analyzer checks the file against the native one.
    // ignore: argument_type_not_assignable
    externalLibrary: const ExternalLibrary(debugInfo: 'index.html scripts'),
  );
}
