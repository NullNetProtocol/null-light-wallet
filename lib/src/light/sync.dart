import 'dart:math' as math;

import '../core/wallet_core.dart';
import 'light_client.dart';
import 'network.dart';

/// How far a sync got: `scanned` of `tip`.
typedef SyncProgress = void Function(int next, int tip);

/// What one [syncWallet] run did.
class SyncOutcome {
  const SyncOutcome({
    required this.tip,
    required this.blocks,
    required this.found,
    required this.rolledBack,
  });

  /// The server's tip height.
  final int tip;

  /// Blocks scanned.
  final int blocks;

  /// Notes found for the wallet.
  final int found;

  /// Blocks undone because the server's chain moved to another branch.
  final int rolledBack;
}

/// Brings `wallet` up to the server's tip: checks the server is on the
/// main network, undoes blocks the server no longer has on its main
/// chain, scans the rest in ranges, saves after each range, then submits
/// again any payment still waiting to be mined.
///
/// Only heights and raw transactions go to the server.
Future<SyncOutcome> syncWallet(
  LightClient client,
  WalletHandle wallet, {
  NullNetwork network = NullNetwork.main,
  SyncProgress? onProgress,
}) async {
  final info = await client.infoOn(network);
  final rolledBack = await _undoReorg(client, wallet, info);
  var blocks = 0;
  var found = 0;
  var next = wallet.nextHeight();
  onProgress?.call(next, info.height);
  while (next <= info.height) {
    final count = math.min(info.maxRange, info.height - next + 1);
    final range = await client.compactBlocks(next, count);
    if (range.isEmpty) break;
    final step = await wallet.applyBlocks(range);
    await wallet.save();
    blocks += step.blocks;
    found += step.found;
    next = step.nextHeight;
    onProgress?.call(next, info.height);
  }
  await _resubmit(client, wallet);
  return SyncOutcome(
    tip: info.height,
    blocks: blocks,
    found: found,
    rolledBack: rolledBack,
  );
}

/// Rolls the wallet back to the last height whose hash matches the
/// server's main chain, if the newest one does not. Returns the number
/// of blocks undone.
Future<int> _undoReorg(
  LightClient client,
  WalletHandle wallet,
  LightInfo info,
) async {
  final next = wallet.nextHeight();
  if (next == 0) return 0;
  final newest = next - 1;
  // A server behind the wallet is compared at its own tip: a match there
  // means it lags, and the blocks above stay until it catches up.
  final top = math.min(newest, info.height);
  var height = top;
  while (height >= 0) {
    final start = math.max(0, height - info.maxRange + 1);
    final theirs = await client.blockHashes(start, height - start + 1);
    for (var h = height; h >= start; h--) {
      final index = h - start;
      if (index < theirs.length && wallet.scannedHash(h) == theirs[index]) {
        if (h == top) return 0;
        await wallet.rollbackTo(h);
        await wallet.save();
        return newest - h;
      }
    }
    height = start - 1;
  }
  throw const LightException('the server shares no blocks with this wallet');
}

/// Hands pending payments to the server again. A server that already has
/// one, or mined it, refuses it; that is fine, the next scan settles it.
Future<void> _resubmit(LightClient client, WalletHandle wallet) async {
  for (final transaction in wallet.pendingTransactions()) {
    try {
      await client.submit(transaction);
    } on LightException {
      // Already known or mined; or the server is down. Retry next sync.
    }
  }
}
