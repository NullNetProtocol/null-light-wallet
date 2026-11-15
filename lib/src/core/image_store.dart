import 'dart:typed_data';

import '../rust/api/wallet.dart' as rw;
import 'wallet_core.dart';

/// Where a byte-image wallet is kept: IndexedDB in the browser, memory in
/// tests.
abstract class ImageBackend {
  /// The saved image, or `null` if there is none.
  Future<Uint8List?> read();

  /// Replaces the saved image.
  Future<void> write(Uint8List image);

  /// Forgets the image.
  Future<void> delete();
}

/// The wallet as a byte image (the browser has no files). The image holds
/// the same sealed records as a wallet file: keys, phrase and notes under
/// the passphrase. It is saved after every change ([WalletHandle.save]).
class ImageStore implements WalletStore {
  ImageStore(this.backend, {this.createImage, this.openImage});

  final ImageBackend backend;

  /// Overrides for tests; the Rust core otherwise.
  final Future<WalletHandle> Function(
    String words,
    String passphrase,
    ImageBackend backend,
  )?
  createImage;
  final Future<WalletHandle> Function(
    Uint8List image,
    String passphrase,
    ImageBackend backend,
  )?
  openImage;

  @override
  Future<bool> exists() async => await backend.read() != null;

  @override
  Future<WalletHandle> create(String words, String passphrase) async {
    if (await exists()) throw StateError('a wallet already exists here');
    final wallet = await (createImage ?? _rustCreate)(
      words,
      passphrase,
      backend,
    );
    await wallet.save();
    return wallet;
  }

  @override
  Future<WalletHandle> open(String passphrase) async {
    final image = await backend.read();
    if (image == null) throw StateError('no wallet in this browser');
    return (openImage ?? _rustOpen)(image, passphrase, backend);
  }

  @override
  Future<void> delete() => backend.delete();

  static Future<WalletHandle> _rustCreate(
    String words,
    String passphrase,
    ImageBackend backend,
  ) async => RustHandle(
    await rw.LightWallet.createImage(words: words, passphrase: passphrase),
    onSave: backend.write,
  );

  static Future<WalletHandle> _rustOpen(
    Uint8List image,
    String passphrase,
    ImageBackend backend,
  ) async => RustHandle(
    await rw.LightWallet.openImage(image: image, passphrase: passphrase),
    onSave: backend.write,
  );
}
