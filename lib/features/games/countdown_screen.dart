import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/data/game_data_repository.dart';
import '../../core/models/app_models.dart';
import '../../core/services/runtime_services.dart';
import '../../core/widgets/party_widgets.dart';
import 'countdown_engine.dart';

class CountdownScreen extends ConsumerStatefulWidget {
  const CountdownScreen({super.key});

  @override
  ConsumerState<CountdownScreen> createState() => _CountdownScreenState();
}

class _CountdownScreenState extends ConsumerState<CountdownScreen> {
  static const _engine = CountdownGameEngine();

  List<Player> selected = <Player>[];
  bool selectionInitialized = false;
  CountdownMatch? match;
  int seconds = 0;
  Timer? timer;

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    if (!selectionInitialized) {
      selected = List<Player>.from(app.players);
      selectionInitialized = true;
    }
    final current = match;
    final phase = current?.phase;
    final level = current?.currentTurn.level ?? 5;
    return PopScope(
      canPop: current == null,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop && await confirmLeaveGame(context) && context.mounted) {
          timer?.cancel();
          context.pop();
        }
      },
      child: PartyPage(
        title: '5-4-3-2-1',
        centerTitle: true,
        style: PartyGameStyle.countdown,
        tone: phase == CountdownPhase.finalResult
            ? PartyScreenTone.success
            : switch (level) {
                4 => PartyScreenTone.action,
                3 => PartyScreenTone.secret,
                2 => PartyScreenTone.danger,
                1 => PartyScreenTone.success,
                _ => PartyScreenTone.standard,
              },
        subtitle: current == null
            ? null
            : phase == CountdownPhase.finalResult
            ? 'Final leaderboard'
            : 'Level $level · ${_playerFor(current.currentTurn.playerId).name}',
        child: PartyPhaseSwitcher(child: _content(app)),
      ),
    );
  }

  Widget _content(AppState app) {
    final current = match;
    if (current == null) return _setup(app);
    return switch (current.phase) {
      CountdownPhase.transition => _transition(current),
      CountdownPhase.prompt => _prompt(current),
      CountdownPhase.timing => _timing(current),
      CountdownPhase.scoreEntry => _scoreEntry(current),
      CountdownPhase.finalResult => _final(current),
    };
  }

  Widget _setup(AppState app) => ListView(
    key: const ValueKey<String>('countdown-setup'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      const Text(
        'Each player completes all five levels before the phone moves to the next player.',
      ),
      const SizedBox(height: 18),
      Text('Players', style: Theme.of(context).textTheme.titleLarge),
      PlayerChips(
        players: app.players,
        minimum: 1,
        onChanged: (List<Player> value) => setState(() => selected = value),
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: selected.isEmpty ? null : _start,
        icon: const Icon(Icons.bolt),
        label: const Text('START COUNTDOWN'),
      ),
    ],
  );

  Widget _transition(CountdownMatch current) {
    final turn = current.currentTurn;
    final player = _playerFor(turn.playerId);
    return Padding(
      key: ValueKey<String>('transition-${current.turnIndex}-${turn.level}'),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          PlayerNameBadge(player: player),
          const SizedBox(height: 20),
          ResponsivePartyText(
            '${turn.level}',
            minFontSize: 88,
            maxFontSize: 132,
            maxLines: 1,
          ),
          Text(
            'NAME ${turn.level} · IN ${turn.level} SECONDS',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _showPrompt,
            child: const Text('BEGIN LEVEL'),
          ),
        ],
      ),
    );
  }

  Widget _prompt(CountdownMatch current) {
    final turn = current.currentTurn;
    final player = _playerFor(turn.playerId);
    return SingleChildScrollView(
      key: ValueKey<String>('prompt-${current.turnIndex}-${turn.prompt.id}'),
      padding: const EdgeInsets.all(18),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          PlayerNameBadge(player: player),
          const SizedBox(height: 10),
          Text(
            '${player.name}, get ready!',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          GradientCard(
            colors: const <Color>[PartyColors.coral, PartyColors.orange],
            child: ResponsivePartyText(
              'Name ${turn.level}…\n${turn.prompt.text.toUpperCase()}',
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
  }

  Widget _timing(CountdownMatch current) => Padding(
    key: ValueKey<String>('timing-${current.turnIndex}-$seconds'),
    padding: const EdgeInsets.all(18),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        ResponsivePartyText(
          '$seconds',
          minFontSize: 84,
          maxFontSize: 128,
          maxLines: 1,
        ),
        Text(
          current.currentTurn.prompt.text.toUpperCase(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ],
    ),
  );

  Widget _scoreEntry(CountdownMatch current) {
    final turn = current.currentTurn;
    final player = _playerFor(turn.playerId);
    final selectedAnswer = current.answerCount;
    final total = current.scores[player.id] ?? 0;
    return SingleChildScrollView(
      key: ValueKey<String>('score-entry-${current.turnIndex}'),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const StickerBadge(emoji: '⏰', size: 104),
          const SizedBox(height: 22),
          Text(
            'TIME’S UP',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displaySmall,
          ),
          const SizedBox(height: 12),
          Text(
            'HOW MANY DID THEY ANSWER?',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 18),
          Semantics(
            label: 'Choose answers from 0 to ${turn.level}',
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                for (var answer = 0; answer <= turn.level; answer++)
                  SizedBox.square(
                    dimension: 56,
                    child: answer == selectedAnswer
                        ? FilledButton(
                            key: ValueKey<String>('answer-$answer'),
                            onPressed: () => _selectAnswer(answer),
                            child: Text('$answer'),
                          )
                        : OutlinedButton(
                            key: ValueKey<String>('answer-$answer'),
                            onPressed: () => _selectAnswer(answer),
                            child: Text('$answer'),
                          ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            selectedAnswer == null
                ? '${player.name} has $total points'
                : '+$selectedAnswer this level · ${total + selectedAnswer} total',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              key: const Key('countdown-continue'),
              onPressed: selectedAnswer == null ? null : _continue,
              child: const Text('CONTINUE'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _final(CountdownMatch current) {
    final ranked = List<Player>.from(selected)
      ..sort(
        (Player a, Player b) =>
            (current.scores[b.id] ?? 0).compareTo(current.scores[a.id] ?? 0),
      );
    final winnerNames = current.winnerIds
        .map((String id) => _playerFor(id).name)
        .join(' & ');
    final coWinners = current.winnerIds.length > 1;
    return ListView(
      key: const ValueKey<String>('countdown-final'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Center(child: StickerBadge(emoji: '🏆', size: 104)),
        const SizedBox(height: 22),
        Text(
          coWinners ? 'CO-WINNERS' : 'WINNER',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 6),
        ResponsivePartyText(
          winnerNames.toUpperCase(),
          minFontSize: 30,
          maxFontSize: 54,
          maxLines: 3,
        ),
        const SizedBox(height: 18),
        ...ranked.indexed.map(((int, Player) entry) {
          final (index, player) = entry;
          final isWinner = current.winnerIds.contains(player.id);
          return PartyCard(
            child: ListTile(
              leading: Text(
                isWinner ? '🏆' : '#${index + 1}',
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                ),
              ),
              title: Text(player.name),
              trailing: Text(
                '${current.scores[player.id] ?? 0}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          );
        }),
        const SizedBox(height: 12),
        FilledButton(onPressed: _start, child: const Text('PLAY AGAIN')),
        OutlinedButton(
          onPressed: _changePlayers,
          child: const Text('CHANGE PLAYERS'),
        ),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('BACK TO LIBRARY'),
        ),
      ],
    );
  }

  Player _playerFor(String id) =>
      selected.firstWhere((Player player) => player.id == id);

  void _start() {
    timer?.cancel();
    setState(() {
      seconds = 0;
      match = _engine.start(
        players: selected,
        prompts: ref.read(gameDataProvider).countdown,
        random: ref.read(randomProvider),
      );
    });
  }

  void _showPrompt() => setState(() {
    match = _engine.showPrompt(match!);
  });

  void _beginTimer() {
    timer?.cancel();
    final timingMatch = _engine.startTimer(match!);
    setState(() {
      match = timingMatch;
      seconds = timingMatch.currentTurn.level;
    });
    timer = Timer.periodic(const Duration(seconds: 1), (Timer value) {
      if (!mounted || match?.phase != CountdownPhase.timing) {
        value.cancel();
        return;
      }
      if (seconds <= 1) {
        value.cancel();
        _expireTimer();
      } else {
        setState(() => seconds--);
      }
    });
  }

  void _expireTimer() {
    if (match?.phase != CountdownPhase.timing) return;
    timer?.cancel();
    setState(() {
      seconds = 0;
      match = _engine.expireTimer(match!);
    });
    final settings = ref.read(appControllerProvider).settings;
    final feedback = ref.read(partyFeedbackProvider);
    if (settings.soundEnabled) {
      unawaited(feedback.playAlert());
    }
    if (settings.hapticsEnabled) {
      unawaited(feedback.heavyImpact());
    }
  }

  void _selectAnswer(int answer) => setState(() {
    match = _engine.selectAnswer(match!, answer);
  });

  void _continue() => setState(() {
    match = _engine.continueAfterScore(match!);
  });

  void _changePlayers() {
    timer?.cancel();
    setState(() {
      seconds = 0;
      match = null;
    });
  }
}
