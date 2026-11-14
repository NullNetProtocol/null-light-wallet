# Releasing

There are no app-store releases. Each release publishes, on this
repository's GitHub releases page:

- `null-wallet-<version>.apk`, signed with the release key
- `null-wallet-web-<version>.tar.gz`, the web build
- `SHA256SUMS` for both

## Android signing

Release APKs are signed with one long-lived key. Android only installs an
update signed with the same key as the installed app, so **losing the key
means every user has to uninstall (after backing up their recovery phrase)
and install again.** Keep the keystore offline, with a backup.

`android/key.properties` points the build at the keystore. It and every
`*.jks`/`*.keystore` are ignored by git and must never be committed:

```
storeFile=/absolute/path/to/release.jks
storePassword=...
keyAlias=nullwallet
keyPassword=...
```

Without `key.properties`, release builds are signed with the debug key and
must not be published.

## Steps

1. Bump `version` in `pubspec.yaml` (`x.y.z+build`; the build number must
   grow for Android to accept the update).
2. `flutter test`, `(cd rust && cargo test)`.
3. `flutter build apk --release` and `flutter build web --release`.
4. Check the APK's signer:
   `apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk`.
5. Write `SHA256SUMS`, tag `vX.Y.Z`, publish the release with the files.
