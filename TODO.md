# TODO

## Done

- [x] Flutter app for Android and the web, Material 3, black and white,
      light and dark (2026-11-14)
- [x] Rust core over flutter_rust_bridge, pinned to a null-chain tag:
      address checks, compact-block decoding
- [x] Light-server client: `getlightinfo` with network and genesis check,
      block hashes, compact blocks, submission, transaction status
- [x] Settings: light server (https only, http on loopback), connection test
- [x] Android: no cloud backup or device transfer of app data; release
      signing from a local `key.properties`
- [x] Core on null-chain `v0.1.12`: create (24 words) and restore, wallet
      file sealed under a passphrase, unlock, recovery phrase shown again
      with the passphrase (2026-11-15)
- [x] Sync: compact blocks in server-sized ranges, reorg rollback with
      `getblockhashes`, a lagging server undoes nothing, pending payments
      resubmitted
- [x] Balance (spendable, on its way), activity (received, sent, change
      hidden by default)
- [x] Send: exact fee quote, review, build and prove on the device, submit;
      a refusal frees the notes, a lost reply stays pending
- [x] Onboarding: phrase shown once, three random words asked back,
      passphrase of 8+ characters
- [x] Receive: newest address, QR code, copy, new address
- [x] Auto-lock after a minute in the background; lock now; delete wallet
- [x] Android: `FLAG_SECURE` on the whole app (no screenshots, recordings
      or recents preview)

## Next

- [ ] Send: scan a QR code, payment URIs
- [ ] Rust core test of a real payment end to end (fund, scan, send)
- [ ] Rebuild a payment whose anchor got too old before it was mined
- [ ] Wallet birthday: restore scans from genesis today
- [ ] Android Keystore for the passphrase-derived key, biometric unlock
- [ ] Light server list with failover
- [ ] Measure proving time on a mid-range phone; keep the proving key
      across launches

## Web wallet

- [x] null-chain `v0.1.12` builds for `wasm32-unknown-unknown`
      (single-threaded proving) and keeps a wallet in a byte image
- [x] The core builds for wasm32 (`getrandom` with `js`)
- [ ] Wire the core into the web build (flutter_rust_bridge web) and keep
      the image in IndexedDB
- [ ] Measure proving in WebAssembly
- [ ] Hosting: strict CSP, COOP/COEP, a reproducible build whose hash is
      published with each release

## Later

- [ ] Tor for sync and submission
- [ ] Watch-only import from a viewing key
- [ ] Payment URIs
- [ ] F-Droid (reproducible build)
