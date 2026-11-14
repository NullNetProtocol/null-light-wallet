import 'package:flutter/foundation.dart';

import '../rust/api/core.dart' as rust;
import '../rust/frb_generated.dart';

/// Result of checking an address typed on the Send screen.
class AddressValidity {
  const AddressValidity(this.valid, [this.reason]);

  final bool valid;
  final String? reason;
}

/// Everything the app needs from the Rust core. Key derivation, note
/// decryption, the witness tree and proving stay in the null-chain
/// crates; Dart only calls through this.
abstract class WalletCore {
  /// Whether the core runs on this platform yet.
  bool get available;

  /// The core's version, for Settings.
  String get version;

  /// Whether `address` is a main-network address.
  AddressValidity checkAddress(String address);
}

/// The Rust core over flutter_rust_bridge (Android).
class RustCore implements WalletCore {
  RustCore._();

  /// Loads the native library once.
  static Future<RustCore> load() async {
    await RustLib.init();
    return RustCore._();
  }

  @override
  bool get available => true;

  @override
  String get version => rust.coreVersion();

  @override
  AddressValidity checkAddress(String address) {
    final check = rust.checkAddress(address: address);
    return AddressValidity(check.valid, check.error);
  }
}

/// Stand-in where the core is not built yet: the browser, until the
/// null-chain crates compile to WebAssembly.
class UnavailableCore implements WalletCore {
  const UnavailableCore();

  @override
  bool get available => false;

  @override
  String get version => 'not available on this platform yet';

  @override
  AddressValidity checkAddress(String address) =>
      const AddressValidity(false, 'address checks need the wallet core');
}

/// The core for the platform the app runs on.
Future<WalletCore> loadCore() async =>
    kIsWeb ? const UnavailableCore() : await RustCore.load();
