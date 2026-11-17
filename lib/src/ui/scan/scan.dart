// The QR scanner where there is one: Android only. The web build has no
// camera access (its Permissions-Policy and CSP stay as they are).
export 'scan_none.dart' if (dart.library.io) 'scan_android.dart';
