import 'dart:math';

import '../games/stop_timer_engine.dart';

const int nearbyTimerGameVersion = 1;
const Duration nearbyTimerStartLead = Duration(milliseconds: 750);

class TimerClockSample {
  const TimerClockSample({required this.offsetMicros, required this.rttMicros});

  final int offsetMicros;
  final int rttMicros;
}

class NearbyStopTimerSession {
  NearbyStopTimerSession({
    required this.setup,
    required Random random,
    StopTimerGameEngine engine = const StopTimerGameEngine(),
  }) : _engine = engine,
       _random = random,
       game = engine.start(setup, random) {
    if (setup.mode == StopTimerMode.solo) {
      throw ArgumentError('Solo Training does not support Nearby.');
    }
  }

  final StopTimerSetup setup;
  final StopTimerGameEngine _engine;
  final Random _random;
  StopTimerGameState game;
  final Map<String, String> devicePlayers = <String, String>{};
  final Map<String, List<TimerClockSample>> _clockSamples =
      <String, List<TimerClockSample>>{};
  final Set<String> readyPlayerIds = <String>{};
  TimerBallotBox? ballotBox;
  List<String> creatorDecisionCandidates = <String>[];
  int? scheduledStartHostMicros;
  String? activeAttemptId;
  String? endedReason;
  int _attemptSequence = 0;

  List<String> get localPlayerIds => game.setup.players
      .map((player) => player.id)
      .where((String id) => !devicePlayers.containsValue(id))
      .toList(growable: false);

  void assignDevice(String deviceId, String playerId) {
    if (!game.setup.players.any((player) => player.id == playerId)) {
      throw StateError('player_missing');
    }
    if (devicePlayers.entries.any(
      (entry) => entry.key != deviceId && entry.value == playerId,
    )) {
      throw StateError('player_claimed');
    }
    devicePlayers[deviceId] = playerId;
  }

  void recordClockSample({
    required String deviceId,
    required int hostSentMicros,
    required int clientReceivedMicros,
    required int clientSentMicros,
    required int hostReceivedMicros,
  }) {
    final networkRtt = max(
      0,
      (hostReceivedMicros - hostSentMicros) -
          (clientSentMicros - clientReceivedMicros),
    );
    final offset =
        ((clientReceivedMicros - hostSentMicros) +
            (clientSentMicros - hostReceivedMicros)) ~/
        2;
    final samples = _clockSamples.putIfAbsent(
      deviceId,
      () => <TimerClockSample>[],
    );
    samples.add(TimerClockSample(offsetMicros: offset, rttMicros: networkRtt));
    samples.sort(
      (TimerClockSample a, TimerClockSample b) =>
          a.rttMicros.compareTo(b.rttMicros),
    );
    if (samples.length > 5) samples.removeLast();
  }

  bool isCalibrated(String deviceId) =>
      (_clockSamples[deviceId]?.length ?? 0) >= 3;

  int clockSampleCount(String deviceId) => _clockSamples[deviceId]?.length ?? 0;

  int offsetFor(String deviceId) {
    final samples = _clockSamples[deviceId];
    if (samples == null || samples.length < 3) {
      throw StateError('clock_not_calibrated');
    }
    final offsets =
        samples.map((TimerClockSample sample) => sample.offsetMicros).toList()
          ..sort();
    return offsets[offsets.length ~/ 2];
  }

  void markSecretReady(String playerId) {
    if (game.phase != StopTimerPhase.privateReveal ||
        !game.setup.players.any((player) => player.id == playerId)) {
      throw StateError('invalid_ready');
    }
    readyPlayerIds.add(playerId);
    if (game.setup.players.every(
      (player) => readyPlayerIds.contains(player.id),
    )) {
      while (game.phase == StopTimerPhase.privateReveal) {
        game = _engine.advancePrivateReveal(game);
      }
    }
  }

  void beginBuzzerTurns() {
    if (game.setup.mode != StopTimerMode.buzzer) {
      throw StateError('wrong_mode');
    }
    game = _engine.hideTarget(game);
  }

