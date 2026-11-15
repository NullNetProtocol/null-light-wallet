import 'package:flutter/material.dart';

import '../core/amount.dart';
import '../core/wallet_core.dart';
import '../wallet_model.dart';

/// Balance, sync status and activity.
class WalletPage extends StatefulWidget {
  const WalletPage({super.key, required this.model});

  final WalletModel model;

  @override
  State<WalletPage> createState() => _WalletPageState();
}

class _WalletPageState extends State<WalletPage> {
  bool _showChange = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final model = widget.model;
        final items = model.activity
            .where((i) => _showChange || i.kind != ActivityKind.change)
            .toList();
        return RefreshIndicator(
          onRefresh: model.sync,
          child: ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              _BalanceCard(balance: model.balance),
              _SyncLine(model: model),
              const Divider(height: 32),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Text(
                      'Activity',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Spacer(),
                    FilterChip(
                      label: const Text('Change'),
                      selected: _showChange,
                      onSelected: (on) => setState(() => _showChange = on),
                    ),
                  ],
                ),
              ),
              if (items.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No payments yet. Share your address from Receive to get '
                    'paid.',
                  ),
                )
              else
                for (final item in items) ActivityTile(item: item),
            ],
          ),
        );
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});

  final Balance? balance;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final b = balance;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Balance', style: text.labelLarge),
          const SizedBox(height: 4),
          Text(
            b == null ? '—' : '${formatAmount(b.total)} NULL',
            key: const Key('balance'),
            style: text.displaySmall,
          ),
          if (b != null && b.spendable != b.total) ...[
            const SizedBox(height: 4),
            Text(
              '${formatAmount(b.spendable)} spendable now'
              '${b.pending > BigInt.zero ? ' · ${formatAmount(b.pending)} in payments on their way' : ''}',
              style: text.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _SyncLine extends StatelessWidget {
  const _SyncLine({required this.model});

  final WalletModel model;

  @override
  Widget build(BuildContext context) {
    final tip = model.tip;
    final next = model.syncNext;
    final String text;
    double? progress;
    if (model.syncError != null && !model.syncing) {
      text = 'Sync failed: ${model.syncError}. Pull to retry.';
    } else if (model.syncing && tip != null && next != null) {
      text = 'Scanning block $next of $tip';
      progress = tip == 0 ? null : (next / tip).clamp(0, 1).toDouble();
    } else if (model.syncing) {
      text = 'Connecting to the light server…';
    } else if (model.upToDate) {
      text = 'Up to date at block $tip';
    } else {
      text = 'Not synced yet. Pull to sync.';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            style: model.syncError != null && !model.syncing
                ? TextStyle(color: Theme.of(context).colorScheme.error)
                : null,
          ),
          if (model.syncing) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(value: progress),
          ],
        ],
      ),
    );
  }
}

/// One activity row.
class ActivityTile extends StatelessWidget {
  const ActivityTile({super.key, required this.item});

  final ActivityItem item;

  @override
  Widget build(BuildContext context) {
    final sent = item.kind == ActivityKind.sent;
    final title = switch (item.kind) {
      ActivityKind.received => 'Received',
      ActivityKind.change => 'Change',
      ActivityKind.sent => switch (item.state) {
        SendState.pending => 'Sending',
        SendState.failed => 'Payment failed',
        _ => 'Sent',
      },
    };
    final details = [
      if (item.height != null) 'block ${item.height}',
      if (item.state == SendState.pending) 'waiting to be mined',
      if (item.address != null) _short(item.address!),
      if (item.memo != null) '“${item.memo}”',
      if (item.includesFee) 'network fee included',
      if (item.error != null) item.error!,
    ].join(' · ');
    final failed = item.state == SendState.failed;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
      leading: Icon(
        failed
            ? Icons.error_outline
            : sent
            ? Icons.call_made
            : Icons.call_received,
        color: failed ? Theme.of(context).colorScheme.error : null,
      ),
      title: Text(title),
      subtitle: details.isEmpty ? null : Text(details),
      trailing: Text(
        '${sent ? '−' : '+'}${formatAmount(item.amount)}',
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(decoration: failed ? TextDecoration.lineThrough : null),
      ),
    );
  }

  static String _short(String address) => address.length <= 20
      ? address
      : '${address.substring(0, 12)}…${address.substring(address.length - 6)}';
}
