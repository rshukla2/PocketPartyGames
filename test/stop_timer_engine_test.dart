import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/features/games/stop_timer_engine.dart';

void main() {
  group('TimerTargetGenerator', () {
    const generator = TimerTargetGenerator();

    test('is seeded, bounded, and produces hundredth-second values', () {
      final first = Random(19);
      final second = Random(19);
      final values = List<double>.generate(
        2000,
        (_) => generator.generate(first),
      );
      expect(
        values,
        List<double>.generate(2000, (_) => generator.generate(second)),
      );
      expect(values.every((value) => value >= .25 && value <= 15), isTrue);
      expect(
        values.every((value) => ((value * 100).round() / 100) == value),
        isTrue,
      );
      expect(values.any((value) => value < 1), isTrue);
      expect(values.any((value) => value >= 10), isTrue);
    });

    test('matches the weighted bands and decreases across 1–5 seconds', () {
      final random = Random(991);
      final bands = List<int>.filled(5, 0);
      final oneToFiveSeconds = List<int>.filled(4, 0);
      for (var index = 0; index < 100000; index++) {
        final value = generator.generate(random);
        final band = value < 1
            ? 0
            : value < 5
            ? 1
            : value < 8
            ? 2
            : value < 10
            ? 3
            : 4;
        bands[band]++;
        if (band == 1) oneToFiveSeconds[value.floor() - 1]++;
      }
      expect(bands[1], greaterThan(bands[2]));
      expect(bands[2], greaterThan(bands[0]));
      expect(bands[0], greaterThan(bands[3]));
      expect(bands[3], greaterThan(bands[4]));
      expect(
        oneToFiveSeconds,
        orderedEquals(List<int>.from(oneToFiveSeconds)..sort((a, b) => b - a)),
      );
    });

    test('related target stays in range and exactly 2–3 seconds away', () {
      for (final crew in <double>[.25, 1, 7.5, 14, 15]) {
        final alternate = generator.relatedTarget(crew, Random(7));
        expect(alternate, inInclusiveRange(.25, 15));
        expect((alternate - crew).abs(), inInclusiveRange(2, 3));
      }
    });
  });

  group('StopTimerGameEngine', () {
    const engine = StopTimerGameEngine(
      targetGenerator: _FixedTargetGenerator(),
    );
    final players = _players(4);

    test('setup JSON preserves every timer option', () {
      final setup = StopTimerSetup(
        mode: StopTimerMode.imposter,
        players: players,
        pointsGoal: 9,
        imposterCount: 2,
        imposterInfoMode: TimerImposterInfoMode.noTarget,
      );
      final restored = StopTimerSetup.fromJson(setup.toJson());
      expect(restored.mode, setup.mode);
      expect(restored.players.map((player) => player.id), <String>[
        'p0',
        'p1',
        'p2',
        'p3',
      ]);
      expect(restored.pointsGoal, 9);
      expect(restored.imposterCount, 2);
      expect(restored.imposterInfoMode, TimerImposterInfoMode.noTarget);
    });

    test('Buzzer runs one private attempt per player and scores closest', () {
      var state = engine.start(
        StopTimerSetup(mode: StopTimerMode.buzzer, players: players),
        Random(4),
      );
      expect(state.phase, StopTimerPhase.targetReveal);
      expect(
        state.plan.playOrder.toSet(),
        players.map((player) => player.id).toSet(),
      );
      state = engine.hideTarget(state);
      final durations = <double>[4.8, 5.004, 5.2, 7];
      for (var index = 0; index < players.length; index++) {
        state = engine.startAttempt(state);
        state = engine.recordAttempt(state, durations[index]);
      }
      expect(state.phase, StopTimerPhase.roundResult);
      expect(state.attempts, hasLength(4));
      final winner = state.roundResults.single.rankedAttempts.first.playerId;
      expect(state.scores[winner], 2);
      expect(state.scores.values.where((score) => score > 0), hasLength(1));
    });

    test('equal closest errors share points and can produce co-winners', () {
      const plan = TimerRoundPlan(
        number: 1,
        targetSeconds: 5,
        playOrder: <String>['a', 'b'],
      );
      final result = engine.scoreBuzzerRound(plan, const <TimerAttempt>[
        TimerAttempt(playerId: 'a', durationSeconds: 4.9),
        TimerAttempt(playerId: 'b', durationSeconds: 5.1),
      ]);
      expect(result.pointsAwarded, <String, int>{'a': 1, 'b': 1});
    });

    test('Buzzer continues until the first-to goal is reached', () {
      var state = engine.start(
        StopTimerSetup(
          mode: StopTimerMode.buzzer,
          players: players.take(2).toList(),
          pointsGoal: 3,
        ),
        Random(1),
      );
      for (var round = 0; round < 3; round++) {
        state = engine.hideTarget(state);
        for (var index = 0; index < 2; index++) {
          state = engine.startAttempt(state);
          state = engine.recordAttempt(
            state,
            state.currentPlayerId == 'p0' ? 5.2 : 8,
          );
        }
        state = engine.continueAfterRound(state, Random(round + 2));
      }
      expect(state.phase, StopTimerPhase.finalResult);
      expect(engine.matchComplete(state), isTrue);
      expect(engine.matchWinnerIds(state), hasLength(1));
    });

    test('False Target gives every imposter one shared neutral target', () {
      final fivePlayers = _players(5);
      final state = engine.start(
        StopTimerSetup(
          mode: StopTimerMode.imposter,
          players: fivePlayers,
          imposterCount: 2,
        ),
        Random(8),
      );
      expect(state.plan.imposterPlayerIds, hasLength(2));
      expect(state.plan.falseTargetSeconds, 7.25);
      for (final id in state.plan.imposterPlayerIds) {
        expect(
          state.plan.targetFor(id, TimerImposterInfoMode.falseTarget),
          7.25,
        );
      }
    });

    test(
      'No Target gives imposters null and one accusation decides outcome',
      () {
        final fivePlayers = _players(5);
        var state = engine.start(
          StopTimerSetup(
            mode: StopTimerMode.imposter,
            players: fivePlayers,
            imposterCount: 2,
            imposterInfoMode: TimerImposterInfoMode.noTarget,
          ),
          Random(9),
        );
        final imposter = state.plan.imposterPlayerIds.first;
        expect(
          state.plan.targetFor(imposter, TimerImposterInfoMode.noTarget),
          isNull,
        );
        for (var index = 0; index < fivePlayers.length; index++) {
          state = engine.advancePrivateReveal(state);
        }
        for (var index = 0; index < fivePlayers.length; index++) {
          state = engine.startAttempt(state);
          state = engine.recordAttempt(state, index + 1);
        }
        expect(state.phase, StopTimerPhase.voting);
        state = engine.accuse(state, imposter);
        expect(state.phase, StopTimerPhase.finalResult);
        expect(state.outcome, StopTimerOutcome.crew);
      },
    );

    test('imposter count preserves a Crew majority for 3–20 players', () {
      for (var count = 3; count <= 20; count++) {
        final roster = _players(count);
        final maximum = (count - 1) ~/ 2;
        expect(
          () => engine.start(
            StopTimerSetup(
              mode: StopTimerMode.imposter,
              players: roster,
              imposterCount: maximum,
            ),
            Random(count),
          ),
          returnsNormally,
        );
        expect(
          () => engine.start(
            StopTimerSetup(
              mode: StopTimerMode.imposter,
              players: roster,
              imposterCount: maximum + 1,
            ),
            Random(count),
          ),
          throwsArgumentError,
        );
      }
    });
  });
}

class _FixedTargetGenerator extends TimerTargetGenerator {
  const _FixedTargetGenerator();

  @override
  double generate(Random random) => 5;

  @override
  double relatedTarget(double crewTarget, Random random) => 7.25;
}

List<Player> _players(int count) => List<Player>.generate(
  count,
  (int index) =>
      Player(id: 'p$index', name: 'Player ${index + 1}', colorIndex: index % 8),
);
