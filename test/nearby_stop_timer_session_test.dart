import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/features/games/stop_timer_engine.dart';
import 'package:pocket_party_games/features/nearby/nearby_stop_timer_session.dart';

void main() {
  const engine = StopTimerGameEngine(targetGenerator: _FixedTargetGenerator());

  test('clock calibration uses the median of low-RTT samples', () {
    final session = NearbyStopTimerSession(
      setup: StopTimerSetup(mode: StopTimerMode.buzzer, players: _players(2)),
      random: Random(1),
      engine: engine,
    );
    session.assignDevice('d0', 'p0');
    for (var index = 0; index < 5; index++) {
      _calibrate(session, 'd0', offset: 5000, base: 1000000 + index * 10000);
    }
    expect(session.isCalibrated('d0'), isTrue);
    expect(session.offsetFor('d0'), 5000);
    session.beginBuzzerTurns();
    final scheduled = session.scheduleAttempt(
      session.game.currentPlayerId,
      2000000,
    );
    expect(
      session.projectionFor('d0')['scheduledStartMicros'],
      scheduled + 5000,
    );
    expect(
      session.projectionFor('d0'),
      isNot(contains('scheduledStartHostMicros')),
    );
  });

  test('session rejects unsupported modes, assignments, and early actions', () {
    expect(
      () => NearbyStopTimerSession(
        setup: StopTimerSetup(mode: StopTimerMode.solo, players: _players(1)),
        random: Random(1),
        engine: engine,
      ),
      throwsArgumentError,
    );
    final session = NearbyStopTimerSession(
      setup: StopTimerSetup(mode: StopTimerMode.buzzer, players: _players(3)),
      random: Random(12),
      engine: engine,
    );
    expect(session.localPlayerIds, hasLength(3));
    expect(session.clockSampleCount('missing'), 0);
    expect(() => session.offsetFor('missing'), throwsStateError);
    expect(() => session.assignDevice('d0', 'missing'), throwsStateError);
    session.assignDevice('d0', 'p0');
    expect(session.localPlayerIds, hasLength(2));
    expect(() => session.assignDevice('d1', 'p0'), throwsStateError);
    expect(() => session.markSecretReady('p0'), throwsStateError);
    session.assignDevice('d1', 'p1');
    session.assignDevice('d2', 'p2');
    expect(
      () => session.scheduleAttempt(session.game.currentPlayerId, 1000000),
      throwsStateError,
    );
    session.beginBuzzerTurns();
    expect(
      () => session.scheduleAttempt(session.game.currentPlayerId, 1000000),
      throwsStateError,
    );

    final timer = NearbyStopTimerSession(
      setup: StopTimerSetup(mode: StopTimerMode.imposter, players: _players(3)),
      random: Random(13),
      engine: engine,
    );
    expect(timer.beginBuzzerTurns, throwsStateError);
  });

  test('Buzzer hides attempts until every scheduled turn is complete', () {
    final players = _players(3);
    final session = NearbyStopTimerSession(
      setup: StopTimerSetup(mode: StopTimerMode.buzzer, players: players),
      random: Random(2),
      engine: engine,
    );
    for (var index = 0; index < players.length; index++) {
      session.assignDevice('d$index', players[index].id);
      for (var sample = 0; sample < 3; sample++) {
        _calibrate(
          session,
          'd$index',
          offset: 1000 * (index + 1),
          base: 1000000 + sample * 10000,
        );
      }
    }
    expect(session.projectionFor('d0')['targetSeconds'], 5.0);
    session.beginBuzzerTurns();
    expect(session.projectionFor('d0'), isNot(contains('targetSeconds')));

    var hostNow = 2000000;
    while (session.game.phase != StopTimerPhase.roundResult) {
      final playerId = session.game.currentPlayerId;
      final deviceId = session.devicePlayers.entries
          .firstWhere((entry) => entry.value == playerId)
          .key;
      final scheduled = session.scheduleAttempt(playerId, hostNow);
      final offset = session.offsetFor(deviceId);
      session.stopRemoteAttempt(
        deviceId: deviceId,
        attemptId: session.activeAttemptId!,
        clientStopMicros: scheduled + 5000000 + offset,
      );
      hostNow += 7000000;
      if (session.game.phase != StopTimerPhase.roundResult) {
        expect(session.projectionFor('d0'), isNot(contains('attempts')));
      }
    }
    final result = session.projectionFor('d0');
    expect(result['attempts'], hasLength(3));
    expect(result['pointsAwarded'], isNotEmpty);
  });

  test('twenty simulated Buzzer clients complete one authoritative round', () {
    final players = _players(20);
    final session = NearbyStopTimerSession(
      setup: StopTimerSetup(mode: StopTimerMode.buzzer, players: players),
      random: Random(20),
      engine: engine,
    );
    for (var index = 0; index < players.length; index++) {
      session.assignDevice('d$index', players[index].id);
      for (var sample = 0; sample < 3; sample++) {
        _calibrate(
          session,
          'd$index',
          offset: index * 100,
          base: 1000000 + sample * 10000,
        );
      }
    }
    session.beginBuzzerTurns();
    var hostNow = 2000000;
    while (session.game.phase != StopTimerPhase.roundResult) {
      final playerId = session.game.currentPlayerId;
      final device = session.devicePlayers.entries
          .firstWhere((entry) => entry.value == playerId)
          .key;
      final scheduled = session.scheduleAttempt(playerId, hostNow);
      session.stopRemoteAttempt(
        deviceId: device,
        attemptId: session.activeAttemptId!,
        clientStopMicros: scheduled + 5000000 + session.offsetFor(device),
      );
      hostNow += 7000000;
    }
    expect(session.game.attempts, hasLength(20));
    expect(session.game.roundResults.single.winnerIds, hasLength(20));
  });

  test('host attempts validate timestamps and Buzzer can continue', () {
    final session = NearbyStopTimerSession(
      setup: StopTimerSetup(mode: StopTimerMode.buzzer, players: _players(2)),
      random: Random(14),
      engine: engine,
    );
    session.beginBuzzerTurns();
    while (session.game.phase != StopTimerPhase.roundResult) {
      final playerId = session.game.currentPlayerId;
      final scheduled = session.scheduleAttempt(playerId, 1000000);
      expect(
        () => session.stopHostAttempt(
          playerId: playerId,
          attemptId: 'wrong',
          hostStopMicros: scheduled,
        ),
        throwsStateError,
      );
      expect(
        () => session.stopHostAttempt(
          playerId: playerId,
          attemptId: session.activeAttemptId!,
          hostStopMicros: scheduled - 1,
        ),
        throwsStateError,
      );
      session.stopHostAttempt(
        playerId: playerId,
        attemptId: session.activeAttemptId!,
        hostStopMicros: scheduled + 5000000,
      );
    }
    session.continueBuzzer();
    expect(session.game.phase, StopTimerPhase.targetReveal);
  });

  test('False Target projections never reveal role or another secret', () {
    final players = _players(5);
    final session = NearbyStopTimerSession(
      setup: StopTimerSetup(
        mode: StopTimerMode.imposter,
        players: players,
        imposterCount: 2,
      ),
      random: Random(4),
      engine: engine,
    );
    for (var index = 0; index < players.length; index++) {
      session.assignDevice('d$index', players[index].id);
    }
    final imposterId = session.game.plan.imposterPlayerIds.first;
    final device = session.devicePlayers.entries
        .firstWhere((entry) => entry.value == imposterId)
        .key;
    final projection = session.projectionFor(device);
    final private = Map<String, dynamic>.from(projection['private'] as Map);
    expect(private, isNot(contains('isImposter')));
    expect(private['targetSeconds'], 7.25);
    expect(projection.toString(), isNot(contains('imposterPlayerIds')));
    expect(projection.toString(), isNot(contains('5.0')));
  });

  test('No Target reveals only IMPOSTER to the assigned recipient', () {
    final players = _players(5);
    final session = NearbyStopTimerSession(
      setup: StopTimerSetup(
        mode: StopTimerMode.imposter,
        players: players,
        imposterCount: 2,
        imposterInfoMode: TimerImposterInfoMode.noTarget,
      ),
      random: Random(5),
      engine: engine,
    );
    for (var index = 0; index < players.length; index++) {
      session.assignDevice('d$index', players[index].id);
    }
    final imposterId = session.game.plan.imposterPlayerIds.first;
    final imposterDevice = session.devicePlayers.entries
        .firstWhere((entry) => entry.value == imposterId)
        .key;
    final private = Map<String, dynamic>.from(
      session.projectionFor(imposterDevice)['private'] as Map,
    );
    expect(private['isImposter'], isTrue);
    expect(private, isNot(contains('targetSeconds')));
  });

  test('twenty simulated Timer Imposter clients reveal, play, and vote', () {
    final players = _players(20);
    final session = NearbyStopTimerSession(
      setup: StopTimerSetup(
        mode: StopTimerMode.imposter,
        players: players,
        imposterCount: 9,
      ),
      random: Random(21),
      engine: engine,
    );
    for (var index = 0; index < players.length; index++) {
      session.assignDevice('d$index', players[index].id);
      for (var sample = 0; sample < 3; sample++) {
        _calibrate(
          session,
          'd$index',
          offset: index * 100,
          base: 1000000 + sample * 10000,
        );
      }
      session.markSecretReady(players[index].id);
    }
    var hostNow = 2000000;
    while (session.game.phase != StopTimerPhase.voting) {
      final playerId = session.game.currentPlayerId;
      final device = session.devicePlayers.entries
          .firstWhere((entry) => entry.value == playerId)
          .key;
      final scheduled = session.scheduleAttempt(playerId, hostNow);
      session.stopRemoteAttempt(
        deviceId: device,
        attemptId: session.activeAttemptId!,
        clientStopMicros: scheduled + 5000000 + session.offsetFor(device),
      );
      hostNow += 7000000;
    }
    for (final player in players) {
      session.castVote(player.id, player.id == 'p0' ? 'p1' : 'p0');
    }
    expect(session.game.phase, StopTimerPhase.finalResult);
    expect(session.game.attempts, hasLength(20));
    expect(session.game.accusedPlayerId, 'p0');
  });

  test(
    'Timer voting is private, rejects self votes, and picks one suspect',
    () {
      final session = _readyTimerSession(engine);
      final players = session.game.setup.players;
      final suspect = players.first.id;
      for (final player in players) {
        final target = player.id == suspect ? players[1].id : suspect;
        session.castVote(player.id, target);
        if (session.game.phase == StopTimerPhase.voting) {
          expect(
            session.projectionFor('d2').toString(),
            isNot(contains('votes')),
          );
        }
      }
      expect(session.game.phase, StopTimerPhase.finalResult);
      expect(session.game.accusedPlayerId, suspect);
      final result = session.projectionFor('d2');
      expect(result['outcome'], isNotNull);
      expect(result['imposterPlayerIds'], isNotEmpty);
      expect(result['accusedPlayerId'], suspect);
    },
  );

  test('a tied ballot runs once and then requires the creator', () {
    final session = _readyTimerSession(engine, playerCount: 4);
    session.castVote('p0', 'p1');
    session.castVote('p1', 'p0');
    session.castVote('p2', 'p1');
    final firstTie = session.castVote('p3', 'p0');
    expect(firstTie.runoffCandidates, containsAll(<String>['p0', 'p1']));
    expect(session.ballotBox?.runoff, 1);

    session.castVote('p0', 'p1');
    session.castVote('p1', 'p0');
    session.castVote('p2', 'p0');
    final secondTie = session.castVote('p3', 'p1');
    expect(secondTie.creatorDecisionRequired, isTrue);
    expect(
      session.creatorDecisionCandidates,
      containsAll(<String>['p0', 'p1']),
    );
    expect(() => session.resolveCreator('p3'), throwsStateError);
    session.resolveCreator('p0');
    expect(session.game.phase, StopTimerPhase.finalResult);
  });

  test('expiry during voting removes stale ballots before tallying', () {
    final session = _readyTimerSession(engine);
    session.castVote('p0', 'p1');
    session.castVote('p1', 'p0');

    session.expireDevice('d4');

    expect(session.game.setup.players, hasLength(4));
    expect(session.ballotBox?.voterIds, isNot(contains('p4')));
    expect(session.ballotBox?.votes, hasLength(2));
  });

  test('an interrupted remote attempt restarts at its handoff', () {
    final players = _players(2);
    final session = NearbyStopTimerSession(
      setup: StopTimerSetup(mode: StopTimerMode.buzzer, players: players),
      random: Random(7),
      engine: engine,
    );
    for (var index = 0; index < 2; index++) {
      session.assignDevice('d$index', players[index].id);
      for (var sample = 0; sample < 3; sample++) {
        _calibrate(session, 'd$index', offset: 0, base: sample * 10000);
      }
    }
    session.beginBuzzerTurns();
    final activeDevice = session.devicePlayers.entries
        .firstWhere((entry) => entry.value == session.game.currentPlayerId)
        .key;
    session.scheduleAttempt(session.game.currentPlayerId, 1000000);
    session.deviceDisconnected(activeDevice);
    expect(session.game.phase, StopTimerPhase.handoff);
    expect(session.activeAttemptId, isNull);
    expect(session.game.attempts, isEmpty);
  });

  test('expired devices are removed and too-small rooms end gracefully', () {
    final players = _players(3);
    final session = NearbyStopTimerSession(
      setup: StopTimerSetup(mode: StopTimerMode.buzzer, players: players),
      random: Random(8),
      engine: engine,
    );
    for (var index = 0; index < players.length; index++) {
      session.assignDevice('d$index', players[index].id);
    }
    session.expireDevice('d0');
    expect(session.game.setup.players, hasLength(2));
    expect(session.endedReason, isNull);
    session.expireDevice('d1');
    expect(session.endedReason, contains('Not enough players'));
    expect(session.game.phase, StopTimerPhase.finalResult);
  });

  test('private reveal advances when an unready remote player expires', () {
    final players = _players(4);
    final session = NearbyStopTimerSession(
      setup: StopTimerSetup(mode: StopTimerMode.imposter, players: players),
      random: Random(9),
      engine: engine,
    );
    for (var index = 0; index < players.length; index++) {
      session.assignDevice('d$index', players[index].id);
    }
    for (final player in players.take(3)) {
      session.markSecretReady(player.id);
    }
    expect(session.game.phase, StopTimerPhase.privateReveal);

    session.expireDevice('d3');

    expect(session.game.phase, StopTimerPhase.handoff);
  });
}

