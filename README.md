# NULL Wallet (light)

A light wallet for [NULL](https://nullnet.sh), the shielded-only
cryptocurrency: an Android app (APK) and a web wallet, from one Flutter
codebase with a Rust core.

**Status: scaffold.** The app runs, checks addresses and talks to light
servers, but cannot create or restore a wallet yet. Do not use it for
funds. See [TODO.md](TODO.md).

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

The web build does not include the Rust core yet: the null-chain crates
need a build without multi-threaded proving to compile to WebAssembly.
Until then the web wallet can talk to light servers but holds no keys.

Releases are described in [docs/release.md](docs/release.md).

## License

MIT or Apache-2.0, at your option.
