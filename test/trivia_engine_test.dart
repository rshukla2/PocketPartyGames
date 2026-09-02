import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/core/data/game_data_repository.dart';
import 'package:pocket_party_games/features/games/trivia_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameDataRepository data;
  late TriviaDeckPlanner planner;

  setUpAll(() async {
    data = await GameDataRepository.load();
    planner = TriviaDeckPlanner(questions: data.trivia);
  });

  test('uses the real 35 easy, 35 medium, and 30 hard category split', () {
    final availability = planner.availability(
      category: 'general',
      difficulty: TriviaDifficultyFilter.mixed,
      playerCount: 1,
    );

    expect(availability.eligibleByDifficulty, <TriviaDifficultyFilter, int>{
      TriviaDifficultyFilter.easy: 35,
      TriviaDifficultyFilter.medium: 35,
      TriviaDifficultyFilter.hard: 30,
    });
  });

  test('computes strict mixed caps for representative player counts', () {
    const expected = <int, int>{
      2: 25,
      3: 25,
      4: 23,
      5: 20,
      6: 15,
      10: 9,
      20: 3,
    };

    for (final entry in expected.entries) {
      expect(
        planner
            .availability(
              category: 'general',
              difficulty: TriviaDifficultyFilter.mixed,
              playerCount: entry.key,
            )
            .maxQuestionsPerPlayer,
        entry.value,
        reason: 'Unexpected cap for ${entry.key} players',
      );
    }
  });

  test('computes fixed-difficulty and all-category caps', () {
    expect(
      planner
          .availability(
            category: 'general',
            difficulty: TriviaDifficultyFilter.medium,
            playerCount: 6,
          )
          .maxQuestionsPerPlayer,
      5,
    );
    expect(
      planner
          .availability(
            category: 'general',
            difficulty: TriviaDifficultyFilter.hard,
            playerCount: 20,
          )
          .maxQuestionsPerPlayer,
      1,
    );
    expect(
      planner
          .availability(
            category: 'all',
            difficulty: TriviaDifficultyFilter.medium,
            playerCount: 6,
          )
          .maxQuestionsPerPlayer,
      25,
    );
  });

  test('supports arbitrary integer deck sizes', () {
    for (final count in <int>[7, 13, 16, 22, 25]) {
      final plan = planner.plan(
        category: 'all',
        difficulty: TriviaDifficultyFilter.mixed,
        playerIds: const <String>['a', 'b'],
        questionsPerPlayer: count,
        turnOrder: TriviaTurnOrder.fullSetEach,
        random: Random(count),
      );
      expect(
        plan.decks,
        everyElement(
          predicate<TriviaPlayerDeck>((deck) => deck.turns.length == count),
        ),
      );
    }
  });

  test(
    'deals unique, equally difficult decks with equal point opportunity',
    () {
      final plan = planner.plan(
        category: 'general',
        difficulty: TriviaDifficultyFilter.mixed,
        playerIds: List<String>.generate(5, (index) => 'p$index'),
        questionsPerPlayer: 20,
        turnOrder: TriviaTurnOrder.fullSetEach,
        random: Random(42),
      );

      expect(plan.quotaPerPlayer, <TriviaDifficultyFilter, int>{
        TriviaDifficultyFilter.easy: 7,
        TriviaDifficultyFilter.medium: 7,
        TriviaDifficultyFilter.hard: 6,
      });
      final ids = plan.turns.map((turn) => turn.question.id).toList();
      expect(ids.toSet(), hasLength(ids.length));
      final possibleScores = plan.decks
          .map(
            (deck) =>
                deck.turns.fold<int>(0, (sum, turn) => sum + turn.pointValue),
          )
          .toSet();
      expect(possibleScores, hasLength(1));
      expect(possibleScores.single, 39);
    },
  );

  test('full-set ordering keeps each player deck together', () {
    final plan = planner.plan(
      category: 'general',
      difficulty: TriviaDifficultyFilter.easy,
      playerIds: const <String>['a', 'b', 'c'],
      questionsPerPlayer: 7,
      turnOrder: TriviaTurnOrder.fullSetEach,
      random: Random(7),
    );

    expect(plan.turns.take(7).map((turn) => turn.playerId).toSet(), <String>{
      'a',
    });
    expect(
      plan.turns.skip(7).take(7).map((turn) => turn.playerId).toSet(),
      <String>{'b'},
    );
    expect(plan.turns.skip(14).map((turn) => turn.playerId).toSet(), <String>{
      'c',
    });
  });

  test('one-each ordering rotates while retaining per-player numbering', () {
    final plan = planner.plan(
      category: 'general',
      difficulty: TriviaDifficultyFilter.easy,
      playerIds: const <String>['a', 'b', 'c'],
      questionsPerPlayer: 5,
      turnOrder: TriviaTurnOrder.oneQuestionEach,
      random: Random(9),
    );

    expect(
      plan.turns.take(6).map((turn) => (turn.playerId, turn.questionNumber)),
      <(String, int)>[
        ('a', 1),
        ('b', 1),
        ('c', 1),
        ('a', 2),
        ('b', 2),
        ('c', 2),
      ],
    );
  });

  test('seeded planning is deterministic', () {
    TriviaDeckPlan build() => planner.plan(
      category: 'science',
      difficulty: TriviaDifficultyFilter.mixed,
      playerIds: const <String>['a', 'b'],
      questionsPerPlayer: 13,
      turnOrder: TriviaTurnOrder.oneQuestionEach,
      random: Random(1234),
    );

    expect(
      build().turns.map((turn) => turn.question.id),
      build().turns.map((turn) => turn.question.id),
    );
  });

  test('awards the documented values and rejects exhausted plans', () {
    expect(TriviaDeckPlanner.pointsForDifficulty('easy'), 1);
    expect(TriviaDeckPlanner.pointsForDifficulty('medium'), 2);
    expect(TriviaDeckPlanner.pointsForDifficulty('hard'), 3);
    expect(
      () => planner.plan(
        category: 'general',
        difficulty: TriviaDifficultyFilter.mixed,
        playerIds: List<String>.generate(20, (index) => 'p$index'),
        questionsPerPlayer: 5,
        turnOrder: TriviaTurnOrder.fullSetEach,
        random: Random(1),
      ),
      throwsRangeError,
    );
  });
}
