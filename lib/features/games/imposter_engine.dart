import 'dart:math';

import '../../core/models/app_models.dart';
import '../../core/models/game_models.dart';

enum ImposterMode { classic, oddWord }

enum ImposterPhase { privateReveal, discussion, voting, result }

enum ImposterOutcome { crew, imposters }

class ImposterSetup {
  const ImposterSetup({
    required this.players,
    this.category = 'Random',
    this.imposterCount = 1,
    this.discussionSeconds = 180,
    this.mode = ImposterMode.classic,
    this.hintsEnabled = false,
    this.multipleRounds = false,
  });

  final List<Player> players;
  final String category;
  final int imposterCount;
  final int discussionSeconds;
  final ImposterMode mode;
  final bool hintsEnabled;
  final bool multipleRounds;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'players': players.map((Player player) => player.toJson()).toList(),
    'category': category,
    'imposterCount': imposterCount,
    'discussionSeconds': discussionSeconds,
    'mode': mode.name,
    'hintsEnabled': hintsEnabled,
    'multipleRounds': multipleRounds,
  };

  factory ImposterSetup.fromJson(Map<String, dynamic> json) => ImposterSetup(
    players: (json['players'] as List<dynamic>)
        .map(
          (dynamic value) =>
              Player.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList(growable: false),
    category: json['category'] as String? ?? 'Random',
    imposterCount: (json['imposterCount'] as num?)?.toInt() ?? 1,
    discussionSeconds: (json['discussionSeconds'] as num?)?.toInt() ?? 180,
    mode: ImposterMode.values.byName(
      json['mode'] as String? ?? ImposterMode.classic.name,
    ),
    hintsEnabled: json['hintsEnabled'] as bool? ?? false,
    multipleRounds: json['multipleRounds'] as bool? ?? false,
  );
}

class ImposterAssignment {
  const ImposterAssignment({
    required this.playerId,
    required this.isImposter,
    required this.word,
    this.hint,
  });

  final String playerId;
  final bool isImposter;
  final String? word;
  final String? hint;

  Map<String, dynamic> privateProjection(ImposterMode mode) =>
      <String, dynamic>{
        'word': word,
        if (mode == ImposterMode.classic) 'isImposter': isImposter,
        if (hint != null) 'hint': hint,
      };
}

class ImposterVote {
  const ImposterVote({
    required this.voterId,
    required this.targetPlayerId,
    required this.round,
    required this.runoff,
  });

  final String voterId;
  final String targetPlayerId;
  final int round;
  final int runoff;
}

class ImposterRound {
  const ImposterRound({
    required this.number,
    required this.activePlayerIds,
    this.eliminatedPlayerId,
    this.banner,
  });

  final int number;
  final List<String> activePlayerIds;
  final String? eliminatedPlayerId;
  final String? banner;
}

class ImposterMatch {
  const ImposterMatch({
    required this.setup,
    required this.crewWord,
    required this.groupId,
    required this.assignments,
    required this.activePlayerIds,
    required this.rounds,
    required this.phase,
    this.outcome,
  });

  final ImposterSetup setup;
  final String crewWord;
  final String groupId;
  final Map<String, ImposterAssignment> assignments;
  final List<String> activePlayerIds;
  final List<ImposterRound> rounds;
  final ImposterPhase phase;
  final ImposterOutcome? outcome;

  int get activeImposterCount => activePlayerIds
      .where((String id) => assignments[id]?.isImposter == true)
      .length;

  int get activeCrewCount => activePlayerIds.length - activeImposterCount;

  ImposterMatch copyWith({
    List<String>? activePlayerIds,
    List<ImposterRound>? rounds,
    ImposterPhase? phase,
    ImposterOutcome? outcome,
  }) => ImposterMatch(
    setup: setup,
    crewWord: crewWord,
    groupId: groupId,
    assignments: assignments,
    activePlayerIds: activePlayerIds ?? this.activePlayerIds,
    rounds: rounds ?? this.rounds,
    phase: phase ?? this.phase,
    outcome: outcome ?? this.outcome,
  );
}

class ImposterVoteResolution {
  const ImposterVoteResolution({
    required this.eliminatedPlayerId,
    this.runoffCandidates = const <String>[],
    this.creatorDecisionRequired = false,
  });

