import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/models/game_models.dart';
import 'package:pocket_party_games/features/games/imposter_engine.dart';
import 'package:pocket_party_games/features/nearby/nearby_imposter_session.dart';

void main() {
  final words = <ImposterWord>[
    const ImposterWord(
      id: 'a',
      category: 'Test',
      word: 'Norway',
      groupId: 'nordic',
      hint: 'Northern Europe',
    ),
    const ImposterWord(
      id: 'b',
      category: 'Test',
      word: 'Sweden',
      groupId: 'nordic',
      hint: 'Northern Europe',
    ),
    const ImposterWord(
      id: 'c',
      category: 'Test',
      word: 'Finland',
      groupId: 'nordic',
      hint: 'Northern Europe',
    ),
    const ImposterWord(
      id: 'd',
      category: 'Test',
      word: 'Denmark',
      groupId: 'nordic',
      hint: 'Northern Europe',
    ),
  ];

  test('Classic projections expose only the recipient private assignment', () {
    final session = NearbyImposterSession(
      setup: ImposterSetup(
        players: _players(4),
        category: 'Test',
        hintsEnabled: true,
      ),
      words: words,
      random: Random(3),
    );
    for (final player in session.setup.players) {
      session.assignDevice('d-${player.id}', player.id);
    }
    final imposter = session.match.assignments.values.firstWhere(
      (value) => value.isImposter,
    );
    final projection = session.projectionFor('d-${imposter.playerId}');
    final private = Map<String, dynamic>.from(projection['private'] as Map);

    expect(private['isImposter'], isTrue);
    expect(private['word'], isNull);
    expect(private['hint'], isNotEmpty);
    expect(projection.toString(), isNot(contains(session.match.crewWord)));
  });

  test('Odd Word projections never reveal roles or another player word', () {
    final session = NearbyImposterSession(
      setup: ImposterSetup(
        players: _players(6),
        category: 'Test',
        imposterCount: 2,
        mode: ImposterMode.oddWord,
      ),
      words: words,
      random: Random(7),
    );
    for (final player in session.setup.players) {
      session.assignDevice('d-${player.id}', player.id);
    }
    final imposters = session.match.assignments.values
        .where((value) => value.isImposter)
        .toList();
    final first = session.projectionFor('d-${imposters.first.playerId}');
    final private = Map<String, dynamic>.from(first['private'] as Map);

    expect(private, isNot(contains('isImposter')));
    expect(private, isNot(contains('hint')));
    expect(first.toString(), isNot(contains(imposters.last.word!)));
  });

  test(
    'readiness starts a clocked discussion and private ballots stay hidden',
    () {
      final now = DateTime(2026, 1, 2, 3, 4, 5);
      final session = NearbyImposterSession(
        setup: ImposterSetup(
          players: _players(4),
          category: 'Test',
          discussionSeconds: 60,
        ),
        words: words,
        random: Random(2),
        now: () => now,
      );
      for (final player in session.setup.players) {
        session.assignDevice('d-${player.id}', player.id);
        session.markReady(player.id);
      }
      session.beginDiscussion(now);
      session.beginVoting();
      expect(session.discussionDeadline, isNull);
      expect(session.castVote('p0', 'p1').eliminatedPlayerId, isNull);

      final projection = session.projectionFor('d-p2');
      expect(projection.toString(), isNot(contains('p0:')));
      expect(
        Map<String, dynamic>.from(projection['private'] as Map)['hasVoted'],
        isFalse,
      );
    },
  );

  test('twenty simulated clients can ready, vote, and enter one runoff', () {
    final players = _players(20);
    final session = NearbyImposterSession(
      setup: ImposterSetup(
        players: players,
        category: 'Test',
        imposterCount: 9,
        mode: ImposterMode.oddWord,
        multipleRounds: true,
      ),
      words: words,
      random: Random(11),
    );
    for (var index = 0; index < players.length; index++) {
      session.assignDevice('d$index', players[index].id);
      session.markReady(players[index].id);
      expect(session.projectionFor('d$index')['private'], isNotEmpty);
    }
    expect(session.allPlayersReady, isTrue);
    session.beginDiscussion(DateTime(2026));
    session.beginVoting();
    for (var index = 0; index < players.length; index++) {
      session.castVote(
        players[index].id,
        players[(index + 1) % players.length].id,
      );
    }

    expect(session.match.phase, ImposterPhase.voting);
    expect(session.ballotBox!.runoff, 1);
    expect(session.ballotBox!.candidates, hasLength(20));
  });
}

List<Player> _players(int count) => List<Player>.generate(
  count,
  (int index) =>
      Player(id: 'p$index', name: 'Player ${index + 1}', colorIndex: index % 8),
);