  int scheduleAttempt(String playerId, int hostNowMicros) {
    if (game.phase != StopTimerPhase.handoff ||
        game.currentPlayerId != playerId) {
      throw StateError('not_active_player');
    }
    final deviceId = devicePlayers.entries
        .where((entry) => entry.value == playerId)
        .map((entry) => entry.key)
        .firstOrNull;
    if (deviceId != null && !isCalibrated(deviceId)) {
      throw StateError('clock_not_calibrated');
    }
    game = _engine.startAttempt(game);
    scheduledStartHostMicros =
        hostNowMicros + nearbyTimerStartLead.inMicroseconds;
    activeAttemptId = '${game.plan.number}-$playerId-${++_attemptSequence}';
    return scheduledStartHostMicros!;
  }

  void stopRemoteAttempt({
    required String deviceId,
    required String attemptId,
    required int clientStopMicros,
  }) {
    final playerId = devicePlayers[deviceId];
    if (playerId == null || playerId != game.currentPlayerId) {
      throw StateError('not_active_player');
    }
    final adjustedHostStop = clientStopMicros - offsetFor(deviceId);
    _recordScheduledAttempt(playerId, attemptId, adjustedHostStop);
  }

  void stopHostAttempt({
    required String playerId,
    required String attemptId,
    required int hostStopMicros,
  }) => _recordScheduledAttempt(playerId, attemptId, hostStopMicros);

  void _recordScheduledAttempt(
    String playerId,
    String attemptId,
    int hostStopMicros,
  ) {
    final start = scheduledStartHostMicros;
    if (game.phase != StopTimerPhase.running ||
        game.currentPlayerId != playerId ||
        activeAttemptId != attemptId ||
        start == null) {
      throw StateError('invalid_attempt');
    }
    final elapsed = hostStopMicros - start;
    if (elapsed < 0) {
      throw StateError('invalid_attempt_time');
    }
    game = _engine.recordAttempt(game, elapsed / 1000000);
    scheduledStartHostMicros = null;
    activeAttemptId = null;
    if (game.phase == StopTimerPhase.voting) {
      ballotBox = TimerBallotBox(
        voterIds: game.setup.players.map((player) => player.id).toList(),
      );
    }
  }

  void deviceDisconnected(String deviceId) {
    final playerId = devicePlayers[deviceId];
    if (playerId != null &&
        game.phase == StopTimerPhase.running &&
        game.currentPlayerId == playerId) {
      game = _engine.restartInterruptedAttempt(game);
      scheduledStartHostMicros = null;
      activeAttemptId = null;
    }
  }

  void expireDevice(String deviceId) {
    final playerId = devicePlayers.remove(deviceId);
    _clockSamples.remove(deviceId);
    if (playerId == null) return;
    readyPlayerIds.remove(playerId);
    game = _engine.removePlayer(game, playerId);
    if (game.setup.mode == StopTimerMode.buzzer &&
        game.setup.players.length < 2) {
      endedReason = 'Not enough players remain for Buzzer Battle.';
    } else if (game.setup.mode == StopTimerMode.imposter &&
        game.setup.players.length < 3) {
      endedReason = 'Not enough players remain for Timer Imposter.';
    }
    if (game.phase == StopTimerPhase.voting && endedReason == null) {
      _rebuildBallotAfterExpiry(playerId);
    } else if (game.phase == StopTimerPhase.privateReveal &&
        endedReason == null &&
        game.setup.players.every(
          (player) => readyPlayerIds.contains(player.id),
        )) {
      while (game.phase == StopTimerPhase.privateReveal) {
        game = _engine.advancePrivateReveal(game);
      }
    }
  }

  void _rebuildBallotAfterExpiry(String expiredPlayerId) {
    final old = ballotBox;
    if (old == null) return;
    final voters = old.voterIds
        .where((String id) => id != expiredPlayerId)
        .toList(growable: false);
    final candidates = old.candidates
        ?.where((String id) => id != expiredPlayerId)
        .toList(growable: false);
    final replacement = TimerBallotBox(
      voterIds: voters,
      candidates: candidates?.isEmpty == true ? null : candidates,
      runoff: old.runoff,
    );
    for (final vote in old.votes.values) {
      if (vote.voterId != expiredPlayerId &&
          vote.targetPlayerId != expiredPlayerId) {
        replacement.cast(vote.voterId, vote.targetPlayerId);
      }
    }
    ballotBox = replacement;
    _applyVoteResolution(replacement.resolve());
  }