  final String? eliminatedPlayerId;
  final List<String> runoffCandidates;
  final bool creatorDecisionRequired;
}

class ImposterBallotBox {
  ImposterBallotBox({
    required this.activePlayerIds,
    required this.round,
    this.runoff = 0,
    this.candidates,
  });

  final List<String> activePlayerIds;
  final int round;
  final int runoff;
  final List<String>? candidates;
  final Map<String, ImposterVote> _votes = <String, ImposterVote>{};

  Map<String, ImposterVote> get votes =>
      Map<String, ImposterVote>.unmodifiable(_votes);

  bool cast(String voterId, String targetPlayerId) {
    final eligibleCandidates = candidates ?? activePlayerIds;
    if (!activePlayerIds.contains(voterId) ||
        !eligibleCandidates.contains(targetPlayerId) ||
        voterId == targetPlayerId ||
        _votes.containsKey(voterId)) {
      return false;
    }
    _votes[voterId] = ImposterVote(
      voterId: voterId,
      targetPlayerId: targetPlayerId,
      round: round,
      runoff: runoff,
    );
    return true;
  }

  bool get isComplete => _votes.length == activePlayerIds.length;

  ImposterVoteResolution resolve() {
    if (!isComplete) {
      return const ImposterVoteResolution(eliminatedPlayerId: null);
    }
    final totals = <String, int>{};
    for (final vote in _votes.values) {
      totals.update(
        vote.targetPlayerId,
        (int value) => value + 1,
        ifAbsent: () => 1,
      );
    }
    final highest = totals.values.reduce(max);
    final leaders = totals.entries
        .where((MapEntry<String, int> entry) => entry.value == highest)
        .map((MapEntry<String, int> entry) => entry.key)
        .toList(growable: false);
    if (leaders.length == 1) {
      return ImposterVoteResolution(eliminatedPlayerId: leaders.single);
    }
    return ImposterVoteResolution(
      eliminatedPlayerId: null,
      runoffCandidates: leaders,
      creatorDecisionRequired: runoff >= 1,
    );
  }
}

class ImposterGameEngine {
  const ImposterGameEngine();

  ImposterMatch createMatch({
    required ImposterSetup setup,
    required List<ImposterWord> words,
    required Random random,
  }) {
    if (setup.players.length < 3) {
      throw ArgumentError.value(
        setup.players.length,
        'players',
        'At least three players are required.',
      );
    }
    final maximum = max(1, (setup.players.length - 1) ~/ 2);
    if (setup.imposterCount < 1 || setup.imposterCount > maximum) {
      throw ArgumentError.value(
        setup.imposterCount,
        'imposterCount',
        'Must preserve an initial Crew majority.',
      );
    }
    final pool = setup.category == 'Random'
        ? words
        : words
              .where((ImposterWord word) => word.category == setup.category)
              .toList();
    if (pool.isEmpty) {
      throw StateError('No Imposter words match the selected category.');
    }

    final crewWord = pool[random.nextInt(pool.length)];
    final related =
        pool
            .where(
              (ImposterWord word) =>
                  word.groupId == crewWord.groupId && word.id != crewWord.id,
            )
            .toList()
          ..shuffle(random);
    if (related.isEmpty) {
      throw StateError('The selected word has no related alternatives.');
    }

    final shuffledPlayers = List<Player>.from(setup.players)..shuffle(random);
    final imposterIds = shuffledPlayers
        .take(setup.imposterCount)
        .map((Player player) => player.id)
        .toSet();
    var alternateIndex = 0;
    final assignments = <String, ImposterAssignment>{};
    for (final player in setup.players) {
      final isImposter = imposterIds.contains(player.id);
      final alternate = related[alternateIndex % related.length];
      if (isImposter) alternateIndex++;
      assignments[player.id] = ImposterAssignment(
        playerId: player.id,
        isImposter: isImposter,
        word: switch (setup.mode) {
          ImposterMode.classic => isImposter ? null : crewWord.word,
          ImposterMode.oddWord => isImposter ? alternate.word : crewWord.word,
        },
        hint:
            setup.mode == ImposterMode.classic &&
                isImposter &&
                setup.hintsEnabled
            ? crewWord.hint
            : null,
      );
    }
    final active = setup.players
        .map((Player player) => player.id)
        .toList(growable: false);
    return ImposterMatch(
      setup: setup,
      crewWord: crewWord.word,
      groupId: crewWord.groupId,
      assignments: Map<String, ImposterAssignment>.unmodifiable(assignments),
      activePlayerIds: active,
      rounds: <ImposterRound>[
        ImposterRound(number: 1, activePlayerIds: active),
      ],
      phase: ImposterPhase.privateReveal,
    );
  }

