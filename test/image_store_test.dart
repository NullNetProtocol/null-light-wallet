import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:null_light_wallet/src/core/image_store.dart';
import 'package:null_light_wallet/src/core/wallet_core.dart';

import 'fakes.dart';

/// An image kept in memory, counting writes.
class MemoryBackend implements ImageBackend {
  Uint8List? image;
  int writes = 0;

  @override
  Future<Uint8List?> read() async => image;

  @override
  Future<void> write(Uint8List image) async {
    this.image = image;
    writes++;
  }

  @override
  Future<void> delete() async => image = null;
}

/// A wallet whose image is its passphrase, saved through the backend.
class ImageWallet extends FakeWallet {
  ImageWallet(this.backend, String passphrase)
    : super(words: 'w', passphrase: passphrase);

  final ImageBackend backend;

  @override
  Future<void> save() async {
    await super.save();
    await backend.write(Uint8List.fromList(passphrase.codeUnits));
  }
}

void main() {
  late MemoryBackend backend;
  late ImageStore store;

  setUp(() {
    backend = MemoryBackend();
    store = ImageStore(
      backend,
      createImage: (words, passphrase, b) async => ImageWallet(b, passphrase),
      openImage: (image, passphrase, b) async {
        if (String.fromCharCodes(image) != passphrase) {
          throw ArgumentError('wrong passphrase');
        }
        return ImageWallet(b, passphrase);
      },
    );
  });

  test('a new wallet is saved at once and opens again', () async {
    expect(await store.exists(), isFalse);
    await expectLater(store.open('pass'), throwsStateError);
    final WalletHandle wallet = await store.create('words', 'pass');
    expect(backend.writes, 1, reason: 'saved before any sync');
    expect(await store.exists(), isTrue);
    wallet.close();
    await expectLater(store.open('nope'), throwsArgumentError);
    expect(await store.open('pass'), isA<ImageWallet>());
  });

  test('one wallet per browser, and delete forgets it', () async {
    await store.create('words', 'pass');
    await expectLater(store.create('words', 'other'), throwsStateError);
    await store.delete();
    expect(await store.exists(), isFalse);
    await store.create('words', 'other');
    expect(await store.exists(), isTrue);
  });
}
