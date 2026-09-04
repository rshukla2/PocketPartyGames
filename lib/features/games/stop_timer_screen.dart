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

enum _Mode { solo, buzzer, imposter }

enum _Phase { menu, setup, reveal, ready, running, result, finalResult }

class StopTimerScreen extends ConsumerStatefulWidget {
  const StopTimerScreen({super.key});
  @override
  ConsumerState<StopTimerScreen> createState() => _StopTimerScreenState();
}

class _StopTimerScreenState extends ConsumerState<StopTimerScreen> {
  _Phase phase = _Phase.menu;
  _Mode mode = _Mode.solo;
  List<Player> selected = <Player>[];
  int totalRounds = 5;
  int round = 1;
  double target = 8;
  double falseTarget = 12;
  String imposterId = '';
  int revealIndex = 0;
  bool showingRole = false;
  final stopwatch = Stopwatch();
  final results = <String, double>{};
  final scores = <String, int>{};
  Timer? repaintTimer;

  @override
  void dispose() {
    repaintTimer?.cancel();
    WakelockPlus.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = ref.watch(appControllerProvider);
    if (selected.isEmpty) selected = List<Player>.from(app.players.take(4));
    return PopScope(
      canPop: phase == _Phase.menu || phase == _Phase.setup,
      onPopInvokedWithResult: (bool didPop, Object? result) async {
        if (!didPop && await confirmLeaveGame(context) && context.mounted) {
          context.pop();
        }
      },
      child: PartyPage(
        title: 'Stop the Timer',
        style: PartyGameStyle.stopTimer,
        tone: switch (phase) {
          _Phase.reveal => PartyScreenTone.secret,
          _Phase.running => PartyScreenTone.action,
          _Phase.result || _Phase.finalResult => PartyScreenTone.success,
          _ => PartyScreenTone.standard,
        },
        subtitle: _subtitle,
        child: PartyPhaseSwitcher(child: _content(app)),
      ),
    );
  }

  String get _subtitle => switch (phase) {
    _Phase.menu => 'Precision timing showdown',
    _Phase.setup => '${_modeName(mode)} setup',
    _Phase.reveal => 'Private target reveal',
    _Phase.ready => 'Round $round of $totalRounds',
    _Phase.running => '${results.length}/${selected.length} stopped',
    _Phase.result => 'Round $round results',
    _Phase.finalResult => 'Final podium',
  };

  Widget _content(AppState app) => switch (phase) {
    _Phase.menu => _menu(),
    _Phase.setup => _setup(app),
    _Phase.reveal => _reveal(),
    _Phase.ready => _ready(app),
    _Phase.running => _running(app),
    _Phase.result => _result(app),
    _Phase.finalResult => _final(app),
  };

  Widget _menu() => ListView(
    key: const ValueKey<String>('timer-menu'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      _modeCard(
        _Mode.solo,
        '🎯',
        'SOLO TRAINING',
        'Memorize a hidden target and stop with millisecond precision.',
      ),
      _modeCard(
        _Mode.buzzer,
        '🚨',
        'BUZZER BATTLE',
        'Everyone gets a button. Closest to the target earns 3 points.',
      ),
      _modeCard(
        _Mode.imposter,
        '🕵️',
        'TIMER IMPOSTER',
        'One player secretly receives a different target time.',
      ),
    ],
  );

  Widget _modeCard(_Mode value, String emoji, String title, String body) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: GradientCard(
          colors: value == _Mode.solo
              ? const <Color>[PartyColors.yellow, PartyColors.orange]
              : value == _Mode.buzzer
              ? const <Color>[PartyColors.coral, PartyColors.pink]
              : const <Color>[PartyColors.purple, PartyColors.blue],
          onTap: () => setState(() {
            mode = value;
            phase = value == _Mode.solo ? _Phase.ready : _Phase.setup;
            totalRounds = value == _Mode.solo ? 1 : 5;
            round = 1;
            _newTarget();
          }),
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

  Widget _setup(AppState app) => ListView(
    key: const ValueKey<String>('timer-setup'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      Text('Players', style: Theme.of(context).textTheme.titleLarge),
      PlayerChips(
        players: app.players,
        minimum: mode == _Mode.imposter ? 3 : 2,
        onChanged: (List<Player> value) => setState(() => selected = value),
      ),
      if (mode == _Mode.buzzer) ...<Widget>[
        const SizedBox(height: 18),
        Text('Rounds: $totalRounds'),
        PartySlider(
          value: totalRounds.toDouble(),
          min: 3,
          max: 10,
          divisions: 7,
          label: '$totalRounds',
          onChanged: (double value) =>
              setState(() => totalRounds = value.round()),
        ),
      ],
      const SizedBox(height: 24),
      FilledButton.icon(
        onPressed: _startMatch,
        icon: const Icon(Icons.play_arrow),
        label: const Text('START MATCH'),
      ),
      if (!kIsWeb) ...<Widget>[
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: () => context.push(
            '/nearby',
            extra: mode == _Mode.buzzer ? 'timer-buzzer' : 'timer-imposter',
          ),
          icon: const Icon(Icons.wifi_tethering),
          label: const Text('USE NEARBY PHONES'),
        ),
      ],
    ],
  );

