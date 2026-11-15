import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../rust/api/wallet.dart' as rw;
import '../wallet_core.dart';

/// Android: a wallet file in the app's private directory, which Android
/// keeps out of backups (`data_extraction_rules.xml`).
Future<WalletStore> platformStore() async {
  final dir = await getApplicationSupportDirectory();
  return FileStore('${dir.path}/wallet.redb');
}

/// The wallet as a file.
class FileStore implements WalletStore {
  FileStore(this.path);

  final String path;

  @override
  Future<bool> exists() => File(path).exists();

  @override
  Future<WalletHandle> create(String words, String passphrase) async =>
      RustHandle(
        await rw.LightWallet.createFile(
          path: path,
          words: words,
          passphrase: passphrase,
        ),
      );

  @override
  Future<WalletHandle> open(String passphrase) async => RustHandle(
    await rw.LightWallet.openFile(path: path, passphrase: passphrase),
  );

  @override
  Future<void> delete() async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
