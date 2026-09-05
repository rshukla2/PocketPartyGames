import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/models/game_models.dart';
import 'package:pocket_party_games/features/games/truth_dare_engine.dart';

void main() {
  const engine = TruthDareGameEngine();
  const players = <Player>[
    Player(id: 'a', name: 'Alex', colorIndex: 0),
    Player(id: 'b', name: 'Blair', colorIndex: 1),
    Player(id: 'c', name: 'Casey', colorIndex: 2),
  ];
  const card = TruthDareCard(
    id: 'truth-1',
    type: 'truth',
    category: 'Chill',
    intensity: 1,
    text: 'Test card?',
  );

  test('each player receives independent swap and skip allowances', () {
    var session = engine.start(players);
    session = engine.useSwap(session, 'a');
    session = engine.useSwap(session, 'a');
    expect(session.playerStates['a']!.swapsRemaining, 0);
    expect(session.playerStates['b']!.swapsRemaining, 2);
    expect(() => engine.useSwap(session, 'a'), throwsStateError);

    session = engine.recordTurn(
      session,
      player: players.first,
      card: card,
      outcome: TruthDareTurnOutcome.skipped,
    );
    expect(session.playerStates['a']!.freeSkipsRemaining, 0);
    expect(session.playerStates['b']!.freeSkipsRemaining, 1);
    expect(
      () => engine.recordTurn(
        session,
        player: players.first,
        card: card,
        outcome: TruthDareTurnOutcome.skipped,
      ),
      throwsStateError,
    );
  });

  test('quit requires the free skip and removes only that player', () {
    var session = engine.start(players);
    expect(
      () => engine.recordTurn(
        session,
        player: players.first,
        card: card,
        outcome: TruthDareTurnOutcome.quit,
      ),
      throwsStateError,
    );
    session = engine.recordTurn(
      session,
      player: players.first,
      card: card,
      outcome: TruthDareTurnOutcome.skipped,
    );
    session = engine.recordTurn(
      session,
      player: players.first,
      card: card,
      outcome: TruthDareTurnOutcome.quit,
    );
    expect(session.activePlayerIds, <String>['b', 'c']);
    expect(session.history.last.outcome, TruthDareTurnOutcome.quit);
  });

  test(
    'ordered rotation skips quit players and ends with no active player',
    () {
      var session = engine.start(players);
      for (final player in players) {
        session = engine.recordTurn(
          session,
          player: player,
          card: card,
          outcome: TruthDareTurnOutcome.skipped,
        );
        session = engine.recordTurn(
          session,
          player: player,
          card: card,
          outcome: TruthDareTurnOutcome.quit,
        );
        if (player.id == 'a') {
          expect(
            engine.nextPlayerId(
              session,
              roster: players,
              currentPlayerId: 'a',
              randomRotation: false,
              random: Random(1),
            ),
            'b',
          );
        }
      }
      expect(
        engine.nextPlayerId(
          session,
          roster: players,
          currentPlayerId: 'c',
          randomRotation: false,
          random: Random(1),
        ),
        isNull,
      );
    },
  );

  test('random rotation selects only active players', () {
    var session = engine.start(players);
    session = engine.recordTurn(
      session,
      player: players[1],
      card: card,
      outcome: TruthDareTurnOutcome.skipped,
    );
    session = engine.recordTurn(
      session,
      player: players[1],
      card: card,
      outcome: TruthDareTurnOutcome.quit,
    );
    for (var seed = 0; seed < 20; seed++) {
      expect(
        engine.nextPlayerId(
          session,
          roster: players,
          currentPlayerId: 'a',
          randomRotation: true,
          random: Random(seed),
        ),
        isNot('b'),
      );
    }
  });

  test('a new session restores every resource', () {
    var session = engine.start(players);
    session = engine.useSwap(session, 'a');
    final replay = engine.start(players);
    expect(replay.playerStates['a']!.swapsRemaining, 2);
    expect(replay.playerStates['a']!.freeSkipsRemaining, 1);
    expect(replay.history, isEmpty);
  });
}
