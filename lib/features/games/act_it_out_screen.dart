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

enum _ActMode { classic, imposter }

enum _ActPhase { setup, handoff, acting, score, reveal }

class ActItOutScreen extends ConsumerStatefulWidget {
  const ActItOutScreen({super.key});
  @override
  ConsumerState<ActItOutScreen> createState() => _ActItOutScreenState();
}

class _ActItOutScreenState extends ConsumerState<ActItOutScreen> {
  _ActMode mode = _ActMode.classic;
  _ActPhase phase = _ActPhase.setup;
  List<Player> players = <Player>[];
  String category = 'All';
  int secondsPerTurn = 60;
  int rounds = 2;
  int turn = 0;
  int seconds = 60;
  late ActingPrompt prompt;
  String? imposterId;
  Timer? timer;
  final scores = <String, int>{};
  final used = <String>{};

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    if (players.isEmpty) players = List<Player>.from(app.players);
    return PopScope(
      canPop: phase == _ActPhase.setup,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop && await confirmLeaveGame(context) && context.mounted) {
          context.pop();
        }
      },
      child: PartyPage(
        title: 'Act It Out',
        style: PartyGameStyle.actItOut,
        tone: switch (phase) {
          _ActPhase.handoff when mode == _ActMode.imposter =>
            PartyScreenTone.secret,
          _ActPhase.acting => PartyScreenTone.action,
          _ActPhase.score || _ActPhase.reveal => PartyScreenTone.success,
          _ => PartyScreenTone.standard,
        },
        subtitle: phase == _ActPhase.setup
            ? '420 prompts · No props needed'
            : players[turn % players.length].name,
        child: PartyPhaseSwitcher(child: _body(app)),
      ),
    );
  }

  Widget _body(AppState app) => switch (phase) {
    _ActPhase.setup => _setup(app),
    _ActPhase.handoff => _handoff(),
    _ActPhase.acting => _acting(),
    _ActPhase.score => _scoreView(),
    _ActPhase.reveal => _reveal(),
  };

  Widget _setup(AppState app) {
    final categories = <String>{
      'All',
      ...ref.read(gameDataProvider).acting.map((ActingPrompt p) => p.category),
    }.toList()..sort();
    return ListView(
      key: const ValueKey<String>('acting-setup'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        SegmentedButton<_ActMode>(
          expandedInsets: EdgeInsets.zero,
          showSelectedIcon: false,
          segments: const <ButtonSegment<_ActMode>>[
            ButtonSegment<_ActMode>(
              value: _ActMode.classic,
              label: Text('Classic'),
            ),
            ButtonSegment<_ActMode>(
              value: _ActMode.imposter,
              label: Text('Imposter'),
            ),
          ],
          selected: <_ActMode>{mode},
          onSelectionChanged: (Set<_ActMode> value) =>
              setState(() => mode = value.first),
        ),
        const SizedBox(height: 16),
        Text(
          mode == _ActMode.classic
              ? 'Act without speaking. The group guesses before time runs out.'
              : 'Everyone sees the same prompt except the imposter, who sees only its category.',
        ),
        const SizedBox(height: 18),
        PlayerChips(
          players: app.players,
          minimum: mode == _ActMode.imposter ? 3 : 2,
          onChanged: (List<Player> value) => players = value,
        ),
        const SizedBox(height: 16),
        PartyDropdownField<String>(
          label: 'Category',
          initialValue: category,
          items: categories
              .map(
                (String value) =>
                    DropdownMenuItem<String>(value: value, child: Text(value)),
              )
              .toList(),
          onChanged: (String? value) =>
              setState(() => category = value ?? 'All'),
        ),
        const SizedBox(height: 12),
        PartyDropdownField<int>(
          label: 'Acting time',
          initialValue: secondsPerTurn,
          items: const <int>[30, 45, 60, 90]
              .map(
                (int value) => DropdownMenuItem<int>(
                  value: value,
                  child: Text('$value seconds'),
                ),
              )
              .toList(),
          onChanged: (int? value) => secondsPerTurn = value ?? 60,
        ),
        if (mode == _ActMode.classic) ...<Widget>[
          const SizedBox(height: 12),
          PartyDropdownField<int>(
            label: 'Rounds per player',
            initialValue: rounds,
            items: const <int>[1, 2, 3]
                .map(
                  (int value) => DropdownMenuItem<int>(
                    value: value,
                    child: Text('$value'),
                  ),
                )
                .toList(),
            onChanged: (int? value) => rounds = value ?? 2,
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.play_arrow),
          label: const Text('START LOCAL GAME'),
        ),
        OutlinedButton.icon(
          onPressed: () => context.push('/nearby?game=acting'),
          icon: const Icon(Icons.wifi),
          label: const Text('PLAY NEARBY'),
        ),
      ],
    );
  }

  Widget _handoff() {
    final player = players[turn % players.length];
    final hidden = player.id == imposterId;
    return Padding(
      key: ValueKey<String>('act-handoff-$turn'),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          PlayerAvatar(player: player, radius: 46),
          const SizedBox(height: 14),
          Text(
            'Pass to ${player.name}',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text('Keep the screen private.'),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (BuildContext dialogContext) => AlertDialog(
                title: Text(
                  hidden ? 'You are the acting imposter' : prompt.text,
                ),
                content: Text(
                  hidden
                      ? 'Category: ${prompt.category}. Watch closely and blend in.'
                      : 'Act it out without speaking or spelling.',
                ),
                actions: <Widget>[
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(dialogContext)
                          .colorScheme
                          .primary,
                      foregroundColor: Theme.of(dialogContext)
                          .colorScheme
                          .onPrimary,
                    ),
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _begin();
                    },
                    child: const Text('READY'),
                  ),
                ],
              ),
            ),
            child: const Text('REVEAL MY PROMPT'),
          ),
        ],
      ),
    );
  }

  Widget _acting() => Padding(
    key: ValueKey<String>('acting-$turn-$seconds'),
    padding: const EdgeInsets.all(18),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        ResponsivePartyText(
          '$seconds',
          minFontSize: 72,
          maxFontSize: 120,
          maxLines: 1,
        ),
        ResponsivePartyText(
          mode == _ActMode.classic ? prompt.text : 'ACT AND OBSERVE',
          minFontSize: 30,
          maxFontSize: 52,
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: _finish,
          icon: const Icon(Icons.stop),
          label: const Text('STOP TIMER'),
        ),
      ],
    ),
  );

  Widget _scoreView() => ListView(
    key: ValueKey<String>('act-score-$turn'),
    padding: const EdgeInsets.all(18),
    children: <Widget>[
      Text(
        prompt.text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      const SizedBox(height: 18),
      if (mode == _ActMode.classic) ...<Widget>[
        FilledButton.icon(
          onPressed: () => _award(true),
          icon: const Icon(Icons.check),
          label: const Text('GUESSED · +1'),
        ),
        OutlinedButton(
          onPressed: () => _award(false),
          child: const Text('NOT GUESSED'),
        ),
      ] else
        FilledButton(
          onPressed: _nextImposter,
          child: Text(
            turn + 1 >= players.length ? 'REVEAL IMPOSTER' : 'NEXT PLAYER',
          ),
        ),
    ],
  );

  Widget _reveal() {
    if (mode == _ActMode.imposter) {
      final imposter = players.firstWhere((Player p) => p.id == imposterId);
      return ListView(
        key: const ValueKey<String>('acting-imposter-result'),
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Center(child: StickerBadge(emoji: '🎭', size: 104)),
          const SizedBox(height: 24),
          Text(
            '${imposter.name} was the acting imposter',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text('The prompt was “${prompt.text}”.', textAlign: TextAlign.center),
          const SizedBox(height: 24),
          FilledButton(onPressed: _start, child: const Text('PLAY AGAIN')),
          TextButton(
            onPressed: () => setState(() => phase = _ActPhase.setup),
            child: const Text('CHANGE SETUP'),
          ),
        ],
      );
    }
    return ListView(
      key: const ValueKey<String>('charades-result'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Center(child: StickerBadge(emoji: '🏆', size: 104)),
        const SizedBox(height: 22),
        ScoreBoard(players: players, scores: scores),
        const SizedBox(height: 16),
        FilledButton(onPressed: _start, child: const Text('PLAY AGAIN')),
        TextButton(
          onPressed: () => setState(() => phase = _ActPhase.setup),
          child: const Text('CHANGE SETUP'),
        ),
      ],
    );
  }

  void _start() {
    if (players.length < (mode == _ActMode.imposter ? 3 : 2)) return;
    final pool = ref
        .read(gameDataProvider)
        .acting
        .where((ActingPrompt p) => category == 'All' || p.category == category)
        .toList();
    final random = ref.read(randomProvider);
    prompt = pool[random.nextInt(pool.length)];
    used
      ..clear()
      ..add(prompt.id);
    scores
      ..clear()
      ..addEntries(players.map((Player p) => MapEntry<String, int>(p.id, 0)));
    imposterId = mode == _ActMode.imposter
        ? players[random.nextInt(players.length)].id
        : null;
    turn = 0;
    setState(() => phase = _ActPhase.handoff);
  }

  void _begin() {
    timer?.cancel();
    seconds = secondsPerTurn;
    setState(() => phase = _ActPhase.acting);
    timer = Timer.periodic(const Duration(seconds: 1), (Timer value) {
      if (!mounted) return;
      if (seconds <= 1) {
        value.cancel();
        _finish();
      } else {
        setState(() => seconds--);
      }
    });
  }

  void _finish() {
    timer?.cancel();
    if (phase == _ActPhase.acting) setState(() => phase = _ActPhase.score);
  }

  void _award(bool correct) {
    if (correct) {
      scores[players[turn % players.length].id] =
          (scores[players[turn % players.length].id] ?? 0) + 1;
    }
    turn++;
    if (turn >= players.length * rounds) {
      setState(() => phase = _ActPhase.reveal);
      return;
    }
    final pool = ref
        .read(gameDataProvider)
        .acting
        .where((ActingPrompt p) => category == 'All' || p.category == category)
        .toList();
    final available = pool
        .where((ActingPrompt p) => !used.contains(p.id))
        .toList();
    prompt =
        (available.isEmpty ? pool : available)[ref
            .read(randomProvider)
            .nextInt((available.isEmpty ? pool : available).length)];
    used.add(prompt.id);
    setState(() => phase = _ActPhase.handoff);
  }

  void _nextImposter() {
    turn++;
    setState(
      () =>
          phase = turn >= players.length ? _ActPhase.reveal : _ActPhase.handoff,
    );
  }
}