  TimerVoteResolution castVote(String voterId, String targetPlayerId) {
    final box = ballotBox;
    if (game.phase != StopTimerPhase.voting || box == null) {
      throw StateError('wrong_phase');
    }
    if (!box.cast(voterId, targetPlayerId)) {
      throw StateError('invalid_vote');
    }
    final resolution = box.resolve();
    _applyVoteResolution(resolution);
    return resolution;
  }

  void resolveCreator(String playerId) {
    if (!creatorDecisionCandidates.contains(playerId)) {
      throw StateError('invalid_creator_decision');
    }
    game = _engine.accuse(game, playerId);
    creatorDecisionCandidates = <String>[];
    ballotBox = null;
  }

  void _applyVoteResolution(TimerVoteResolution resolution) {
    if (resolution.suspectPlayerId != null) {
      game = _engine.accuse(game, resolution.suspectPlayerId!);
      ballotBox = null;
    } else if (resolution.runoffCandidates.isNotEmpty) {
      if (resolution.creatorDecisionRequired) {
        creatorDecisionCandidates = resolution.runoffCandidates;
      } else {
        ballotBox = TimerBallotBox(
          voterIds: game.setup.players.map((player) => player.id).toList(),
          candidates: resolution.runoffCandidates,
          runoff: 1,
        );
      }
    }
  }

  void continueBuzzer() {
    game = _engine.continueAfterRound(game, _random);
  }

  Map<String, dynamic> projectionFor(String deviceId) {
    final playerId = devicePlayers[deviceId];
    final resultVisible =
        game.phase == StopTimerPhase.roundResult ||
        game.phase == StopTimerPhase.finalResult;
    final private = <String, dynamic>{
      'playerId': playerId,
      if (playerId != null) 'ready': readyPlayerIds.contains(playerId),
      if (playerId != null)
        'isActivePlayer':
            game.plan.playOrder.isNotEmpty && game.currentPlayerId == playerId,
      if (playerId != null)
        'hasVoted': ballotBox?.votes.containsKey(playerId) ?? false,
      if (playerId != null) 'clockCalibrated': isCalibrated(deviceId),
    };
    if (game.setup.mode == StopTimerMode.imposter &&
        game.phase == StopTimerPhase.privateReveal &&
        playerId != null) {
      final target = game.plan.targetFor(playerId, game.setup.imposterInfoMode);
      if (target == null) {
        private['isImposter'] = true;
      } else {
        private['targetSeconds'] = target;
      }
    }
    return <String, dynamic>{
      'type': 'stopTimerSnapshot',
      'gameStateVersion': nearbyTimerGameVersion,
      'mode': game.setup.mode.name,
      'phase': game.phase.name,
      'players': game.setup.players.map((player) => player.toJson()).toList(),
      'round': game.plan.number,
      'currentPlayerId': game.plan.playOrder.isEmpty
          ? null
          : game.currentPlayerId,
      'scores': game.scores,
      'pointsGoal': game.setup.pointsGoal,
      'runoffCandidates': ballotBox?.candidates ?? const <String>[],
      'creatorDecisionCandidates': creatorDecisionCandidates,
      'scheduledStartMicros':
          scheduledStartHostMicros == null || !isCalibrated(deviceId)
          ? null
          : scheduledStartHostMicros! + offsetFor(deviceId),
      'activeAttemptId': activeAttemptId,
      'endedReason': endedReason,
      if (game.setup.mode == StopTimerMode.buzzer &&
          (game.phase == StopTimerPhase.targetReveal || resultVisible))
        'targetSeconds': game.plan.targetSeconds,
      if (resultVisible)
        'attempts': game.attempts.values
            .map((TimerAttempt attempt) => attempt.toJson())
            .toList(),
      if (game.phase == StopTimerPhase.roundResult)
        'pointsAwarded': game.roundResults.last.pointsAwarded,
      if (game.setup.mode == StopTimerMode.imposter &&
          game.phase == StopTimerPhase.finalResult) ...<String, dynamic>{
        'outcome': game.outcome?.name,
        'accusedPlayerId': game.accusedPlayerId,
        'targetSeconds': game.plan.targetSeconds,
        'falseTargetSeconds': game.plan.falseTargetSeconds,
        'imposterPlayerIds': game.plan.imposterPlayerIds.toList(),
      },
      'private': private,
    };
  }
}
