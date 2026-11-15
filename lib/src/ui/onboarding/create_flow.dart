import 'dart:math';

import 'package:flutter/material.dart';

import '../../wallet_model.dart';
import 'passphrase_step.dart';

/// Words asked back before the wallet is created.
const confirmCount = 3;

/// `count` distinct word positions to ask back, in order.
List<int> pickChallenge(Random random, int words, int count) {
  final positions = List<int>.generate(words, (i) => i)..shuffle(random);
  return positions.take(count).toList()..sort();
}

/// Create: show the new phrase, ask three of its words back, choose a
/// passphrase. The phrase is shown here once; Settings can show it again
/// after the passphrase is entered.
class CreateFlow extends StatefulWidget {
  const CreateFlow({super.key, required this.model, this.random});

  final WalletModel model;

  /// Picks the words to confirm; tests pass a seeded one.
  final Random? random;

  @override
  State<CreateFlow> createState() => _CreateFlowState();
}

class _CreateFlowState extends State<CreateFlow> {
  late final String _phrase = widget.model.core.generatePhrase();
  late final List<String> _words = _phrase.split(' ');
  late final List<int> _challenge = pickChallenge(
    widget.random ?? Random.secure(),
    _words.length,
    confirmCount,
  );
  int _step = 0;

  Future<void> _create(String passphrase) async {
    await widget.model.create(_phrase, passphrase);
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('New wallet · step ${_step + 1} of 3')),
      body: SafeArea(
        child: switch (_step) {
          0 => _ShowPhrase(
            words: _words,
            onDone: () => setState(() => _step = 1),
          ),
          1 => _ConfirmPhrase(
            words: _words,
            challenge: _challenge,
            onBack: () => setState(() => _step = 0),
            onDone: () => setState(() => _step = 2),
          ),
          _ => PassphraseStep(onCreate: _create),
        },
      ),
    );
  }
}

class _ShowPhrase extends StatelessWidget {
  const _ShowPhrase({required this.words, required this.onDone});

  final List<String> words;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Write down your recovery phrase', style: text.titleLarge),
        const SizedBox(height: 8),
        const Text(
          'These 24 words are the only backup of your wallet. Write them on '
          'paper, in order, and keep it somewhere safe. Anyone who has them '
          'can spend your coins. Never type them into a website or a chat.',
        ),
        const SizedBox(height: 24),
        PhraseGrid(words: words),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: onDone,
          child: const Text('I have written it down'),
        ),
      ],
    );
  }
}

/// The words of a phrase, numbered, in two columns.
class PhraseGrid extends StatelessWidget {
  const PhraseGrid({super.key, required this.words});

  final List<String> words;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyLarge
        ?.copyWith(fontFamily: 'monospace');
    final half = (words.length / 2).ceil();
    Widget column(int from, int to) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = from; i < to; i++)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(
                '${(i + 1).toString().padLeft(2)}. ${words[i]}',
                style: style,
              ),
            ),
        ],
      ),
    );
    return Card.outlined(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [column(0, half), column(half, words.length)],
        ),
      ),
    );
  }
}

class _ConfirmPhrase extends StatefulWidget {
  const _ConfirmPhrase({
    required this.words,
    required this.challenge,
    required this.onBack,
    required this.onDone,
  });

  final List<String> words;
  final List<int> challenge;
  final VoidCallback onBack;
  final VoidCallback onDone;

  @override
  State<_ConfirmPhrase> createState() => _ConfirmPhraseState();
}

class _ConfirmPhraseState extends State<_ConfirmPhrase> {
  late final _fields = [
    for (final _ in widget.challenge) TextEditingController(),
  ];
  bool _wrong = false;

  @override
  void dispose() {
    for (final field in _fields) {
      field.dispose();
    }
    super.dispose();
  }

  void _check() {
    final right = [
      for (var i = 0; i < _fields.length; i++)
        _fields[i].text.trim().toLowerCase() ==
            widget.words[widget.challenge[i]],
    ].every((ok) => ok);
    if (right) {
      widget.onDone();
    } else {
      setState(() => _wrong = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text('Check your copy', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Type these words from what you wrote down.'),
        const SizedBox(height: 24),
        for (var i = 0; i < _fields.length; i++) ...[
          TextField(
            key: ValueKey('confirm-${widget.challenge[i]}'),
            controller: _fields[i],
            autocorrect: false,
            enableSuggestions: false,
            enableIMEPersonalizedLearning: false,
            decoration: InputDecoration(
              labelText: 'Word ${widget.challenge[i] + 1}',
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_wrong) ...[
          Text(
            'That does not match. Check your copy, or go back to see the '
            'words again.',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
          const SizedBox(height: 16),
        ],
        FilledButton(onPressed: _check, child: const Text('Continue')),
        const SizedBox(height: 12),
        TextButton(
          onPressed: widget.onBack,
          child: const Text('Show the words again'),
        ),
      ],
    );
  }
}
