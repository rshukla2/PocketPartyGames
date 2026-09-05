import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/models/app_models.dart';
import '../../core/services/runtime_services.dart';
import '../../core/widgets/party_widgets.dart';
import 'stop_timer_engine.dart';

enum _ShellPhase { menu, setup, game }

class StopTimerScreen extends ConsumerStatefulWidget {
  const StopTimerScreen({super.key});

  @override
  ConsumerState<StopTimerScreen> createState() => _StopTimerScreenState();
}

class _StopTimerScreenState extends ConsumerState<StopTimerScreen> {
  static const _engine = StopTimerGameEngine();

  _ShellPhase shellPhase = _ShellPhase.menu;
  StopTimerMode mode = StopTimerMode.solo;
  List<Player> selected = <Player>[];
  bool selectionInitialized = false;
  int pointsGoal = 5;
  int imposterCount = 1;
  TimerImposterInfoMode imposterInfoMode = TimerImposterInfoMode.falseTarget;
  StopTimerGameState? game;
  bool showingSecret = false;
  final Stopwatch stopwatch = Stopwatch();

  @override
  void dispose() {
    stopwatch.stop();
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    if (!selectionInitialized) {
      selected = List<Player>.from(app.players.take(4));
      selectionInitialized = true;
    }
    final phase = game?.phase;
    return PopScope(
      canPop: shellPhase != _ShellPhase.game,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop && await confirmLeaveGame(context) && context.mounted) {
          context.pop();
        }
      },
      child: PartyPage(
        title: 'Stop the Timer',
        style: PartyGameStyle.stopTimer,
        tone: switch (phase) {
          StopTimerPhase.privateReveal => PartyScreenTone.secret,
          StopTimerPhase.running => PartyScreenTone.action,
          StopTimerPhase.roundResult ||
          StopTimerPhase.finalResult => PartyScreenTone.success,
          _ => PartyScreenTone.standard,
        },
        subtitle: _subtitle,
        child: PartyPhaseSwitcher(child: _content(app)),
      ),
    );
  }

  String get _subtitle {
    if (shellPhase == _ShellPhase.menu) return 'Precision timing showdown';
    if (shellPhase == _ShellPhase.setup) return '${_modeName(mode)} setup';
    final current = game!;
    return switch (current.phase) {
      StopTimerPhase.targetReveal =>
        mode == StopTimerMode.buzzer
            ? 'Round ${current.plan.number} · Memorize together'
            : 'Solo target',
      StopTimerPhase.privateReveal =>
        'Private target ${current.revealIndex + 1}/${selected.length}',
      StopTimerPhase.handoff =>
        'Attempt ${current.currentPlayerIndex + 1}/${current.plan.playOrder.length}',
      StopTimerPhase.running => '${_currentPlayer(current).name} is timing',
      StopTimerPhase.roundResult =>
        mode == StopTimerMode.solo
            ? 'Attempt result'
            : 'Round ${current.plan.number} results',
      StopTimerPhase.voting => 'One group accusation',
      StopTimerPhase.finalResult =>
        mode == StopTimerMode.buzzer
            ? 'Final scoreboard'
            : 'Imposters revealed',
    };
  }

  Widget _content(AppState app) => switch (shellPhase) {
    _ShellPhase.menu => _menu(),
    _ShellPhase.setup => _setup(app),
    _ShellPhase.game => _gameContent(app),
  };

  Widget _gameContent(AppState app) => switch (game!.phase) {
    StopTimerPhase.targetReveal => _targetReveal(app),
    StopTimerPhase.privateReveal => _privateReveal(),
    StopTimerPhase.handoff => _handoff(),
    StopTimerPhase.running => _running(),
    StopTimerPhase.roundResult => _roundResult(app),
    StopTimerPhase.voting => _voting(),
    StopTimerPhase.finalResult => _finalResult(),
  };

  Widget _menu() => ListView(
    key: const ValueKey<String>('timer-menu'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      _modeCard(
        StopTimerMode.solo,
        '🎯',
        'SOLO TRAINING',
        'Memorize a hidden target and stop with millisecond precision.',
      ),
      _modeCard(
        StopTimerMode.buzzer,
        '🚨',
        'BUZZER BATTLE',
        'Take private turns. The closest player scores until someone reaches the goal.',
      ),
      _modeCard(
        StopTimerMode.imposter,
        '🕵️',
        'TIMER IMPOSTER',
        'Follow your secret timing clue, take a private turn, then vote.',
      ),
    ],
  );

  Widget _modeCard(
    StopTimerMode value,
    String emoji,
    String title,
    String body,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: GradientCard(
      colors: value == StopTimerMode.solo
          ? const <Color>[PartyColors.yellow, PartyColors.orange]
          : value == StopTimerMode.buzzer
          ? const <Color>[PartyColors.coral, PartyColors.pink]
          : const <Color>[PartyColors.purple, PartyColors.blue],
      onTap: () => _selectMode(value),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Text(emoji, style: const TextStyle(fontSize: 42)),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        subtitle: Text(body),
        trailing: const Icon(Icons.arrow_forward),
      ),
    ),
  );

  Widget _setup(AppState app) {
    final minimum = mode == StopTimerMode.imposter ? 3 : 2;
    final maximumImposters = max(1, (selected.length - 1) ~/ 2);
    if (imposterCount > maximumImposters) imposterCount = maximumImposters;
    return ListView(
      key: ValueKey<String>('timer-setup-${mode.name}'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text('PLAYERS', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        PlayerChips(
          key: ValueKey<String>('timer-players-${mode.name}'),
          players: app.players,
          minimum: minimum,
          onChanged: (List<Player> value) => setState(() {
            selected = value;
            imposterCount = min(
              imposterCount,
              max(1, (selected.length - 1) ~/ 2),
            );
          }),
        ),
        if (mode == StopTimerMode.buzzer) ...<Widget>[
          const SizedBox(height: 22),
          Text(
            'FIRST TO: $pointsGoal POINTS',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          PartySlider(
            value: pointsGoal.toDouble(),
            min: 3,
            max: 15,
            divisions: 12,
            label: '$pointsGoal',
            onChanged: (double value) =>
                setState(() => pointsGoal = value.round()),
          ),
          const Text(
            'Closest earns 1 point. Match the displayed hundredth exactly for 2.',
          ),
        ],
        if (mode == StopTimerMode.imposter) ...<Widget>[
          const SizedBox(height: 22),
          Text(
            'IMPOSTERS: $imposterCount',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          PartySlider(
            value: imposterCount.toDouble(),
            min: maximumImposters == 1 ? 0 : 1,
            max: maximumImposters.toDouble(),
            divisions: maximumImposters == 1 ? null : maximumImposters - 1,
            label: '$imposterCount',
            onChanged: maximumImposters == 1
                ? null
                : (double value) =>
                      setState(() => imposterCount = value.round()),
          ),
          const SizedBox(height: 18),
          Text('IMPOSTER INFO', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<TimerImposterInfoMode>(
            showSelectedIcon: false,
            segments: const <ButtonSegment<TimerImposterInfoMode>>[
              ButtonSegment(
                value: TimerImposterInfoMode.falseTarget,
                label: Text('FALSE TARGET'),
              ),
              ButtonSegment(
                value: TimerImposterInfoMode.noTarget,
                label: Text('NO TARGET'),
              ),
            ],
            selected: <TimerImposterInfoMode>{imposterInfoMode},
            onSelectionChanged: (Set<TimerImposterInfoMode> value) =>
                setState(() => imposterInfoMode = value.first),
          ),
          const SizedBox(height: 8),
          Text(
            imposterInfoMode == TimerImposterInfoMode.falseTarget
                ? 'Everyone sees a target. Imposters secretly share a nearby alternate.'
                : 'Crew sees the target. Imposters are told only that they are imposters.',
          ),
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: selected.length < minimum ? null : _startMatch,
          icon: const Icon(Icons.play_arrow),
          label: Text(
            mode == StopTimerMode.imposter ? 'DEAL SECRET INFO' : 'START MATCH',
          ),
        ),
        if (selected.length < minimum)
          Text(
            'Choose at least $minimum players.',
            textAlign: TextAlign.center,
          ),
        if (!kIsWeb) ...<Widget>[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: selected.length < minimum ? null : _startNearby,
            icon: const Icon(Icons.wifi_tethering),
            label: const Text('USE NEARBY PHONES'),
          ),
        ],
      ],
    );
  }

  Widget _targetReveal(AppState app) {
    final current = game!;
    return Padding(
      key: ValueKey<String>('timer-target-${current.plan.number}'),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const StickerBadge(emoji: '⏱️', size: 104),
          const SizedBox(height: 20),
          const Text(
            'TARGET TIME',
            style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2),
          ),
          const SizedBox(height: 8),
          ResponsivePartyText(
            '${current.plan.targetSeconds.toStringAsFixed(2)}s',
            minFontSize: 54,
            maxFontSize: 90,
            maxLines: 1,
          ),
          if (mode == StopTimerMode.solo)
            Text(
              '${app.soloStats.attempts} attempts · Best ${app.soloStats.bestErrorMs == null ? '—' : '±${(app.soloStats.bestErrorMs! / 1000).toStringAsFixed(2)}s'}',
            ),
          const SizedBox(height: 24),
          Text(
            mode == StopTimerMode.solo
                ? 'Memorize the target. The clock disappears when you start.'
                : 'Everyone memorizes this target. Hide it before the first private turn.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 26),
          FilledButton.icon(
            onPressed: mode == StopTimerMode.solo
                ? _startSoloAttempt
                : _hideBuzzerTarget,
            icon: const Icon(Icons.visibility_off),
            label: Text(
              mode == StopTimerMode.solo
                  ? 'START TIMER'
                  : 'HIDE TARGET & START TURNS',
            ),
          ),
        ],
      ),
    );
  }

  Widget _privateReveal() {
    final current = game!;
    final player = current.setup.players[current.revealIndex];
    final target = current.plan.targetFor(player.id, imposterInfoMode);
    return Padding(
      key: ValueKey<String>(
        'timer-secret-${current.revealIndex}-$showingSecret',
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          PlayerNameBadge(player: player),
          const SizedBox(height: 18),
          Text(
            showingSecret
                ? 'YOUR SECRET INFO'
                : 'PASS TO ${player.name.toUpperCase()}',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 22),
          GradientCard(
            colors: const <Color>[PartyColors.nearBlack, PartyColors.purple],
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 180),
              child: Center(
                child: !showingSecret
                    ? const Icon(Icons.lock, size: 90)
                    : target == null
                    ? const ResponsivePartyText(
                        'IMPOSTER',
                        minFontSize: 44,
                        maxFontSize: 72,
                        maxLines: 1,
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          const Text('YOUR TARGET'),
                          ResponsivePartyText(
                            '${target.toStringAsFixed(2)}s',
                            minFontSize: 48,
                            maxFontSize: 78,
                            maxLines: 1,
                          ),
                          const Text(
                            'Memorize it. Your role will not be revealed.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
              ),
            ),
          ),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: _advanceSecret,
            child: Text(
              !showingSecret
                  ? 'SHOW SECRET INFO'
                  : current.revealIndex + 1 == current.setup.players.length
                  ? 'START PRIVATE TURNS'
                  : 'HIDE & PASS',
            ),
          ),
        ],
      ),
    );
  }

  Widget _handoff() {
    final current = game!;
    final player = _currentPlayer(current);
    return Padding(
      key: ValueKey<String>('timer-handoff-${player.id}'),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          PlayerNameBadge(player: player),
          const SizedBox(height: 18),
          Text(
            'PASS TO ${player.name.toUpperCase()}',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Only this player should hold the phone. Your target and previous times stay hidden.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: _startAttempt,
            icon: const Icon(Icons.play_arrow),
            label: const Text('START TIMER'),
          ),
        ],
      ),
    );
  }

  Widget _running() {
    final player = _currentPlayer(game!);
    return Center(
      key: ValueKey<String>('timer-running-${player.id}'),
      child: Semantics(
        button: true,
        label: 'Stop timer for ${player.name}',
        child: InkWell(
          onTap: _stopAttempt,
          borderRadius: BorderRadius.circular(150),
          child: Ink(
            width: 260,
            height: 260,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: <Color>[PartyColors.yellow, PartyColors.orange],
              ),
            ),
            child: const Center(
              child: Text(
                'STOP!',
                style: TextStyle(
                  color: PartyColors.nearBlack,
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roundResult(AppState app) {
    final current = game!;
    final result = current.roundResults.last;
    if (mode == StopTimerMode.solo) {
      final attempt = result.rankedAttempts.single;
      final error = attempt.absoluteErrorFrom(current.plan.targetSeconds);
      return ListView(
        key: const ValueKey<String>('solo-timer-result'),
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Center(child: StickerBadge(emoji: '🎯', size: 104)),
          const SizedBox(height: 20),
          ResponsivePartyText(
            _rating(error),
            minFontSize: 36,
            maxFontSize: 58,
            maxLines: 2,
          ),
          const SizedBox(height: 18),
          PartyCard(
            child: Column(
              children: <Widget>[
                Text(
                  'Target ${current.plan.targetSeconds.toStringAsFixed(2)}s',
                ),
                Text(
                  'Stopped ${attempt.durationSeconds.toStringAsFixed(2)}s',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text('Error ±${error.toStringAsFixed(2)}s'),
              ],
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: _restartSolo, child: const Text('TRY AGAIN')),
          TextButton(
            onPressed: _returnToMenu,
            child: const Text('CHANGE MODE'),
          ),
        ],
      );
    }

    return ListView(
      key: ValueKey<String>('buzzer-result-${current.plan.number}'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Center(child: StickerBadge(emoji: '🏁', size: 96)),
        const SizedBox(height: 16),
        Text(
          'TARGET ${current.plan.targetSeconds.toStringAsFixed(2)}s',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 14),
        ...result.rankedAttempts.indexed.map((entry) {
          final (index, attempt) = entry;
          final player = _playerById(attempt.playerId);
          final award = result.pointsAwarded[player.id] ?? 0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PartyCard(
              child: ListTile(
                leading: Text(
                  index == 0 ? '🏆' : '#${index + 1}',
                  style: const TextStyle(fontSize: 22),
                ),
                title: Text(player.name),
                subtitle: Text(
                  '${attempt.durationSeconds.toStringAsFixed(2)}s · ${_signedError(attempt.errorFrom(current.plan.targetSeconds))}',
                ),
                trailing: award == 0
                    ? null
                    : PartyStatusPill(
                        label: '+$award PT${award == 1 ? '' : 'S'}',
                        color: PartyColors.yellow,
                      ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        ScoreBoard(players: selected, scores: current.scores),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _continueBuzzer,
          child: Text(
            _engine.matchComplete(current)
                ? 'VIEW FINAL RESULTS'
                : 'NEXT ROUND',
          ),
        ),
      ],
    );
  }

  Widget _voting() => ListView(
    key: const ValueKey<String>('timer-imposter-voting'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      const Center(child: StickerBadge(emoji: '🗳️', size: 96)),
      const SizedBox(height: 20),
      Text(
        'WHO IS AN IMPOSTER?',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displaySmall,
      ),
      const SizedBox(height: 10),
      const Text(
        'Finish your group discussion, then tap one suspect. The choice is final.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 22),
      ...selected.map(
        (Player player) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FilledButton(
            key: ValueKey<String>('timer-vote-${player.id}'),
            onPressed: () => _accuse(player.id),
            child: Text(player.name.toUpperCase()),
          ),
        ),
      ),
    ],
  );

  Widget _finalResult() {
    final current = game!;
    if (mode == StopTimerMode.buzzer) {
      final winners = _engine
          .matchWinnerIds(current)
          .map(_playerById)
          .toList(growable: false);
      return ListView(
        key: const ValueKey<String>('buzzer-final'),
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          const Center(child: StickerBadge(emoji: '🏆', size: 104)),
          const SizedBox(height: 20),
          ResponsivePartyText(
            winners.length == 1
                ? '${winners.single.name.toUpperCase()} WINS'
                : 'CO-WINNERS!',
            minFontSize: 40,
            maxFontSize: 68,
            maxLines: 2,
          ),
          if (winners.length > 1)
            Text(
              winners.map((Player player) => player.name).join(' · '),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 18),
          ScoreBoard(players: selected, scores: current.scores),
          const SizedBox(height: 18),
          FilledButton(onPressed: _startMatch, child: const Text('PLAY AGAIN')),
          OutlinedButton(
            onPressed: _returnToSetup,
            child: const Text('CHANGE SETUP'),
          ),
          TextButton(
            onPressed: () => context.go('/'),
            child: const Text('BACK TO LIBRARY'),
          ),
        ],
      );
    }

    final crewWon = current.outcome == StopTimerOutcome.crew;
    return ListView(
      key: const ValueKey<String>('timer-imposter-result'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Center(child: StickerBadge(emoji: crewWon ? '🏆' : '🎭', size: 104)),
        const SizedBox(height: 20),
        ResponsivePartyText(
          crewWon
              ? 'CREW WINS'
              : current.setup.imposterCount == 1
              ? 'IMPOSTER WINS'
              : 'IMPOSTERS WIN',
          minFontSize: 40,
          maxFontSize: 68,
          maxLines: 2,
        ),
        Text(
          'CREW TARGET · ${current.plan.targetSeconds.toStringAsFixed(2)}s',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (current.plan.falseTargetSeconds != null)
          Text(
            'IMPOSTER TARGET · ${current.plan.falseTargetSeconds!.toStringAsFixed(2)}s',
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 16),
        ...current.plan.playOrder.map((String id) {
          final player = _playerById(id);
          final attempt = current.attempts[id]!;
          final isImposter = current.plan.imposterPlayerIds.contains(id);
          final assigned = current.plan.targetFor(id, imposterInfoMode);
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: PartyCard(
              child: ListTile(
                title: Text(player.name),
                subtitle: Text(
                  '${attempt.durationSeconds.toStringAsFixed(2)}s · ${assigned == null ? 'NO TARGET' : 'TARGET ${assigned.toStringAsFixed(2)}s'}',
                ),
                trailing: Text(isImposter ? 'IMPOSTER' : 'CREW'),
              ),
            ),
          );
        }),
        const SizedBox(height: 10),
        FilledButton(onPressed: _startMatch, child: const Text('PLAY AGAIN')),
        OutlinedButton(
          onPressed: _returnToSetup,
          child: const Text('CHANGE SETUP'),
        ),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('BACK TO LIBRARY'),
        ),
      ],
    );
  }

  void _selectMode(StopTimerMode value) {
    mode = value;
    if (value == StopTimerMode.solo) {
      selected = <Player>[ref.read(appControllerProvider).players.first];
      _startMatch();
      return;
    }
    setState(() {
      selected = List<Player>.from(
        ref
            .read(appControllerProvider)
            .players
            .take(value == StopTimerMode.imposter ? 6 : 4),
      );
      shellPhase = _ShellPhase.setup;
      game = null;
    });
  }

  StopTimerSetup _setupValue() => StopTimerSetup(
    mode: mode,
    players: List<Player>.unmodifiable(selected),
    pointsGoal: pointsGoal,
    imposterCount: imposterCount,
    imposterInfoMode: imposterInfoMode,
  );

  void _startMatch() => setState(() {
    game = _engine.start(_setupValue(), ref.read(randomProvider));
    showingSecret = false;
    shellPhase = _ShellPhase.game;
  });

  void _startNearby() => context.push(
    '/nearby?game=${mode == StopTimerMode.buzzer ? 'timer-buzzer' : 'timer-imposter'}',
    extra: _setupValue(),
  );

  void _hideBuzzerTarget() => setState(() => game = _engine.hideTarget(game!));

  void _startSoloAttempt() {
    game = _engine.hideTarget(game!);
    _startAttempt();
  }

  void _advanceSecret() {
    if (!showingSecret) {
      setState(() => showingSecret = true);
      return;
    }
    setState(() {
      game = _engine.advancePrivateReveal(game!);
      showingSecret = false;
    });
  }

  void _startAttempt() {
    stopwatch
      ..reset()
      ..start();
    unawaited(WakelockPlus.enable());
    setState(() => game = _engine.startAttempt(game!));
  }

  Future<void> _stopAttempt() async {
    if (game?.phase != StopTimerPhase.running) return;
    stopwatch.stop();
    final duration = stopwatch.elapsedMicroseconds / 1000000;
    final updated = _engine.recordAttempt(game!, duration);
    if (mounted) setState(() => game = updated);
    await WakelockPlus.disable();
    if (mode == StopTimerMode.solo) {
      await ref
          .read(appControllerProvider.notifier)
          .recordSoloAttempt(updated.plan.targetSeconds, duration);
    }
  }

  void _continueBuzzer() => setState(() {
    game = _engine.continueAfterRound(game!, ref.read(randomProvider));
  });

  void _restartSolo() => setState(() {
    game = _engine.start(_setupValue(), ref.read(randomProvider));
  });

  void _accuse(String playerId) =>
      setState(() => game = _engine.accuse(game!, playerId));

  void _returnToSetup() => setState(() {
    game = null;
    showingSecret = false;
    shellPhase = _ShellPhase.setup;
  });

  void _returnToMenu() => setState(() {
    game = null;
    showingSecret = false;
    shellPhase = _ShellPhase.menu;
  });

  Player _currentPlayer(StopTimerGameState state) =>
      _playerById(state.currentPlayerId);

  Player _playerById(String id) =>
      selected.firstWhere((Player player) => player.id == id);

  String _modeName(StopTimerMode value) => switch (value) {
    StopTimerMode.solo => 'Solo Training',
    StopTimerMode.buzzer => 'Buzzer Battle',
    StopTimerMode.imposter => 'Timer Imposter',
  };

  String _rating(double error) => switch (ratingForError(error)) {
    SoloRating.unbelievable => 'UNBELIEVABLE! 🎯',
    SoloRating.almostPerfect => 'ALMOST PERFECT! 🔥',
    SoloRating.amazing => 'AMAZING! ⚡',
    SoloRating.great => 'GREAT TIMING! 👍',
    SoloRating.tryAgain => 'TRY AGAIN! ⏳',
  };

  String _signedError(double error) =>
      '${error >= 0 ? '+' : ''}${error.toStringAsFixed(2)}s';
}
