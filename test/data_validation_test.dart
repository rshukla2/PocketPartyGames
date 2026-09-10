import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/core/data/game_data_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all migrated prompt banks match their source counts and schemas',
    () async {
      final data = await GameDataRepository.load();
      expect(data.trivia, hasLength(2250));
      expect(data.truthOrDare, hasLength(500));
      expect(data.pictionary, hasLength(500));
      expect(data.acting, hasLength(600));
      expect(data.countdown, hasLength(316));
      expect(data.imposterWords, hasLength(727));
      expect(
        data.imposterWords.every(
          (word) => word.groupId.isNotEmpty && word.hint.isNotEmpty,
        ),
        isTrue,
      );
      expect(
        data.imposterWords.map((word) => word.groupId).toSet().length,
        120,
      );
      expect(
        data.trivia.map((question) => question.id).toSet(),
        hasLength(2250),
      );
      expect(
        data.truthOrDare.where((card) => card.category == 'Bold'),
        isNotEmpty,
      );
      expect(data.countdown.map((prompt) => prompt.level).toSet(), <int>{
        1,
        2,
        3,
        4,
        5,
      });
    },
  );

  test('expanded game data has the requested category distributions', () async {
    final data = await GameDataRepository.load();

    final triviaCategories = data.trivia
        .map((question) => question.category)
        .toSet();
    expect(triviaCategories, hasLength(15));
    expect(
      triviaCategories,
      containsAll(<String>{'gaming-esports', 'internet-memes'}),
    );
    for (final category in triviaCategories) {
      for (final difficulty in <String>['easy', 'medium', 'hard']) {
        expect(
          data.trivia.where(
            (question) =>
                question.category == category &&
                question.difficulty == difficulty,
          ),
          hasLength(50),
          reason: '$category should have 50 $difficulty questions',
        );
      }
    }

    final truthDareTargets = <(String, String), int>{
      ('Chill', 'truth'): 60,
      ('Chill', 'dare'): 60,
      ('Funny', 'truth'): 60,
      ('Funny', 'dare'): 60,
      ('Friends', 'truth'): 60,
      ('Friends', 'dare'): 60,
      ('Bold', 'truth'): 70,
      ('Bold', 'dare'): 70,
    };
    for (final entry in truthDareTargets.entries) {
      expect(
        data.truthOrDare.where(
          (card) => card.category == entry.key.$1 && card.type == entry.key.$2,
        ),
        hasLength(entry.value),
      );
    }

    for (final category
        in data.imposterWords.map((word) => word.category).toSet()) {
      expect(
        data.imposterWords
            .where((word) => word.category == category)
            .map((word) => word.groupId)
            .toSet(),
        hasLength(12),
        reason: '$category should have 12 Imposter word groups',
      );
    }
  });
}
