/// The NULL networks a wallet can sync, identified by their genesis
/// block so a server on another chain is refused before any scanning.
enum NullNetwork {
  /// The main network, live since 2026-10-15.
  main(
    name: 'main',
    genesis: 'a47d659978361de625cfb4d84641b4f2de6f69ef04338e52612e5f8d95853c92',
    addressPrefix: 'null',
  );

  const NullNetwork({
    required this.name,
    required this.genesis,
    required this.addressPrefix,
  });

  /// The name light servers report in `getlightinfo`.
  final String name;

  /// The genesis block hash, lowercase hex.
  final String genesis;

  /// The bech32m human-readable part of addresses.
  final String addressPrefix;
}

/// Light servers the app knows about. A user can add their own: any
/// `nulld run --light-listen` node works.
const defaultServers = <String>['https://light.nullnet.sh'];
