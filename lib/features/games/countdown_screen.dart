import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/data/game_data_repository.dart';
import '../../core/models/app_models.dart';
import '../../core/models/game_models.dart';
import '../../core/services/runtime_services.dart';
import '../../core/widgets/party_widgets.dart';

enum _Phase {
  setup,
  transition,
  prompt,
  timing,
  result,
  finalResult,
  tiebreaker,
}

class CountdownScreen extends ConsumerStatefulWidget {
  const CountdownScreen({super.key});
  @override
  ConsumerState<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends ConsumerState<CountdownScreen> {
  _Phase phase = _Phase.setup;
  List<Player> selected = <Player>[];
  int level = 5;
  int playerIndex = 0;
  int seconds = 5;
  bool success = false;
  late CountdownPrompt prompt;
  final scores = <String, int>{};
  final used = <String>{};
  Timer? timer;

  @override
  void dispose() {
    timer?.cancel();
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
        title: '5-4-3-2-1',
        style: PartyGameStyle.countdown,
        tone: phase == _Phase.finalResult || phase == _Phase.tiebreaker
            ? PartyScreenTone.success
            : switch (level) {
                4 => PartyScreenTone.action,
                3 => PartyScreenTone.secret,
                2 => PartyScreenTone.danger,
                1 => PartyScreenTone.success,
                _ => PartyScreenTone.standard,
              },
        subtitle: phase == _Phase.setup
            ? 'Think fast · Really fast'
            : 'Level $level · ${selected[playerIndex.clamp(0, selected.length - 1)].name}',
        child: PartyPhaseSwitcher(child: _content(app)),
      ),
    );
  }

  Widget _content(AppState app) => switch (phase) {
    _Phase.setup => _setup(app),
    _Phase.transition => _transition(),
    _Phase.prompt => _prompt(),
    _Phase.timing => _timing(),
    _Phase.result => _result(),
    _Phase.finalResult || _Phase.tiebreaker => _final(),
  };

  Widget _setup(AppState app) => ListView(
    key: const ValueKey<String>('countdown-setup'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      const Text(
        'Each player names 5 things in 5 seconds, then 4 in 4, all the way to 1.',
      ),
      const SizedBox(height: 18),
      Text('Players', style: Theme.of(context).textTheme.titleLarge),
      PlayerChips(
        players: app.players,
        onChanged: (List<Player> value) => selected = value,
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _start,
        icon: const Icon(Icons.bolt),
        label: const Text('START COUNTDOWN'),
      ),
    ],
  );

  Widget _transition() => Padding(
    key: ValueKey<String>('transition-$level'),
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        ResponsivePartyText(
          '$level',
          minFontSize: 88,
          maxFontSize: 132,
          maxLines: 1,
        ),
        Text(
          'NAME $level · IN $level SECONDS',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: _newTurn, child: const Text('BEGIN LEVEL')),
      ],
    ),
  );

  Widget _prompt() => Padding(
    key: ValueKey<String>('prompt-${prompt.id}'),
    padding: const EdgeInsets.all(18),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        PlayerAvatar(player: selected[playerIndex], radius: 40),
        const SizedBox(height: 10),
        Text(
          '${selected[playerIndex].name}, get ready!',
          style: Theme.of(context).textTheme.headlineMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 18),
        GradientCard(
          colors: const <Color>[PartyColors.coral, PartyColors.orange],
          child: ResponsivePartyText(
            'Name $level…\n${prompt.text.toUpperCase()}',
            minFontSize: 28,
            maxFontSize: 46,
            maxLines: 5,
          ),
        ),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: _beginTimer,
          icon: const Icon(Icons.timer),
          label: const Text('START TIMER'),
        ),
      ],
    ),
  );

  Widget _timing() => Padding(
    key: ValueKey<String>('timing-$seconds'),
    padding: const EdgeInsets.all(18),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        ResponsivePartyText(
          '$seconds',
          minFontSize: 84,
          maxFontSize: 128,
          maxLines: 1,
        ),
        Text(
          prompt.text.toUpperCase(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => _finish(true),
          child: const Text('THEY DID IT!'),
        ),
      ],
    ),
  );

  Widget _result() => ListView(
    key: ValueKey<String>('result-$level-$playerIndex'),
    padding: const EdgeInsets.all(18),
    children: <Widget>[
      Center(child: StickerBadge(emoji: success ? '⚡' : '⏰', size: 104)),
      const SizedBox(height: 22),
      Text(
        success ? '+$level POINTS' : 'TIME’S UP',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: 10),
      Text(
        '${selected[playerIndex].name}: ${scores[selected[playerIndex].id] ?? 0} total points',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton(onPressed: _next, child: const Text('CONTINUE')),
    ],
  );

  Widget _final() {
    final ranked = List<Player>.from(selected)
      ..sort(
        (Player a, Player b) =>
            (scores[b.id] ?? 0).compareTo(scores[a.id] ?? 0),
      );
    final top = scores[ranked.first.id] ?? 0;
    final tied = ranked
        .where((Player player) => scores[player.id] == top)
        .toList();
    return ListView(
      key: const ValueKey<String>('countdown-final'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Center(child: StickerBadge(emoji: '🏆', size: 104)),
        const SizedBox(height: 22),
        ScoreBoard(players: selected, scores: scores),
        if (tied.length > 1)
          FilledButton.tonalIcon(
            onPressed: () {
              setState(() {
                final winner =
                    tied[ref.read(randomProvider).nextInt(tied.length)];
                scores[winner.id] = (scores[winner.id] ?? 0) + 1;
              });
            },
            icon: const Icon(Icons.flash_on),
            label: const Text('RUN RANDOM TIEBREAKER'),
          ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _start, child: const Text('PLAY AGAIN')),
        OutlinedButton(
          onPressed: () => setState(() => phase = _Phase.setup),
          child: const Text('CHANGE PLAYERS'),
        ),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('BACK TO LIBRARY'),
        ),
      ],
    );
  }

  void _start() => setState(() {
    level = 5;
    playerIndex = 0;
    scores
      ..clear()
      ..addEntries(
        selected.map((Player player) => MapEntry<String, int>(player.id, 0)),
      );
    used.clear();
    phase = _Phase.transition;
  });

  void _newTurn() {
    final pool = ref
        .read(gameDataProvider)
        .countdown
        .where((CountdownPrompt item) => item.level == level)
        .toList();
    final available = pool
        .where((CountdownPrompt item) => !used.contains(item.id))
        .toList();
    prompt =
        (available.isEmpty ? pool : available)[ref
            .read(randomProvider)
            .nextInt((available.isEmpty ? pool : available).length)];
    used.add(prompt.id);
    setState(() => phase = _Phase.prompt);
  }

  void _beginTimer() {
    timer?.cancel();
    setState(() {
      seconds = level;
      phase = _Phase.timing;
    });
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

  void _finish(bool didSucceed) {
    if (phase != _Phase.timing) return;
    timer?.cancel();
    success = didSucceed;
    if (success) {
      scores[selected[playerIndex].id] =
          (scores[selected[playerIndex].id] ?? 0) + level;
    }
    setState(() => phase = _Phase.result);
  }

  void _next() {
    if (playerIndex + 1 < selected.length) {
      playerIndex++;
      _newTurn();
    } else {
      setState(() {
        if (level > 1) {
          level--;
          playerIndex = 0;
          phase = _Phase.transition;
        } else {
          phase = _Phase.finalResult;
        }
      });
    }
  }
}
