import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/core/data/game_data_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'all migrated prompt banks match their source counts and schemas',
    () async {
      final data = await GameDataRepository.load();
      expect(data.trivia, hasLength(1300));
      expect(data.truthOrDare, hasLength(200));
      expect(data.pictionary, hasLength(194));
      expect(data.acting, hasLength(420));
      expect(data.countdown, hasLength(316));
      expect(data.imposterWords, hasLength(231));
      expect(
        data.imposterWords.every(
          (word) => word.groupId.isNotEmpty && word.hint.isNotEmpty,
        ),
        isTrue,
      );
      expect(
        data.imposterWords.map((word) => word.groupId).toSet().length,
        greaterThanOrEqualTo(40),
      );
      expect(
        data.trivia.map((question) => question.id).toSet(),
        hasLength(1300),
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
}
