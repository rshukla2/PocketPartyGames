import 'dart:math';

import '../../core/models/app_models.dart';

enum StopTimerMode { solo, buzzer, imposter }

enum TimerImposterInfoMode { falseTarget, noTarget }

enum StopTimerPhase {
  targetReveal,
  privateReveal,
  handoff,
  running,
  roundResult,
  voting,
  finalResult,
}

enum StopTimerOutcome { crew, imposters }

class StopTimerSetup {
  const StopTimerSetup({
    required this.mode,
    required this.players,
    this.pointsGoal = 5,
    this.imposterCount = 1,
    this.imposterInfoMode = TimerImposterInfoMode.falseTarget,
  });

  final StopTimerMode mode;
  final List<Player> players;
  final int pointsGoal;
  final int imposterCount;
  final TimerImposterInfoMode imposterInfoMode;

  StopTimerSetup copyWith({List<Player>? players}) => StopTimerSetup(
    mode: mode,
    players: players ?? this.players,
    pointsGoal: pointsGoal,
    imposterCount: imposterCount,
    imposterInfoMode: imposterInfoMode,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mode': mode.name,
    'players': players.map((Player player) => player.toJson()).toList(),
    'pointsGoal': pointsGoal,
    'imposterCount': imposterCount,
    'imposterInfoMode': imposterInfoMode.name,
  };

  factory StopTimerSetup.fromJson(Map<String, dynamic> json) => StopTimerSetup(
    mode: StopTimerMode.values.byName(json['mode'] as String),
    players: (json['players'] as List<dynamic>)
        .map(
          (dynamic value) =>
              Player.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList(growable: false),
    pointsGoal: (json['pointsGoal'] as num?)?.toInt() ?? 5,
    imposterCount: (json['imposterCount'] as num?)?.toInt() ?? 1,
    imposterInfoMode: TimerImposterInfoMode.values.byName(
      json['imposterInfoMode'] as String? ??
          TimerImposterInfoMode.falseTarget.name,
    ),
  );
}

class TimerTargetGenerator {
  const TimerTargetGenerator();

  double generate(Random random) {
    final ticket = random.nextInt(10000);
    final hundredths = switch (ticket) {
      < 1200 => 25 + random.nextInt(75),
      < 7000 => _oneToFive(random),
      < 8800 => 500 + random.nextInt(300),
      < 9600 => 800 + random.nextInt(200),
      _ => 1000 + random.nextInt(501),
    };
    return hundredths / 100;
  }

  double relatedTarget(double crewTarget, Random random) {
    final crewHundredths = (crewTarget * 100).round();
    final delta = 200 + random.nextInt(101);
    final canSubtract = crewHundredths - delta >= 25;
    final canAdd = crewHundredths + delta <= 1500;
    final add = canAdd && (!canSubtract || random.nextBool());
    return (add ? crewHundredths + delta : crewHundredths - delta) / 100;
  }

  int _oneToFive(Random random) {
    final secondTicket = random.nextInt(100);
    final second = switch (secondTicket) {
      < 32 => 1,
      < 59 => 2,
      < 82 => 3,
      _ => 4,
    };
    return second * 100 + random.nextInt(100);
  }
}

class TimerAttempt {
  const TimerAttempt({required this.playerId, required this.durationSeconds});

  final String playerId;
  final double durationSeconds;

  double errorFrom(double target) => durationSeconds - target;
  double absoluteErrorFrom(double target) => errorFrom(target).abs();

  Map<String, dynamic> toJson() => <String, dynamic>{
    'playerId': playerId,
    'durationSeconds': durationSeconds,
  };
}

class TimerVote {
  const TimerVote({required this.voterId, required this.targetPlayerId});

  final String voterId;
  final String targetPlayerId;
}

class TimerVoteResolution {
  const TimerVoteResolution({
    this.suspectPlayerId,
    this.runoffCandidates = const <String>[],
    this.creatorDecisionRequired = false,
  });

