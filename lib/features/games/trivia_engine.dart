import 'dart:math';

import 'package:flutter/foundation.dart';

import '../../core/models/game_models.dart';

enum TriviaDifficultyFilter {
  mixed,
  easy,
  medium,
  hard;

  String? get dataValue => this == mixed ? null : name;
}

enum TriviaTurnOrder { fullSetEach, oneQuestionEach }

@immutable
class TriviaAvailability {
  TriviaAvailability({
    required Map<TriviaDifficultyFilter, int> eligibleByDifficulty,
    required Map<TriviaDifficultyFilter, int> perPlayerCapacity,
    required this.maxQuestionsPerPlayer,
  }) : eligibleByDifficulty = Map.unmodifiable(eligibleByDifficulty),
       perPlayerCapacity = Map.unmodifiable(perPlayerCapacity);

  final Map<TriviaDifficultyFilter, int> eligibleByDifficulty;
  final Map<TriviaDifficultyFilter, int> perPlayerCapacity;
  final int maxQuestionsPerPlayer;

  bool get canPlay => maxQuestionsPerPlayer >= 5;
}

@immutable
class TriviaTurn {
  const TriviaTurn({
    required this.playerId,
    required this.question,
    required this.questionNumber,
    required this.pointValue,
  });

  final String playerId;
  final TriviaQuestion question;
  final int questionNumber;
  final int pointValue;
}

@immutable
class TriviaPlayerDeck {
  TriviaPlayerDeck({required this.playerId, required List<TriviaTurn> turns})
    : turns = List.unmodifiable(turns);

  final String playerId;
  final List<TriviaTurn> turns;
}

@immutable
class TriviaDeckPlan {
  TriviaDeckPlan({
    required List<TriviaPlayerDeck> decks,
    required List<TriviaTurn> turns,
    required this.questionsPerPlayer,
    required Map<TriviaDifficultyFilter, int> quotaPerPlayer,
    required this.turnOrder,
  }) : decks = List.unmodifiable(decks),
       turns = List.unmodifiable(turns),
       quotaPerPlayer = Map.unmodifiable(quotaPerPlayer);

  final List<TriviaPlayerDeck> decks;
  final List<TriviaTurn> turns;
  final int questionsPerPlayer;
  final Map<TriviaDifficultyFilter, int> quotaPerPlayer;
  final TriviaTurnOrder turnOrder;
}

class TriviaDeckPlanner {
  TriviaDeckPlanner({required List<TriviaQuestion> questions})
    : _questions = List.unmodifiable(questions);

  final List<TriviaQuestion> _questions;

  static const _difficulties = <TriviaDifficultyFilter>[
    TriviaDifficultyFilter.easy,
    TriviaDifficultyFilter.medium,
    TriviaDifficultyFilter.hard,
  ];

  static const _mixedWeights = <TriviaDifficultyFilter, double>{
    TriviaDifficultyFilter.easy: .4,
    TriviaDifficultyFilter.medium: .3,
    TriviaDifficultyFilter.hard: .3,
  };

  TriviaAvailability availability({
    required String category,
    required TriviaDifficultyFilter difficulty,
    required int playerCount,
  }) {
    if (playerCount < 1) {
      throw ArgumentError.value(playerCount, 'playerCount', 'Must be positive');
    }
    final categoryPool = _questions.where(
      (question) => category == 'all' || question.category == category,
    );
    final counts = <TriviaDifficultyFilter, int>{
      for (final value in _difficulties)
        value: categoryPool
            .where((question) => question.difficulty == value.dataValue)
            .length,
    };
    final capacities = <TriviaDifficultyFilter, int>{
      for (final value in _difficulties) value: counts[value]! ~/ playerCount,
    };
    final rawMaximum = difficulty == TriviaDifficultyFilter.mixed
        ? capacities.values.fold<int>(0, (sum, value) => sum + value)
        : capacities[difficulty]!;
    return TriviaAvailability(
      eligibleByDifficulty: counts,
      perPlayerCapacity: capacities,
      maxQuestionsPerPlayer: min(25, rawMaximum),
    );
  }