  Widget _reveal() {
    final player = selected[revealIndex];
    final shownTarget = player.id == imposterId ? falseTarget : target;
    return Padding(
      key: ValueKey<String>('timer-reveal-$revealIndex-$showingRole'),
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          PlayerNameBadge(player: player),
          const SizedBox(height: 14),
          Text(
            showingRole
                ? 'YOUR TARGET'
                : 'PASS TO ${player.name.toUpperCase()}',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (showingRole)
            ResponsivePartyText(
              '${shownTarget.toStringAsFixed(2)}s',
              minFontSize: 52,
              maxFontSize: 84,
              maxLines: 1,
            )
          else
            const Icon(Icons.lock, size: 100),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: () {
              if (!showingRole) {
                setState(() => showingRole = true);
              } else if (revealIndex + 1 < selected.length) {
                setState(() {
                  revealIndex++;
                  showingRole = false;
                });
              } else {
                setState(() => phase = _Phase.ready);
              }
            },
            child: Text(
              showingRole
                  ? (revealIndex + 1 == selected.length
                        ? 'READY TO PLAY'
                        : 'HIDE & PASS')
                  : 'SHOW TARGET',
            ),
          ),
        ],
      ),
    );
  }

  Widget _ready(AppState app) => Padding(
    key: ValueKey<String>('timer-ready-$round-$target'),
    padding: const EdgeInsets.all(18),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const Text(
          'TARGET TIME',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2),
        ),
        const SizedBox(height: 8),
        ResponsivePartyText(
          '${target.toStringAsFixed(2)}s',
          minFontSize: 54,
          maxFontSize: 90,
          maxLines: 1,
        ),
        if (mode == _Mode.solo) ...<Widget>[
          Text(
            '${app.soloStats.attempts} attempts · Best ${app.soloStats.bestErrorMs == null ? '—' : '±${(app.soloStats.bestErrorMs! / 1000).toStringAsFixed(2)}s'}',
          ),
        ],
        const SizedBox(height: 24),
        const Text(
          'Memorize the target. The clock disappears when you start.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 26),
        FilledButton.icon(
          onPressed: _begin,
          icon: const Icon(Icons.play_arrow),
          label: const Text('START TIMER'),
        ),
      ],
    ),
  );

  Widget _running(AppState app) {
    if (mode == _Mode.solo) {
      return Center(
        key: const ValueKey<String>('solo-running'),
        child: Semantics(
          button: true,
          label: 'Stop timer',
          child: InkWell(
            onTap: () => _stop(app.players.first.id),
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
    return GridView.count(
      key: ValueKey<int>(results.length),
      padding: const EdgeInsets.all(16),
      crossAxisCount: selected.length <= 4 ? 2 : 3,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: selected.map((Player player) {
        final stopped = results.containsKey(player.id);
        return FilledButton(
          onPressed: stopped ? null : () => _stop(player.id),
          style: FilledButton.styleFrom(
            backgroundColor: PartyColors.playerColors[player.colorIndex % 8],
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              PlayerNameBadge(player: player, compact: true),
              const SizedBox(height: 8),
              Text(
                stopped ? 'STOPPED' : player.name,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _result(AppState app) {
    final ranked =
        selected
            .where((Player player) => results.containsKey(player.id))
            .toList()
          ..sort(
            (Player a, Player b) => (results[a.id]! - target).abs().compareTo(
              (results[b.id]! - target).abs(),
            ),
          );
    return ListView(
      key: ValueKey<String>('timer-result-$round'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (mode == _Mode.imposter)
          Text(
            'The real target was ${target.toStringAsFixed(2)}s',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ...ranked.indexed.map((item) {
          final (index, player) = item;
          final actual = results[player.id]!;
          return PartyCard(
            child: ListTile(
              leading: Text(
                index == 0 ? '🏆' : '#${index + 1}',
                style: const TextStyle(fontSize: 22),
              ),
              title: Text(player.name),
              subtitle: Text(
                '${actual.toStringAsFixed(2)}s · ${(actual - target) >= 0 ? '+' : ''}${(actual - target).toStringAsFixed(2)}s',
              ),
              trailing: mode == _Mode.imposter && player.id == imposterId
                  ? const Text('IMPOSTER')
                  : null,
            ),
          );
        }),
        if (mode == _Mode.solo && ranked.isNotEmpty)
          Text(
            _rating((results[ranked.first.id]! - target).abs()),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _next,
          child: Text(
            mode == _Mode.solo
                ? 'TRY AGAIN'
                : round >= totalRounds
                ? 'VIEW FINAL PODIUM'
                : 'NEXT ROUND',
          ),
        ),
      ],
    );
  }

  Widget _final(AppState app) => ListView(
    key: const ValueKey<String>('timer-final'),
    padding: const EdgeInsets.all(16),
    children: <Widget>[
      const Center(child: StickerBadge(emoji: '🏆', size: 104)),
      const SizedBox(height: 22),
      ScoreBoard(players: selected, scores: scores),
      FilledButton(onPressed: _startMatch, child: const Text('PLAY AGAIN')),
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

  void _startMatch() {
    scores
      ..clear()
      ..addEntries(
        selected.map((Player player) => MapEntry<String, int>(player.id, 0)),
      );
    round = 1;
    _newTarget();
    setState(() {
      if (mode == _Mode.imposter) {
        final random = ref.read(randomProvider);
        imposterId = selected[random.nextInt(selected.length)].id;
        falseTarget = max(3, target + (random.nextBool() ? 4 : -3.5));
        revealIndex = 0;
        showingRole = false;
        phase = _Phase.reveal;
      } else {
        phase = _Phase.ready;
      }
    });
  }

  void _newTarget() =>
      target = (400 + ref.read(randomProvider).nextInt(1001)) / 100;

  void _begin() {
    results.clear();
    stopwatch
      ..reset()
      ..start();
    WakelockPlus.enable();
    repaintTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && phase == _Phase.running) setState(() {});
    });
    setState(() => phase = _Phase.running);
  }

  Future<void> _stop(String id) async {
    if (results.containsKey(id) || phase != _Phase.running) return;
    results[id] = stopwatch.elapsedMicroseconds / 1000000;
    final required = mode == _Mode.solo ? 1 : selected.length;
    if (results.length >= required) {
      stopwatch.stop();
      repaintTimer?.cancel();
      await WakelockPlus.disable();
      if (mode == _Mode.solo) {
        await ref
            .read(appControllerProvider.notifier)
            .recordSoloAttempt(target, results[id]!);
      } else {
        final ranked = List<Player>.from(selected)
          ..sort(
            (Player a, Player b) => (results[a.id]! - target).abs().compareTo(
              (results[b.id]! - target).abs(),
            ),
          );
        for (var index = 0; index < min(3, ranked.length); index++) {
          scores[ranked[index].id] =
              (scores[ranked[index].id] ?? 0) + (3 - index);
        }
      }
      if (mounted) setState(() => phase = _Phase.result);
    } else {
      setState(() {});
    }
  }

  void _next() {
    if (mode == _Mode.solo) {
      _newTarget();
      setState(() => phase = _Phase.ready);
    } else if (round >= totalRounds) {
      setState(() => phase = _Phase.finalResult);
    } else {
      round++;
      _newTarget();
      setState(() => phase = _Phase.ready);
    }
  }

  String _modeName(_Mode value) => switch (value) {
    _Mode.solo => 'Solo',
    _Mode.buzzer => 'Buzzer Battle',
    _Mode.imposter => 'Timer Imposter',
  };
  String _rating(double error) => error <= .05
      ? 'Unbelievable! 🎯'
      : error <= .10
      ? 'Almost perfect! 🔥'
      : error <= .25
      ? 'Amazing! ⚡'
      : error <= .50
      ? 'Great timing! 👍'
      : 'Try again! ⏳';
}
