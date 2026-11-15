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

## Signing in CI

Tag builds sign with the release key from the repository's `release`
environment (secrets `ANDROID_KEYSTORE_B64`, `ANDROID_KEYSTORE_PASSWORD`),
which only tags `v*` can use. The workflow checks the APK's certificate
against the SHA-256 pinned in `.github/workflows/release.yml`:

```
f6:4e:cd:6d:0a:2a:55:28:35:0e:67:8f:a1:de:2d:01:b2:54:91:c4:8c:8c:60:9f:8b:b1:25:cb:68:0b:72:80
```

Users can check an APK they downloaded the same way:
`apksigner verify --print-certs null-wallet-X.Y.Z.apk`.

## Steps

1. Bump `version` in `pubspec.yaml` (`x.y.z+build`; the build number must
   grow for Android to accept the update).
2. `flutter test`, `(cd rust && cargo test)`.
3. Commit, push, and wait for CI on `main`.
4. Tag `vX.Y.Z` (the tag must equal the pubspec version) and push the tag.
   `.github/workflows/release.yml` tests, builds the signed APKs (universal
   and arm64), the web wallet archive and `SHA256SUMS`, and publishes the
   release.
5. Deploy the web archive of the same release to the web host.

Running the workflow by hand builds the same files as artifacts, signed with
the debug key, and publishes nothing.
