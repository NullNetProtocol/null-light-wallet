# NULL Wallet (light)

A light wallet for [NULL](https://nullnet.sh), the shielded-only
cryptocurrency: an Android app (APK) and a web wallet, from one Flutter
codebase with a Rust core.

**Status: early.** The Android app and the web wallet create and restore
wallets, sync from a light server, receive and send. Neither has had an
independent review yet: do not trust it with more than you can lose. See
[TODO.md](TODO.md).

- Android: the signed APK from the [releases](../../releases) (check its
  certificate, see [docs/release.md](docs/release.md)).
- Web: https://wallet.nullnet.sh, the web archive of the same release.

## How it works

- **Light sync.** The wallet downloads *compact blocks* from a light server
  (any `nulld` started with `--light-listen`, see `docs/rpc.md` Phase 5 in
  [null-chain](https://github.com/NullNetProtocol/null-chain)) and finds its
  own notes by trial decryption on the device. The server only ever sees
  block heights, raw transactions and transaction ids: it learns your IP
  address and when you send, never which payments are yours.
- **Rust core.** Keys, note decryption, the witness tree and proving come
  from the null-chain crates, pinned to a release tag, through
  [flutter_rust_bridge](https://github.com/fzyzcjy/flutter_rust_bridge).
  Nothing cryptographic is reimplemented in Dart.
- **Self-custody.** Keys never leave the device. No account, no analytics,
  no cloud backup: the 24-word recovery phrase is the backup.
- **Payment links.** `null:<address>?amount=…&message=…`
  ([docs/payment-uri.md](docs/payment-uri.md)), from a QR code (scanned on
  the device on Android), a pasted text, a tapped link on Android or
  `https://wallet.nullnet.sh/#pay=…`. A link only fills the Send screen;
  you review and confirm every payment.

## Layout

```
lib/                 Flutter app (Material 3)
  src/light/         light-server client (JSON-RPC over HTTPS)
  src/core/          WalletCore: the only way Dart reaches the Rust core
  src/rust/          generated bindings (do not edit)
  src/ui/            screens
rust/                null_light_core: Rust core over the null-chain crates
rust_builder/        cargokit glue that builds the core into the APK
android/  web/       platform shells
```

## Build

Requirements: Flutter (stable), Rust (stable) with the Android targets,
the Android SDK and NDK.

```
rustup target add aarch64-linux-android armv7-linux-androideabi x86_64-linux-android i686-linux-android
flutter test                      # Dart tests
(cd rust && cargo test)           # Rust core tests
flutter build apk --release       # Android
flutter build web --release       # web wallet
```

After changing `rust/src/api`, regenerate the bindings with
`flutter_rust_bridge_codegen generate`.

The web wallet runs the same Rust core as WebAssembly and keeps the
wallet, sealed under its passphrase, in the browser's IndexedDB. Building it
needs nightly Rust with `rust-src`, `wasm-pack` and
`flutter_rust_bridge_codegen` 2.13.0:

```
scripts/build-web.sh              # core to web/pkg, then build/web
```

It must be served with cross-origin isolation (COOP `same-origin`, COEP
`require-corp`) and works under a strict Content-Security-Policy with no
`'unsafe-eval'` (`script-src 'self' 'wasm-unsafe-eval' blob:`). Every
resource is self-hosted: no CDN, no web fonts from elsewhere.

Releases are described in [docs/release.md](docs/release.md).

## License

MIT or Apache-2.0, at your option.
