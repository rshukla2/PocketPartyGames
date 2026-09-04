import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/core/data/game_data_repository.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/models/game_models.dart';
import 'package:pocket_party_games/features/games/imposter_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const engine = ImposterGameEngine();

  test(
    'classic assignments expose the word only to Crew and optional hints',
    () async {
      final data = await GameDataRepository.load();
      final match = engine.createMatch(
        setup: ImposterSetup(
          players: _players(6),
          category: 'Sports',
          imposterCount: 2,
          hintsEnabled: true,
        ),
        words: data.imposterWords,
        random: Random(8),
      );

      expect(
        match.assignments.values.where((value) => value.isImposter),
        hasLength(2),
      );
      for (final assignment in match.assignments.values) {
        if (assignment.isImposter) {
          expect(assignment.word, isNull);
          expect(assignment.hint, isNotEmpty);
        } else {
          expect(assignment.word, match.crewWord);
          expect(assignment.hint, isNull);
        }
      }
    },
  );

  test('Odd Word deals distinct alternatives first and then repeats', () {
    final words = <ImposterWord>[
      const ImposterWord(
        id: 'a',
        category: 'Test',
        word: 'Alpha',
        groupId: 'g',
        hint: 'Letter',
      ),
      const ImposterWord(
        id: 'b',
        category: 'Test',
        word: 'Beta',
        groupId: 'g',
        hint: 'Letter',
      ),
      const ImposterWord(
        id: 'c',
        category: 'Test',
        word: 'Gamma',
        groupId: 'g',
        hint: 'Letter',
      ),
    ];
    final match = engine.createMatch(
      setup: ImposterSetup(
        players: _players(7),
        category: 'Test',
        imposterCount: 3,
        mode: ImposterMode.oddWord,
        hintsEnabled: true,
      ),
      words: words,
      random: Random(4),
    );
    final oddWords = match.assignments.values
        .where((assignment) => assignment.isImposter)
        .map((assignment) => assignment.word)
        .toList();

    expect(oddWords.take(2).toSet(), hasLength(2));
    expect(oddWords[2], isIn(oddWords.take(2)));
    expect(oddWords, everyElement(isNot(match.crewWord)));
    expect(
      match.assignments.values,
      everyElement(
        predicate<ImposterAssignment>((value) => value.hint == null),
      ),
    );
    expect(
      match.assignments.values.map(
        (value) => value
            .privateProjection(ImposterMode.oddWord)
            .containsKey('isImposter'),
      ),
      everyElement(isFalse),
    );
  });

  test('single round resolves immediately from the selected player', () async {
    final data = await GameDataRepository.load();
    final created = engine.createMatch(
      setup: ImposterSetup(players: _players(4)),
      words: data.imposterWords,
      random: Random(2),
    );
    final voting = engine.beginVoting(engine.beginDiscussion(created));
    final imposter = voting.assignments.values.firstWhere(
      (value) => value.isImposter,
    );
    final crew = voting.assignments.values.firstWhere(
      (value) => !value.isImposter,
    );

    expect(
      engine.eliminate(voting, imposter.playerId).outcome,
      ImposterOutcome.crew,
    );
    expect(
      engine.eliminate(voting, crew.playerId).outcome,
      ImposterOutcome.imposters,
    );
  });

  test(
    'multi-round removes players and applies all-imposters and parity wins',
    () async {
      final data = await GameDataRepository.load();
      final created = engine.createMatch(
        setup: ImposterSetup(
          players: _players(5),
          imposterCount: 2,
          multipleRounds: true,
        ),
        words: data.imposterWords,
        random: Random(12),
      );
      final voting = engine.beginVoting(engine.beginDiscussion(created));
      final crew = voting.assignments.values.firstWhere(
        (value) => !value.isImposter,
      );
      final result = engine.eliminate(voting, crew.playerId);

      expect(result.phase, ImposterPhase.result);
      expect(result.outcome, ImposterOutcome.imposters);
      expect(result.activePlayerIds, isNot(contains(crew.playerId)));
    },
  );

  test(
    'nonterminal elimination starts another discussion with a banner',
    () async {
      final data = await GameDataRepository.load();
      final created = engine.createMatch(
        setup: ImposterSetup(
          players: _players(6),
          imposterCount: 1,
          multipleRounds: true,
        ),
        words: data.imposterWords,
        random: Random(14),
      );
      final voting = engine.beginVoting(engine.beginDiscussion(created));
      final crew = voting.assignments.values.firstWhere(
        (value) => !value.isImposter,
      );
      final next = engine.eliminate(voting, crew.playerId);

      expect(next.phase, ImposterPhase.discussion);
      expect(next.rounds, hasLength(2));
      expect(next.rounds.last.banner, contains('WAS NOT AN IMPOSTER'));
      expect(next.activePlayerIds, isNot(contains(crew.playerId)));
    },
  );

  test('Nearby ballots reject self, inactive, and duplicate votes and create a runoff', () {
    final box = ImposterBallotBox(
      activePlayerIds: <String>['a', 'b', 'c', 'd'],
      round: 1,
    );
    expect(box.cast('a', 'a'), isFalse);
    expect(box.cast('missing', 'a'), isFalse);
    expect(box.cast('a', 'b'), isTrue);
    expect(box.cast('a', 'c'), isFalse);
    expect(box.cast('b', 'a'), isTrue);
    expect(box.cast('c', 'd'), isTrue);
    expect(box.cast('d', 'c'), isTrue);
    final resolution = box.resolve();
    expect(resolution.eliminatedPlayerId, isNull);
    expect(
      resolution.runoffCandidates,
      unorderedEquals(<String>['a', 'b', 'c', 'd']),
    );

    final runoff = ImposterBallotBox(
      activePlayerIds: <String>['a', 'b', 'c', 'd'],
      candidates: resolution.runoffCandidates,
      round: 1,
      runoff: 1,
    );
    expect(runoff.cast('a', 'b'), isTrue);
    expect(runoff.cast('b', 'a'), isTrue);
    expect(runoff.cast('c', 'a'), isTrue);
    expect(runoff.cast('d', 'b'), isTrue);
    expect(runoff.resolve().creatorDecisionRequired, isTrue);
  });

  test('setup JSON preserves Nearby configuration', () {
    final setup = ImposterSetup(
      players: _players(8),
      category: 'Places',
      imposterCount: 3,
      discussionSeconds: 60,
      mode: ImposterMode.oddWord,
      multipleRounds: true,
    );
    final decoded = ImposterSetup.fromJson(setup.toJson());
    expect(decoded.players, hasLength(8));
    expect(decoded.category, 'Places');
    expect(decoded.imposterCount, 3);
    expect(decoded.discussionSeconds, 60);
    expect(decoded.mode, ImposterMode.oddWord);
    expect(decoded.multipleRounds, isTrue);
  });
}

List<Player> _players(int count) => List<Player>.generate(
  count,
  (int index) =>
      Player(id: 'p$index', name: 'Player ${index + 1}', colorIndex: index % 8),
);
