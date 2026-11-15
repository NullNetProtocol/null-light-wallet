import 'package:flutter/material.dart';

import '../../wallet_model.dart';
import 'passphrase_step.dart';

/// Restore: type the 24 words, then choose a passphrase. The wallet then
/// scans the chain from the start to find its payments.
class RestorePage extends StatefulWidget {
  const RestorePage({super.key, required this.model});

  final WalletModel model;

  @override
  State<RestorePage> createState() => _RestorePageState();
}

class _RestorePageState extends State<RestorePage> {
  final _phrase = TextEditingController();
  String? _error;
  String? _words;

  @override
  void dispose() {
    _phrase.dispose();
    super.dispose();
  }

  void _next() {
    final words = _phrase.text.trim().split(RegExp(r'\s+')).join(' ');
    final error = widget.model.core.checkPhrase(words);
    setState(() {
      _error = error;
      if (error == null) _words = words.toLowerCase();
    });
  }

  Future<void> _create(String passphrase) async {
    await widget.model.create(_words!, passphrase);
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final words = _words;
    return Scaffold(
      appBar: AppBar(title: const Text('Restore wallet')),
      body: SafeArea(
        child: words != null
            ? PassphraseStep(onCreate: _create, action: 'Restore wallet')
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const Text(
                    'Enter your 24-word recovery phrase, in order, separated '
                    'by spaces. The same phrase works in the desktop wallet.',
                  ),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _phrase,
                    minLines: 4,
                    maxLines: 6,
                    autocorrect: false,
                    enableSuggestions: false,
                    enableIMEPersonalizedLearning: false,
                    keyboardType: TextInputType.visiblePassword,
                    decoration: InputDecoration(
                      labelText: 'Recovery phrase',
                      errorText: _error,
                      errorMaxLines: 3,
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(onPressed: _next, child: const Text('Continue')),
                ],
              ),
      ),
    );
  }
}
