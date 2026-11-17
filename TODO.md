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
- [x] Core on null-chain `v0.1.13`: create (24 words) and restore, wallet
      file sealed under a passphrase, unlock, recovery phrase shown again
      with the passphrase (2026-11-15)
- [x] Sync: compact blocks in server-sized ranges, reorg rollback with
      `getblockhashes`, a lagging server undoes nothing, pending payments
      resubmitted;
      compact block format 2, so a note spent by a block's own coinbase
      counts as spent (2026-11-17)
- [x] Balance (spendable, on its way), activity (received, sent, change
      hidden by default)
- [x] Send: exact fee quote, review, build and prove on the device, submit;
      a refusal frees the notes, a lost reply stays pending
- [x] Onboarding: phrase shown once, three random words asked back,
      passphrase of 8+ characters
- [x] Receive: newest address, QR code, copy, new address
- [x] Receive: an optional amount and message turn the QR code into a
      payment link (2026-11-17)
- [x] Auto-lock after a minute in the background; lock now; delete wallet
- [x] Auto-lock time in Settings: 1, 5 (default), 10 or 30 minutes in the background (2026-11-15)
- [x] Android: `FLAG_SECURE` on the whole app (no screenshots, recordings
      or recents preview)

## Next

- [x] Send: payment URIs (`docs/payment-uri.md`) typed, pasted or scanned
      from a QR code (Android, zxing-cpp on the device) (2026-11-17)
- [x] Payment links open the Send screen after unlocking: `null:` on
      Android, `#pay=` on the web wallet (2026-11-17)
- [x] A real payment end to end on mainnet (receive, then send) on the APK (2026-11-15)
- [ ] The same on the web wallet
- [x] Release workflow: a tag builds the signed APKs and the web archive, checks the signer, publishes them with SHA256SUMS (2026-11-15)
- [ ] Rebuild a payment whose anchor got too old before it was mined
- [ ] Wallet birthday: restore scans from genesis today
- [ ] Android Keystore for the passphrase-derived key, biometric unlock
- [ ] Light server list with failover
- [ ] Measure proving time on a mid-range phone; keep the proving key
      across launches

## Web wallet

- [x] null-chain `v0.1.12` builds for `wasm32-unknown-unknown`
      (single-threaded proving) and keeps a wallet in a byte image
- [x] The core runs in the browser (flutter_rust_bridge web, loaded from
      the page's own scripts so no `eval` is needed); the wallet image lives
      in IndexedDB (2026-11-15)
- [x] Strict CSP without `'unsafe-eval'`, COOP/COEP; no CDN or remote fonts
- [x] Release archive with its hash in `SHA256SUMS`
- [ ] Measure proving in WebAssembly (a send) on a phone browser
- [ ] Reproducible web build (pinned nightly), so anyone can rebuild the
      served archive and compare the hash

## Later

- [ ] Tor for sync and submission
- [ ] Watch-only import from a viewing key
- [ ] F-Droid (reproducible build)