NearbyStopTimerSession _readyTimerSession(
  StopTimerGameEngine engine, {
  int playerCount = 5,
}) {
  final players = _players(playerCount);
  final session = NearbyStopTimerSession(
    setup: StopTimerSetup(
      mode: StopTimerMode.imposter,
      players: players,
      imposterCount: min(2, (players.length - 1) ~/ 2),
    ),
    random: Random(6),
    engine: engine,
  );
  for (var index = 0; index < players.length; index++) {
    session.assignDevice('d$index', players[index].id);
    for (var sample = 0; sample < 3; sample++) {
      _calibrate(session, 'd$index', offset: 0, base: sample * 10000);
    }
    session.markSecretReady(players[index].id);
  }
  var hostNow = 1000000;
  while (session.game.phase != StopTimerPhase.voting) {
    final playerId = session.game.currentPlayerId;
    final device = session.devicePlayers.entries
        .firstWhere((entry) => entry.value == playerId)
        .key;
    final scheduled = session.scheduleAttempt(playerId, hostNow);
    session.stopRemoteAttempt(
      deviceId: device,
      attemptId: session.activeAttemptId!,
      clientStopMicros: scheduled + 5000000,
    );
    hostNow += 7000000;
  }
  return session;
}

void _calibrate(
  NearbyStopTimerSession session,
  String deviceId, {
  required int offset,
  required int base,
}) {
  session.recordClockSample(
    deviceId: deviceId,
    hostSentMicros: base,
    clientReceivedMicros: base + offset + 1000,
    clientSentMicros: base + offset + 1100,
    hostReceivedMicros: base + 2100,
  );
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
