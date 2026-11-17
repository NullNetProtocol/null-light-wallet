// Where payment links come from: Android intents, or the web wallet's
// `#pay=` fragment.
export 'platform/links_io.dart'
    if (dart.library.js_interop) 'platform/links_web.dart';
