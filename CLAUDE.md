# CLAUDE.md

Guidance for working on this repository.

## What this is

The NULL light wallet: an Android APK and a web wallet from one Flutter
codebase (`lib/`) with a Rust core (`rust/`) over the null-chain crates.
`TODO.md` is the roadmap.

## Rules

1. **No cryptography in Dart.** Keys, seed phrases, note decryption, the
   witness tree, proving and address encoding live in the null-chain
   crates. Dart reaches them only through `WalletCore`
   (`lib/src/core/wallet_core.dart`).
2. **Pin null-chain to a release tag** in `rust/Cargo.toml`, never a branch.
3. **The light server learns nothing about our notes.** Only heights, raw
   transactions and txids go to it. Never add a call that sends an
   address, a viewing key or a nullifier.
4. **No secrets in logs,** errors or analytics (there are no analytics).
   Phrases, keys, addresses and amounts never reach `print` or a crash
   report.
5. **Material 3, black and white** (`lib/src/theme.dart`). Brand logos
   only in their black or white variants.
6. **Generated code is not edited:** `lib/src/rust/` and
   `rust/src/frb_generated.rs` come from `flutter_rust_bridge_codegen
   generate`.
7. Every piece of logic gets a test: Dart in `test/`, Rust in a
   `#[cfg(test)] mod tests` at the bottom of the file.

## Commands

```
flutter analyze && flutter test
dart format lib test
(cd rust && cargo fmt && cargo clippy --all-targets -- -D warnings && cargo test)
flutter_rust_bridge_codegen generate   # after changing rust/src/api
flutter build apk --release
scripts/build-web.sh                   # web: core to web/pkg, then build/web
```