  final String? suspectPlayerId;
  final List<String> runoffCandidates;
  final bool creatorDecisionRequired;
}

class TimerBallotBox {
  TimerBallotBox({
    required List<String> voterIds,
    this.candidates,
    this.runoff = 0,
  }) : voterIds = List<String>.unmodifiable(voterIds);

  final List<String> voterIds;
  final List<String>? candidates;
  final int runoff;
  final Map<String, TimerVote> _votes = <String, TimerVote>{};

  Map<String, TimerVote> get votes =>
      Map<String, TimerVote>.unmodifiable(_votes);

  bool cast(String voterId, String targetPlayerId) {
    final available = candidates ?? voterIds;
    if (!voterIds.contains(voterId) ||
        !available.contains(targetPlayerId) ||
        voterId == targetPlayerId ||
        _votes.containsKey(voterId)) {
      return false;
    }
    _votes[voterId] = TimerVote(
      voterId: voterId,
      targetPlayerId: targetPlayerId,
    );
    return true;
  }

  bool get isComplete => _votes.length == voterIds.length;

  TimerVoteResolution resolve() {
    if (!isComplete) return const TimerVoteResolution();
    final totals = <String, int>{};
    for (final vote in _votes.values) {
      totals.update(
        vote.targetPlayerId,
        (int count) => count + 1,
        ifAbsent: () => 1,
      );
    }
    final highest = totals.values.reduce(max);
    final leaders = totals.entries
        .where((MapEntry<String, int> entry) => entry.value == highest)
        .map((MapEntry<String, int> entry) => entry.key)
        .toList(growable: false);
    if (leaders.length == 1) {
      return TimerVoteResolution(suspectPlayerId: leaders.single);
    }
    return TimerVoteResolution(
      runoffCandidates: leaders,
      creatorDecisionRequired: runoff >= 1,
    );
  }
}

class TimerRoundPlan {
  const TimerRoundPlan({
    required this.number,
    required this.targetSeconds,
    required this.playOrder,
    this.imposterPlayerIds = const <String>{},
    this.falseTargetSeconds,
  });

  final int number;
  final double targetSeconds;
  final List<String> playOrder;
  final Set<String> imposterPlayerIds;
  final double? falseTargetSeconds;

  double? targetFor(String playerId, TimerImposterInfoMode infoMode) {
    if (!imposterPlayerIds.contains(playerId)) return targetSeconds;
    return infoMode == TimerImposterInfoMode.falseTarget
        ? falseTargetSeconds
        : null;
  }
}

class TimerRoundResult {
  const TimerRoundResult({
    required this.plan,
    required this.rankedAttempts,
    required this.pointsAwarded,
  });

  final TimerRoundPlan plan;
  final List<TimerAttempt> rankedAttempts;
  final Map<String, int> pointsAwarded;

  List<String> get winnerIds => pointsAwarded.keys.toList(growable: false);
}

class StopTimerGameState {
  const StopTimerGameState({
    required this.setup,
    required this.phase,
    required this.plan,
    required this.scores,
    this.attempts = const <String, TimerAttempt>{},
    this.roundResults = const <TimerRoundResult>[],
    this.currentPlayerIndex = 0,
    this.revealIndex = 0,
    this.outcome,
    this.accusedPlayerId,
  });

  final StopTimerSetup setup;
  final StopTimerPhase phase;
  final TimerRoundPlan plan;
  final Map<String, int> scores;
  final Map<String, TimerAttempt> attempts;
  final List<TimerRoundResult> roundResults;
  final int currentPlayerIndex;
  final int revealIndex;
  final StopTimerOutcome? outcome;
  final String? accusedPlayerId;

  String get currentPlayerId => plan.playOrder[currentPlayerIndex];