  TriviaDeckPlan plan({
    required String category,
    required TriviaDifficultyFilter difficulty,
    required List<String> playerIds,
    required int questionsPerPlayer,
    required TriviaTurnOrder turnOrder,
    required Random random,
  }) {
    if (playerIds.isEmpty || playerIds.toSet().length != playerIds.length) {
      throw ArgumentError.value(
        playerIds,
        'playerIds',
        'Player IDs must be nonempty and unique',
      );
    }
    final available = availability(
      category: category,
      difficulty: difficulty,
      playerCount: playerIds.length,
    );
    if (questionsPerPlayer < 1 ||
        questionsPerPlayer > available.maxQuestionsPerPlayer) {
      throw RangeError.range(
        questionsPerPlayer,
        1,
        available.maxQuestionsPerPlayer,
        'questionsPerPlayer',
      );
    }

    final quotas = difficulty == TriviaDifficultyFilter.mixed
        ? _mixedQuotas(questionsPerPlayer, available.perPlayerCapacity)
        : <TriviaDifficultyFilter, int>{difficulty: questionsPerPlayer};
    final shuffledPools = <TriviaDifficultyFilter, List<TriviaQuestion>>{
      for (final value in quotas.keys)
        value:
            (_questions
                .where(
                  (question) =>
                      (category == 'all' || question.category == category) &&
                      question.difficulty == value.dataValue,
                )
                .toList()
              ..shuffle(random)),
    };
    final cursors = <TriviaDifficultyFilter, int>{
      for (final value in quotas.keys) value: 0,
    };
    final decks = <TriviaPlayerDeck>[];
    for (final playerId in playerIds) {
      final questions = <TriviaQuestion>[];
      for (final difficulty in _difficulties) {
        final amount = quotas[difficulty] ?? 0;
        if (amount == 0) continue;
        final start = cursors[difficulty]!;
        questions.addAll(shuffledPools[difficulty]!.skip(start).take(amount));
        cursors[difficulty] = start + amount;
      }
      questions.shuffle(random);
      decks.add(
        TriviaPlayerDeck(
          playerId: playerId,
          turns: <TriviaTurn>[
            for (final (index, question) in questions.indexed)
              TriviaTurn(
                playerId: playerId,
                question: question,
                questionNumber: index + 1,
                pointValue: pointsForDifficulty(question.difficulty),
              ),
          ],
        ),
      );
    }

    final turns = switch (turnOrder) {
      TriviaTurnOrder.fullSetEach => <TriviaTurn>[
        for (final deck in decks) ...deck.turns,
      ],
      TriviaTurnOrder.oneQuestionEach => <TriviaTurn>[
        for (
          var questionIndex = 0;
          questionIndex < questionsPerPlayer;
          questionIndex++
        )
          for (final deck in decks) deck.turns[questionIndex],
      ],
    };
    return TriviaDeckPlan(
      decks: decks,
      turns: turns,
      questionsPerPlayer: questionsPerPlayer,
      quotaPerPlayer: quotas,
      turnOrder: turnOrder,
    );
  }

  Map<TriviaDifficultyFilter, int> _mixedQuotas(
    int total,
    Map<TriviaDifficultyFilter, int> capacities,
  ) {
    final quotas = <TriviaDifficultyFilter, int>{
      for (final value in _difficulties)
        value: (total * _mixedWeights[value]!).floor(),
    };
    var remaining = total - quotas.values.fold<int>(0, (a, b) => a + b);
    final remainderOrder = List<TriviaDifficultyFilter>.from(_difficulties)
      ..sort((a, b) {
        final aRemainder = total * _mixedWeights[a]! - quotas[a]!;
        final bRemainder = total * _mixedWeights[b]! - quotas[b]!;
        final result = bRemainder.compareTo(aRemainder);
        return result == 0
            ? _difficulties.indexOf(a).compareTo(_difficulties.indexOf(b))
            : result;
      });
    for (final value in remainderOrder) {
      if (remaining == 0) break;
      quotas[value] = quotas[value]! + 1;
      remaining--;
    }

    for (final value in _difficulties) {
      final capacity = capacities[value]!;
      if (quotas[value]! > capacity) {
        remaining += quotas[value]! - capacity;
        quotas[value] = capacity;
      }
    }
    while (remaining > 0) {
      final candidates = _difficulties
          .where((value) => quotas[value]! < capacities[value]!)
          .toList();
      if (candidates.isEmpty) {
        throw StateError('Mixed trivia capacity was calculated incorrectly');
      }
      candidates.sort((a, b) {
        final aDeficit = total * _mixedWeights[a]! - quotas[a]!;
        final bDeficit = total * _mixedWeights[b]! - quotas[b]!;
        final result = bDeficit.compareTo(aDeficit);
        return result == 0
            ? _difficulties.indexOf(a).compareTo(_difficulties.indexOf(b))
            : result;
      });
      quotas[candidates.first] = quotas[candidates.first]! + 1;
      remaining--;
    }
    return quotas;
  }

  static int pointsForDifficulty(String difficulty) => switch (difficulty) {
    'hard' => 3,
    'medium' => 2,
    _ => 1,
  };
}
