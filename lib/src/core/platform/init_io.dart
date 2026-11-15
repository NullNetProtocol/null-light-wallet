import '../../rust/frb_generated.dart';

/// Loads the native core library.
Future<void> initCore() => RustLib.init();
