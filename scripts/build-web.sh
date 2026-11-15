#!/usr/bin/env sh
# Builds the web wallet: the Rust core as WebAssembly (web/pkg, through
# flutter_rust_bridge and wasm-pack on nightly Rust, which the bridge's
# threaded worker pool needs), then the Flutter app with every resource
# self-hosted (no CanvasKit or fonts from a CDN). Output: build/web.
#
# Needs: Flutter, rustup with the nightly toolchain and its rust-src
# component, wasm-pack, flutter_rust_bridge_codegen 2.13.0.
set -eu
cd "$(dirname "$0")/.."
flutter_rust_bridge_codegen build-web --release
flutter build web --release --no-web-resources-cdn
