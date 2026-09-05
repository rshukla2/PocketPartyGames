import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/models/app_models.dart';
import '../../core/models/game_models.dart';

enum CountdownPhase { transition, prompt, timing, scoreEntry, finalResult }

@immutable
class CountdownTurn {
  const CountdownTurn({
    required this.playerId,
    required this.level,
    required this.prompt,
  });

  final String playerId;
  final int level;
  final CountdownPrompt prompt;
}

@immutable
class CountdownMatch {
  CountdownMatch({
    required List<String> playerIds,
    required List<CountdownTurn> turns,
    required this.turnIndex,
    required this.phase,
    required Map<String, int> scores,
    this.answerCount,
  }) : playerIds = List<String>.unmodifiable(playerIds),
       turns = List<CountdownTurn>.unmodifiable(turns),
       scores = Map<String, int>.unmodifiable(scores);

  final List<String> playerIds;
  final List<CountdownTurn> turns;
  final int turnIndex;
  final CountdownPhase phase;
  final Map<String, int> scores;
  final int? answerCount;

  CountdownTurn get currentTurn => turns[turnIndex];

  List<String> get winnerIds {
    if (scores.isEmpty) return const <String>[];
    final best = scores.values.reduce(max);
    return List<String>.unmodifiable(
      playerIds.where((String id) => scores[id] == best),
    );
  }
}

class CountdownGameEngine {
  const CountdownGameEngine();

  CountdownMatch start({
    required List<Player> players,
    required List<CountdownPrompt> prompts,
    required Random random,
  }) {
    if (players.isEmpty) {
      throw ArgumentError.value(players, 'players', 'must not be empty');
    }

    final pools = <int, List<CountdownPrompt>>{};
    for (var level = 1; level <= 5; level++) {
      final pool = prompts
          .where((CountdownPrompt prompt) => prompt.level == level)
          .toList();
      if (pool.isEmpty) {
        throw StateError('Countdown level $level has no prompts.');
      }
      pools[level] = pool;
    }

    final used = <int, Set<String>>{
      for (var level = 1; level <= 5; level++) level: <String>{},
    };
    final turns = <CountdownTurn>[];
    for (final player in players) {
      for (var level = 5; level >= 1; level--) {
        final pool = pools[level]!;
        var available = pool
            .where(
              (CountdownPrompt prompt) => !used[level]!.contains(prompt.id),
            )
            .toList();
        if (available.isEmpty) {
          used[level]!.clear();
          available = List<CountdownPrompt>.from(pool);
        }
        final prompt = available[random.nextInt(available.length)];
        used[level]!.add(prompt.id);
        turns.add(
          CountdownTurn(playerId: player.id, level: level, prompt: prompt),
        );
      }
    }

    return CountdownMatch(
      playerIds: players.map((Player player) => player.id).toList(),
      turns: turns,
      turnIndex: 0,
      phase: CountdownPhase.transition,
      scores: <String, int>{for (final player in players) player.id: 0},
    );
  }

  CountdownMatch showPrompt(CountdownMatch match) {
    _requirePhase(match, CountdownPhase.transition);
    return _copy(match, phase: CountdownPhase.prompt);
  }

  CountdownMatch startTimer(CountdownMatch match) {
    _requirePhase(match, CountdownPhase.prompt);
    return _copy(match, phase: CountdownPhase.timing);
  }

  CountdownMatch expireTimer(CountdownMatch match) {
    _requirePhase(match, CountdownPhase.timing);
    return _copy(match, phase: CountdownPhase.scoreEntry);
  }

  CountdownMatch selectAnswer(CountdownMatch match, int answerCount) {
    _requirePhase(match, CountdownPhase.scoreEntry);
    if (answerCount < 0 || answerCount > match.currentTurn.level) {
      throw RangeError.range(
        answerCount,
        0,
        match.currentTurn.level,
        'answerCount',
      );
    }
    return _copy(match, answerCount: answerCount);
  }

  CountdownMatch continueAfterScore(CountdownMatch match) {
    _requirePhase(match, CountdownPhase.scoreEntry);
    final answerCount = match.answerCount;
    if (answerCount == null) {
      throw StateError('Choose an answer count before continuing.');
    }

    final scores = Map<String, int>.from(match.scores);
    final playerId = match.currentTurn.playerId;
    scores[playerId] = (scores[playerId] ?? 0) + answerCount;
    final nextIndex = match.turnIndex + 1;
    if (nextIndex >= match.turns.length) {
      return CountdownMatch(
        playerIds: match.playerIds,
        turns: match.turns,
        turnIndex: match.turnIndex,
        phase: CountdownPhase.finalResult,
        scores: scores,
      );
    }
    return CountdownMatch(
      playerIds: match.playerIds,
      turns: match.turns,
      turnIndex: nextIndex,
      phase: CountdownPhase.transition,
      scores: scores,
    );
  }

  CountdownMatch _copy(
    CountdownMatch match, {
    CountdownPhase? phase,
    int? answerCount,
  }) => CountdownMatch(
    playerIds: match.playerIds,
    turns: match.turns,
    turnIndex: match.turnIndex,
    phase: phase ?? match.phase,
    scores: match.scores,
    answerCount: answerCount,
  );

  void _requirePhase(CountdownMatch match, CountdownPhase expected) {
    if (match.phase != expected) {
      throw StateError('Expected ${expected.name}, found ${match.phase.name}.');
    }
  }
}