  StopTimerGameState copyWith({
    StopTimerSetup? setup,
    StopTimerPhase? phase,
    TimerRoundPlan? plan,
    Map<String, int>? scores,
    Map<String, TimerAttempt>? attempts,
    List<TimerRoundResult>? roundResults,
    int? currentPlayerIndex,
    int? revealIndex,
    StopTimerOutcome? outcome,
    String? accusedPlayerId,
  }) => StopTimerGameState(
    setup: setup ?? this.setup,
    phase: phase ?? this.phase,
    plan: plan ?? this.plan,
    scores: scores ?? this.scores,
    attempts: attempts ?? this.attempts,
    roundResults: roundResults ?? this.roundResults,
    currentPlayerIndex: currentPlayerIndex ?? this.currentPlayerIndex,
    revealIndex: revealIndex ?? this.revealIndex,
    outcome: outcome ?? this.outcome,
    accusedPlayerId: accusedPlayerId ?? this.accusedPlayerId,
  );
}

class StopTimerGameEngine {
  const StopTimerGameEngine({
    this.targetGenerator = const TimerTargetGenerator(),
  });

  final TimerTargetGenerator targetGenerator;

  StopTimerGameState start(StopTimerSetup setup, Random random) {
    _validateSetup(setup);
    final plan = _createPlan(setup, random, 1);
    return StopTimerGameState(
      setup: setup,
      phase: switch (setup.mode) {
        StopTimerMode.solo ||
        StopTimerMode.buzzer => StopTimerPhase.targetReveal,
        StopTimerMode.imposter => StopTimerPhase.privateReveal,
      },
      plan: plan,
      scores: Map<String, int>.unmodifiable(<String, int>{
        for (final player in setup.players) player.id: 0,
      }),
    );
  }

  StopTimerGameState hideTarget(StopTimerGameState state) {
    if (state.phase != StopTimerPhase.targetReveal) {
      throw StateError('wrong_phase');
    }
    return state.copyWith(phase: StopTimerPhase.handoff);
  }

  StopTimerGameState advancePrivateReveal(StopTimerGameState state) {
    if (state.phase != StopTimerPhase.privateReveal) {
      throw StateError('wrong_phase');
    }
    if (state.revealIndex + 1 < state.setup.players.length) {
      return state.copyWith(revealIndex: state.revealIndex + 1);
    }
    return state.copyWith(phase: StopTimerPhase.handoff, currentPlayerIndex: 0);
  }

  StopTimerGameState startAttempt(StopTimerGameState state) {
    if (state.phase != StopTimerPhase.handoff) {
      throw StateError('wrong_phase');
    }
    return state.copyWith(phase: StopTimerPhase.running);
  }

  StopTimerGameState restartInterruptedAttempt(StopTimerGameState state) {
    if (state.phase != StopTimerPhase.running) {
      throw StateError('wrong_phase');
    }
    return state.copyWith(phase: StopTimerPhase.handoff);
  }

