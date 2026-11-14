import 'package:flutter/material.dart';

import '../app.dart';
import '../core/wallet_core.dart';
import '../light/light_client.dart';
import '../light/network.dart';
import '../settings.dart';

/// The light server, a connection test, and versions.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.core,
    required this.settings,
    required this.lightClient,
  });

  final WalletCore core;
  final AppSettings settings;
  final LightClientFactory lightClient;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late final _server = TextEditingController(text: widget.settings.server);
  String? _serverError;
  String? _status;
  bool _testing = false;

  @override
  void dispose() {
    _server.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = validateServer(_server.text);
    setState(() => _serverError = error);
    if (error == null) await widget.settings.setServer(_server.text);
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });
    final client = widget.lightClient(widget.settings.serverUri);
    String status;
    try {
      final info = await client.infoOn(NullNetwork.main);
      status = info.syncing
          ? 'Connected. The server is still syncing (height ${info.height}).'
          : 'Connected to the main network at height ${info.height}.';
    } on LightException catch (e) {
      status = 'Could not use this server: ${e.message}';
    } finally {
      client.close();
    }
    if (mounted) {
      setState(() {
        _testing = false;
        _status = status;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Light server', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        TextField(
          controller: _server,
          keyboardType: TextInputType.url,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Server URL',
            errorText: _serverError,
            helperText:
                'Any NULL node started with --light-listen. It sees your IP '
                'address, never which payments are yours.',
            helperMaxLines: 3,
          ),
          onSubmitted: (_) => _save(),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(onPressed: _save, child: const Text('Save')),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: _testing ? null : _test,
              child: Text(_testing ? 'Testing…' : 'Test connection'),
            ),
          ],
        ),
        if (_status != null) ...[const SizedBox(height: 12), Text(_status!)],
        const Divider(height: 48),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Wallet core'),
          subtitle: Text(widget.core.version),
        ),
      ],
    );
  }
}