  ImposterMatch beginDiscussion(ImposterMatch match) =>
      match.copyWith(phase: ImposterPhase.discussion);

  ImposterMatch beginVoting(ImposterMatch match) =>
      match.copyWith(phase: ImposterPhase.voting);

  ImposterMatch eliminate(ImposterMatch match, String playerId) {
    if (match.phase != ImposterPhase.voting ||
        !match.activePlayerIds.contains(playerId)) {
      throw StateError(
        'Only an active player can be eliminated during voting.',
      );
    }
    final eliminatedWasImposter = match.assignments[playerId]!.isImposter;
    if (!match.setup.multipleRounds) {
      return match.copyWith(
        phase: ImposterPhase.result,
        outcome: eliminatedWasImposter
            ? ImposterOutcome.crew
            : ImposterOutcome.imposters,
      );
    }

    final remaining = match.activePlayerIds
        .where((String id) => id != playerId)
        .toList(growable: false);
    final imposters = remaining
        .where((String id) => match.assignments[id]!.isImposter)
        .length;
    final crew = remaining.length - imposters;
    if (imposters == 0) {
      return match.copyWith(
        activePlayerIds: remaining,
        phase: ImposterPhase.result,
        outcome: ImposterOutcome.crew,
      );
    }
    if (imposters >= crew) {
      return match.copyWith(
        activePlayerIds: remaining,
        phase: ImposterPhase.result,
        outcome: ImposterOutcome.imposters,
      );
    }
    final player = match.setup.players.firstWhere(
      (Player value) => value.id == playerId,
    );
    final banner = eliminatedWasImposter
        ? '${player.name.toUpperCase()} WAS AN IMPOSTER · $imposters REMAIN${imposters == 1 ? 'S' : ''}'
        : '${player.name.toUpperCase()} WAS NOT AN IMPOSTER';
    final rounds = <ImposterRound>[
      ...match.rounds.sublist(0, match.rounds.length - 1),
      ImposterRound(
        number: match.rounds.last.number,
        activePlayerIds: match.rounds.last.activePlayerIds,
        eliminatedPlayerId: playerId,
      ),
      ImposterRound(
        number: match.rounds.last.number + 1,
        activePlayerIds: remaining,
        banner: banner,
      ),
    ];
    return match.copyWith(
      activePlayerIds: remaining,
      rounds: rounds,
      phase: ImposterPhase.discussion,
    );
  }

  /// Removes a player whose reconnect window expired without treating the
  /// network loss as a vote. Team win conditions still apply immediately.
  ImposterMatch removeDisconnectedPlayer(ImposterMatch match, String playerId) {
    if (!match.activePlayerIds.contains(playerId)) {
      throw StateError('Only an active player can leave the match.');
    }
    final remaining = match.activePlayerIds
        .where((String id) => id != playerId)
        .toList(growable: false);
    final imposters = remaining
        .where((String id) => match.assignments[id]!.isImposter)
        .length;
    final crew = remaining.length - imposters;
    final outcome = imposters == 0
        ? ImposterOutcome.crew
        : imposters >= crew
        ? ImposterOutcome.imposters
        : null;
    final player = match.setup.players.firstWhere(
      (Player value) => value.id == playerId,
    );
    final currentRound = match.rounds.last;
    final rounds = <ImposterRound>[
      ...match.rounds.sublist(0, match.rounds.length - 1),
      ImposterRound(
        number: currentRound.number,
        activePlayerIds: remaining,
        eliminatedPlayerId: currentRound.eliminatedPlayerId,
        banner: '${player.name.toUpperCase()} LEFT THE GAME',
      ),
    ];
    return match.copyWith(
      activePlayerIds: remaining,
      rounds: rounds,
      phase: outcome == null ? match.phase : ImposterPhase.result,
      outcome: outcome,
    );
  }
}