  StopTimerGameState removePlayer(StopTimerGameState state, String playerId) {
    if (!state.setup.players.any((Player player) => player.id == playerId)) {
      return state;
    }
    final oldCurrent = state.plan.playOrder.isEmpty
        ? null
        : state.plan.playOrder[state.currentPlayerIndex];
    final players = state.setup.players
        .where((Player player) => player.id != playerId)
        .toList(growable: false);
    final order = state.plan.playOrder
        .where((String id) => id != playerId)
        .toList(growable: false);
    final attempts = Map<String, TimerAttempt>.from(state.attempts)
      ..remove(playerId);
    final scores = Map<String, int>.from(state.scores)..remove(playerId);
    final imposters = Set<String>.from(state.plan.imposterPlayerIds)
      ..remove(playerId);
    var currentIndex = 0;
    if (order.isNotEmpty && oldCurrent != null && oldCurrent != playerId) {
      currentIndex = order.indexOf(oldCurrent);
    } else if (order.isNotEmpty) {
      currentIndex = min(state.currentPlayerIndex, order.length - 1);
    }
    var phase = state.phase;
    StopTimerOutcome? outcome = state.outcome;
    if (state.setup.mode == StopTimerMode.buzzer && players.length < 2) {
      phase = StopTimerPhase.finalResult;
    } else if (state.setup.mode == StopTimerMode.imposter &&
        (players.length < 3 || imposters.isEmpty)) {
      phase = StopTimerPhase.finalResult;
      outcome = imposters.isEmpty
          ? StopTimerOutcome.crew
          : StopTimerOutcome.imposters;
    } else if (state.phase == StopTimerPhase.running &&
        oldCurrent == playerId) {
      phase = StopTimerPhase.handoff;
    }
    return state.copyWith(
      setup: state.setup.copyWith(players: List<Player>.unmodifiable(players)),
      phase: phase,
      plan: TimerRoundPlan(
        number: state.plan.number,
        targetSeconds: state.plan.targetSeconds,
        playOrder: List<String>.unmodifiable(order),
        imposterPlayerIds: Set<String>.unmodifiable(imposters),
        falseTargetSeconds: state.plan.falseTargetSeconds,
      ),
      attempts: Map<String, TimerAttempt>.unmodifiable(attempts),
      scores: Map<String, int>.unmodifiable(scores),
      currentPlayerIndex: currentIndex,
      revealIndex: players.isEmpty
          ? 0
          : min(state.revealIndex, players.length - 1),
      outcome: outcome,
    );
  }

  StopTimerGameState recordAttempt(
    StopTimerGameState state,
    double durationSeconds,
  ) {
    if (state.phase != StopTimerPhase.running || durationSeconds < 0) {
      throw StateError('invalid_attempt');
    }
    final attempt = TimerAttempt(
      playerId: state.currentPlayerId,
      durationSeconds: durationSeconds,
    );
    final attempts = Map<String, TimerAttempt>.from(state.attempts)
      ..[attempt.playerId] = attempt;
    if (state.currentPlayerIndex + 1 < state.plan.playOrder.length) {
      return state.copyWith(
        phase: StopTimerPhase.handoff,
        attempts: Map<String, TimerAttempt>.unmodifiable(attempts),
        currentPlayerIndex: state.currentPlayerIndex + 1,
      );
    }

    if (state.setup.mode == StopTimerMode.imposter) {
      return state.copyWith(
        phase: StopTimerPhase.voting,
        attempts: Map<String, TimerAttempt>.unmodifiable(attempts),
      );
    }

    final result = scoreBuzzerRound(state.plan, attempts.values.toList());
    final scores = Map<String, int>.from(state.scores);
    for (final award in result.pointsAwarded.entries) {
      scores[award.key] = (scores[award.key] ?? 0) + award.value;
    }
    return state.copyWith(
      phase: StopTimerPhase.roundResult,
      attempts: Map<String, TimerAttempt>.unmodifiable(attempts),
      scores: Map<String, int>.unmodifiable(scores),
      roundResults: List<TimerRoundResult>.unmodifiable(<TimerRoundResult>[
        ...state.roundResults,
        result,
      ]),
    );
  }

  TimerRoundResult scoreBuzzerRound(
    TimerRoundPlan plan,
    List<TimerAttempt> attempts,
  ) {
    if (attempts.length != plan.playOrder.length ||
        attempts
                .map((TimerAttempt attempt) => attempt.playerId)
                .toSet()
                .length !=
            plan.playOrder.length) {
      throw StateError('incomplete_round');
    }
    final ranked = List<TimerAttempt>.from(attempts)
      ..sort(
        (TimerAttempt a, TimerAttempt b) => a
            .absoluteErrorFrom(plan.targetSeconds)
            .compareTo(b.absoluteErrorFrom(plan.targetSeconds)),
      );
    final bestError = ranked.first.absoluteErrorFrom(plan.targetSeconds);
    final winners = ranked.where(
      (TimerAttempt attempt) =>
          (attempt.absoluteErrorFrom(plan.targetSeconds) - bestError).abs() <
          0.000000001,
    );
    final targetHundredths = (plan.targetSeconds * 100).round();
    return TimerRoundResult(
      plan: plan,
      rankedAttempts: List<TimerAttempt>.unmodifiable(ranked),
      pointsAwarded: Map<String, int>.unmodifiable(<String, int>{
        for (final winner in winners)
          winner.playerId:
              (winner.durationSeconds * 100).round() == targetHundredths
              ? 2
              : 1,
      }),
    );
  }

