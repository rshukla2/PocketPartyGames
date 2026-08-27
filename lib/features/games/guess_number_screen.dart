import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/models/app_models.dart';
import '../../core/services/runtime_services.dart';
import '../../core/widgets/party_widgets.dart';

enum _Phase { setup, pass, play, result, finalResult }

class GuessNumberScreen extends ConsumerStatefulWidget {
  const GuessNumberScreen({super.key});
  @override
  ConsumerState<GuessNumberScreen> createState() => _GuessNumberScreenState();
}

class _GuessNumberScreenState extends ConsumerState<GuessNumberScreen> {
  _Phase phase = _Phase.setup;
  List<Player> selected = <Player>[];
  int minValue = 1;
  int maxValue = 100;
  int timerSeconds = 60;
  int roundsPerPlayer = 1;
  int turn = 0;
  int target = 1;
  int questions = 0;
  int seconds = 0;
  bool guessed = false;
  Timer? timer;
  final scores = <String, int>{};
  final recent = <int>[];

  @override
  void dispose() {
    timer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    if (selected.isEmpty) selected = List<Player>.from(app.players);
    return PopScope(
      canPop: phase == _Phase.setup,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop && await confirmLeaveGame(context) && context.mounted) {
          context.pop();
        }
      },
      child: PartyPage(
        title: 'Guess My Number',
        style: PartyGameStyle.guessNumber,
        tone: switch (phase) {
          _Phase.pass => PartyScreenTone.secret,
          _Phase.play => PartyScreenTone.action,
          _Phase.result || _Phase.finalResult => PartyScreenTone.success,
          _ => PartyScreenTone.standard,
        },
        subtitle: switch (phase) {
          _Phase.setup => 'Forehead-style number deduction',
          _Phase.pass => 'Pass the phone privately',
          _Phase.play => 'Ask only yes-or-no questions',
          _Phase.result => 'Turn ${turn + 1} complete',
          _Phase.finalResult => 'Final scoreboard',
        },
        child: PartyPhaseSwitcher(child: _content(app)),
      ),
    );
  }

  Widget _content(AppState app) => switch (phase) {
    _Phase.setup => _setup(app),
    _Phase.pass => _pass(),
    _Phase.play => _play(),
    _Phase.result => _roundResult(),
    _Phase.finalResult => _final(),
  };

  Widget _setup(AppState app) => ListView(
    key: const ValueKey<String>('guess-setup'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Text('Players', style: Theme.of(context).textTheme.titleLarge),
      PlayerChips(
        players: app.players,
        onChanged: (List<Player> value) => selected = value,
      ),
      const SizedBox(height: 18),
      DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: '$minValue-$maxValue',
        decoration: const InputDecoration(labelText: 'Number range'),
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem(value: '1-10', child: Text('1 to 10 · Easy')),
          DropdownMenuItem(value: '1-50', child: Text('1 to 50 · Quick')),
          DropdownMenuItem(value: '1-100', child: Text('1 to 100 · Classic')),
          DropdownMenuItem(value: '1-500', child: Text('1 to 500 · Expert')),
        ],
        onChanged: (String? value) {
          final parts = value!.split('-');
          setState(() {
            minValue = int.parse(parts[0]);
            maxValue = int.parse(parts[1]);
          });
        },
      ),
      const SizedBox(height: 16),
      Text('Timer: ${timerSeconds == 0 ? 'Off' : '${timerSeconds}s'}'),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: <int>[0, 30, 60, 90]
            .map(
              (int value) => ChoiceChip(
                label: Text(value == 0 ? 'Off' : '${value}s'),
                selected: timerSeconds == value,
                onSelected: (_) => setState(() => timerSeconds = value),
              ),
            )
            .toList(),
      ),
      const SizedBox(height: 16),
      Text('Turns per player: $roundsPerPlayer'),
      Slider(
        value: roundsPerPlayer.toDouble(),
        min: 1,
        max: 5,
        divisions: 4,
        label: '$roundsPerPlayer',
        onChanged: (double value) =>
            setState(() => roundsPerPlayer = value.round()),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _start,
        icon: const Icon(Icons.play_arrow),
        label: const Text('START GAME'),
      ),
    ],
  );

  Player get active => selected[turn % selected.length];

  Widget _pass() => Padding(
    key: ValueKey<int>(turn),
    padding: const EdgeInsets.all(22),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        PlayerAvatar(player: active, radius: 46),
        const SizedBox(height: 16),
        Text(
          'PASS TO ${active.name.toUpperCase()}',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        const Text(
          'Hold the phone against your forehead without looking at the screen.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 26),
        FilledButton.icon(
          onPressed: _beginTurn,
          icon: const Icon(Icons.screen_rotation_alt),
          label: const Text('PHONE IN POSITION'),
        ),
      ],
    ),
  );

  Widget _play() => Padding(
    key: ValueKey<String>('guess-$turn-$seconds-$questions'),
    padding: const EdgeInsets.all(18),
    child: Column(
      children: <Widget>[
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: <Widget>[
            Text(
              '${active.name} · $questions questions',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (timerSeconds > 0)
              Text(
                '${seconds}s',
                style: Theme.of(context).textTheme.titleLarge,
              ),
          ],
        ),
        const Spacer(),
        ResponsivePartyText(
          '$target',
          minFontSize: 72,
          maxFontSize: 118,
          maxLines: 1,
        ),
        const Text('Everyone else gives only YES or NO answers.'),
        const Spacer(),
        OutlinedButton.icon(
          onPressed: () => setState(() => questions++),
          icon: const Icon(Icons.add),
          label: const Text('COUNT A QUESTION'),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.tonal(
                onPressed: () => _finish(false),
                child: const Text('GIVE UP'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton(
                onPressed: () => _finish(true),
                child: const Text('GUESSED IT!'),
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _roundResult() => ListView(
    key: ValueKey<String>('guess-result-$turn'),
    padding: const EdgeInsets.all(18),
    children: <Widget>[
      Center(child: StickerBadge(emoji: guessed ? '🎯' : '⏳', size: 104)),
      const SizedBox(height: 22),
      Text(
        guessed ? '${active.name} got it!' : 'The number was $target',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 10),
      Text(
        '$questions questions asked · ${scores[active.id] ?? 0} points total',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 26),
      FilledButton(
        onPressed: _next,
        child: Text(
          turn + 1 >= selected.length * roundsPerPlayer
              ? 'VIEW FINAL PODIUM'
              : 'NEXT PLAYER',
        ),
      ),
    ],
  );

  Widget _final() => ListView(
    key: const ValueKey<String>('guess-final'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      const Center(child: StickerBadge(emoji: '🏆', size: 104)),
      const SizedBox(height: 22),
      ScoreBoard(players: selected, scores: scores),
      const SizedBox(height: 18),
      FilledButton(onPressed: _start, child: const Text('PLAY AGAIN')),
      OutlinedButton(
        onPressed: () => setState(() => phase = _Phase.setup),
        child: const Text('CHANGE SETUP'),
      ),
      TextButton(
        onPressed: () => context.go('/'),
        child: const Text('BACK TO LIBRARY'),
      ),
    ],
  );

  void _start() {
    setState(() {
      scores
        ..clear()
        ..addEntries(
          selected.map((Player player) => MapEntry<String, int>(player.id, 0)),
        );
      recent.clear();
      turn = 0;
      phase = _Phase.pass;
    });
  }

  void _beginTurn() {
    final available = List<int>.generate(
      maxValue - minValue + 1,
      (int index) => minValue + index,
    )..removeWhere(recent.contains);
    target = available[ref.read(randomProvider).nextInt(available.length)];
    recent.add(target);
    if (recent.length > 20) recent.removeAt(0);
    questions = 0;
    seconds = timerSeconds;
    WakelockPlus.enable();
    setState(() => phase = _Phase.play);
    timer?.cancel();
    if (timerSeconds > 0) {
      timer = Timer.periodic(const Duration(seconds: 1), (Timer value) {
        if (!mounted) return;
        if (seconds <= 1) {
          value.cancel();
          _finish(false);
        } else {
          setState(() => seconds--);
        }
      });
    }
  }

  void _finish(bool success) {
    timer?.cancel();
    WakelockPlus.disable();
    if (phase != _Phase.play) return;
    guessed = success;
    if (success) {
      scores[active.id] = (scores[active.id] ?? 0) + max(1, 10 - questions);
    }
    setState(() => phase = _Phase.result);
  }

  void _next() => setState(() {
    turn++;
    phase = turn >= selected.length * roundsPerPlayer
        ? _Phase.finalResult
        : _Phase.pass;
  });
}
