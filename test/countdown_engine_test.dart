import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/models/game_models.dart';
import 'package:pocket_party_games/features/games/countdown_engine.dart';

void main() {
  const engine = CountdownGameEngine();

  test('builds player-first turns through levels 5 to 1', () {
    final match = engine.start(
      players: _players(3),
      prompts: _prompts(4),
      random: Random(7),
    );

    expect(match.turns, hasLength(15));
    expect(match.turns.map((CountdownTurn turn) => turn.playerId), <String>[
      ...List<String>.filled(5, 'p1'),
      ...List<String>.filled(5, 'p2'),
      ...List<String>.filled(5, 'p3'),
    ]);
    for (var player = 0; player < 3; player++) {
      expect(
        match.turns
            .skip(player * 5)
            .take(5)
            .map((CountdownTurn turn) => turn.level),
        <int>[5, 4, 3, 2, 1],
      );
    }
  });

  test('supports one through twenty players', () {
    for (var count = 1; count <= 20; count++) {
      final match = engine.start(
        players: _players(count),
        prompts: _prompts(2),
        random: Random(count),
      );
      expect(match.turns, hasLength(count * 5));
      expect(match.scores, hasLength(count));
      expect(match.scores.values, everyElement(0));
    }
  });

  test('uses unique level prompts until that pool is exhausted', () {
    final match = engine.start(
      players: _players(3),
      prompts: _prompts(2),
      random: Random(2),
    );

    for (var level = 1; level <= 5; level++) {
      final ids = match.turns
          .where((CountdownTurn turn) => turn.level == level)
          .map((CountdownTurn turn) => turn.prompt.id)
          .toList();
      expect(ids.take(2).toSet(), hasLength(2));
      expect(ids[2], isIn(ids.take(2)));
    }
  });

  test('seeded planning is deterministic', () {
    CountdownMatch build() => engine.start(
      players: _players(4),
      prompts: _prompts(5),
      random: Random(44),
    );

    expect(
      build().turns.map((CountdownTurn turn) => turn.prompt.id),
      build().turns.map((CountdownTurn turn) => turn.prompt.id),
    );
  });

  test('requires score selection and rejects values above the level', () {
    var match = engine.start(
      players: _players(1),
      prompts: _prompts(1),
      random: Random(1),
    );
    match = engine.showPrompt(match);
    match = engine.startTimer(match);
    match = engine.expireTimer(match);

    expect(() => engine.continueAfterScore(match), throwsStateError);
    expect(() => engine.selectAnswer(match, -1), throwsRangeError);
    expect(() => engine.selectAnswer(match, 6), throwsRangeError);
    expect(engine.selectAnswer(match, 0).answerCount, 0);
    expect(engine.selectAnswer(match, 5).answerCount, 5);
  });

  test('commits each score once and advances the same player first', () {
    var match = engine.start(
      players: _players(2),
      prompts: _prompts(3),
      random: Random(3),
    );
    match = _scoreTurn(engine, match, 4);

    expect(match.phase, CountdownPhase.transition);
    expect(match.currentTurn.playerId, 'p1');
    expect(match.currentTurn.level, 4);
    expect(match.scores['p1'], 4);
    expect(() => engine.continueAfterScore(match), throwsStateError);
  });

  test('totals points and exposes all co-winners', () {
    var match = engine.start(
      players: _players(2),
      prompts: _prompts(3),
      random: Random(3),
    );
    while (match.phase != CountdownPhase.finalResult) {
      match = _scoreTurn(engine, match, match.currentTurn.level - 1);
    }

    expect(match.scores, <String, int>{'p1': 10, 'p2': 10});
    expect(match.winnerIds, <String>['p1', 'p2']);
  });

  test('validates players and every prompt level', () {
    expect(
      () => engine.start(
        players: const <Player>[],
        prompts: _prompts(1),
        random: Random(1),
      ),
      throwsArgumentError,
    );
    expect(
      () => engine.start(
        players: _players(1),
        prompts: _prompts(1)
            .where((CountdownPrompt prompt) => prompt.level != 3)
            .toList(),
        random: Random(1),
      ),
      throwsStateError,
    );
  });
}

CountdownMatch _scoreTurn(
  CountdownGameEngine engine,
  CountdownMatch match,
  int answer,
) {
  match = engine.showPrompt(match);
  match = engine.startTimer(match);
  match = engine.expireTimer(match);
  match = engine.selectAnswer(match, answer);
  return engine.continueAfterScore(match);
}

List<Player> _players(int count) => List<Player>.generate(
  count,
  (int index) => Player(
    id: 'p${index + 1}',
    name: 'Player ${index + 1}',
    colorIndex: index % 8,
  ),
);

List<CountdownPrompt> _prompts(int perLevel) => <CountdownPrompt>[
  for (var level = 1; level <= 5; level++)
    for (var index = 0; index < perLevel; index++)
      CountdownPrompt(
        id: 'level-$level-$index',
        level: level,
        text: 'Prompt $index for level $level',
      ),
];