  bool matchComplete(StopTimerGameState state) =>
      state.scores.values.any((int score) => score >= state.setup.pointsGoal);

  List<String> matchWinnerIds(StopTimerGameState state) {
    final best = state.scores.values.reduce(max);
    return state.setup.players
        .where((Player player) => state.scores[player.id] == best)
        .map((Player player) => player.id)
        .toList(growable: false);
  }

  StopTimerGameState continueAfterRound(
    StopTimerGameState state,
    Random random,
  ) {
    if (state.phase != StopTimerPhase.roundResult) {
      throw StateError('wrong_phase');
    }
    if (matchComplete(state)) {
      return state.copyWith(phase: StopTimerPhase.finalResult);
    }
    return state.copyWith(
      phase: StopTimerPhase.targetReveal,
      plan: _createPlan(state.setup, random, state.plan.number + 1),
      attempts: const <String, TimerAttempt>{},
      currentPlayerIndex: 0,
    );
  }

  StopTimerGameState accuse(StopTimerGameState state, String playerId) {
    if (state.phase != StopTimerPhase.voting ||
        !state.setup.players.any((Player player) => player.id == playerId)) {
      throw StateError('invalid_accusation');
    }
    return state.copyWith(
      phase: StopTimerPhase.finalResult,
      accusedPlayerId: playerId,
      outcome: state.plan.imposterPlayerIds.contains(playerId)
          ? StopTimerOutcome.crew
          : StopTimerOutcome.imposters,
    );
  }

  TimerRoundPlan _createPlan(StopTimerSetup setup, Random random, int round) {
    final order = setup.players.map((Player player) => player.id).toList()
      ..shuffle(random);
    final target = targetGenerator.generate(random);
    if (setup.mode != StopTimerMode.imposter) {
      return TimerRoundPlan(
        number: round,
        targetSeconds: target,
        playOrder: List<String>.unmodifiable(order),
      );
    }
    final roleOrder = List<String>.from(order)..shuffle(random);
    final imposters = roleOrder.take(setup.imposterCount).toSet();
    return TimerRoundPlan(
      number: round,
      targetSeconds: target,
      playOrder: List<String>.unmodifiable(order),
      imposterPlayerIds: Set<String>.unmodifiable(imposters),
      falseTargetSeconds:
          setup.imposterInfoMode == TimerImposterInfoMode.falseTarget
          ? targetGenerator.relatedTarget(target, random)
          : null,
    );
  }

  void _validateSetup(StopTimerSetup setup) {
    final requiredPlayers = setup.mode == StopTimerMode.solo
        ? 1
        : setup.mode == StopTimerMode.buzzer
        ? 2
        : 3;
    if (setup.players.length < requiredPlayers) {
      throw ArgumentError('Not enough players for ${setup.mode.name}.');
    }
    if (setup.pointsGoal < 3 || setup.pointsGoal > 15) {
      throw ArgumentError.value(setup.pointsGoal, 'pointsGoal');
    }
    if (setup.mode == StopTimerMode.imposter) {
      final maximum = max(1, (setup.players.length - 1) ~/ 2);
      if (setup.imposterCount < 1 || setup.imposterCount > maximum) {
        throw ArgumentError.value(setup.imposterCount, 'imposterCount');
      }
    }
  }
}
