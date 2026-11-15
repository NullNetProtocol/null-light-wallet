import 'package:flutter/material.dart';

import '../app.dart';
import '../light/light_client.dart';
import '../light/network.dart';
import '../settings.dart';
import '../wallet_model.dart';
import 'onboarding/create_flow.dart' show PhraseGrid;
import 'unlock_page.dart' show confirmDelete;
import 'widgets.dart';

/// The light server, the recovery phrase, lock and delete, versions.
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.model,
    required this.lightClient,
  });

  final WalletModel model;
  final LightClientFactory lightClient;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  AppSettings get _settings => widget.model.settings;
  late final _server = TextEditingController(text: _settings.server);
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
    if (error != null) return;
    await _settings.setServer(_server.text);
    if (mounted) showMessage(context, 'Server saved');
    await widget.model.sync();
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });
    final client = widget.lightClient(_settings.serverUri);
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

  Future<void> _showPhrase() async {
    final words = await showDialog<String>(
      context: context,
      builder: (_) => _RevealDialog(model: widget.model),
    );
    if (words == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => Scaffold(
          appBar: AppBar(title: const Text('Recovery phrase')),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Notice(
                  'Anyone who sees these words can take your coins. Make sure '
                  'no one is watching your screen.',
                  icon: Icons.warning_amber,
                ),
                const SizedBox(height: 24),
                PhraseGrid(words: words.split(' ')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _delete() async {
    if (await confirmDelete(context)) await widget.model.delete();
  }

  @override
  Widget build(BuildContext context) {
    final title = Theme.of(context).textTheme.titleMedium;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Light server', style: title),
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
        Text('Wallet', style: title),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.key_outlined),
          title: const Text('Show recovery phrase'),
          subtitle: const Text('Asks for your passphrase'),
          onTap: _showPhrase,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.lock_outline),
          title: const Text('Lock now'),
          subtitle: Text(
            'Also locks after ${widget.model.lockAfter.inMinutes} minute'
            '${widget.model.lockAfter.inMinutes == 1 ? '' : 's'} in the '
            'background',
          ),
          onTap: widget.model.lock,
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.delete_outline,
            color: Theme.of(context).colorScheme.error,
          ),
          title: const Text('Delete wallet from this device'),
          onTap: _delete,
        ),
        const Divider(height: 48),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Wallet core'),
          subtitle: Text(widget.model.core.version),
        ),
      ],
    );
  }
}

class _RevealDialog extends StatefulWidget {
  const _RevealDialog({required this.model});

  final WalletModel model;

  @override
  State<_RevealDialog> createState() => _RevealDialogState();
}

class _RevealDialogState extends State<_RevealDialog> {
  final _passphrase = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _passphrase.dispose();
    super.dispose();
  }

  Future<void> _reveal() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final words = await widget.model.revealPhrase(_passphrase.text);
      if (mounted) Navigator.pop(context, words);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter your passphrase'),
      content: PassphraseField(
        controller: _passphrase,
        errorText: _error,
        autofocus: true,
        onSubmitted: (_) => _reveal(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        BusyButton(label: 'Show', busy: _busy, onPressed: _reveal),
      ],
    );
  }
}
