# TODO

## Done

- [x] Flutter app for Android and the web, Material 3, black and white,
      light and dark (2026-11-14)
- [x] Rust core over flutter_rust_bridge, pinned to null-chain `v0.1.11`:
      address checks, compact-block decoding
- [x] Light-server client: `getlightinfo` with network and genesis check,
      block hashes, compact blocks, submission, transaction status
- [x] Settings: light server (https only, http on loopback), connection test
- [x] Android: no cloud backup or device transfer of app data; release
      signing from a local `key.properties`

## Next

- [ ] Core: create (24 words) and restore, encrypted wallet file, unlock
- [ ] Core: sync step (fetch compact blocks, `scan_compact`), reorg rollback
      with `getblockhashes`, balance and activity
- [ ] Core: build and prove a payment, submit, track status
- [ ] Onboarding: show the phrase once, confirm three random words
- [ ] Receive: newest address, QR code, copy and share
- [ ] Send: QR scan, amount with 8 decimals, memo, review with exact fee
- [ ] Android Keystore for the wallet key, biometrics, auto-lock,
      `FLAG_SECURE` on phrase and send screens
- [ ] Light server list with failover
- [ ] Measure proving time on a mid-range phone; cache the proving key

## Web wallet

- [ ] null-chain: a build of the crates without multi-threaded proving
      (Halo2's `multicore`), so they compile to `wasm32-unknown-unknown`
- [ ] A browser storage backend for the wallet (the core stores in a file)
- [ ] Measure proving in WebAssembly, single and multi-threaded
- [ ] Hosting: strict CSP, COOP/COEP, a reproducible build whose hash is
      published with each release

## Later

- [ ] Tor for sync and submission
- [ ] Watch-only import from a viewing key
- [ ] Payment URIs
- [ ] F-Droid (reproducible build)
