import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/services/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('defaults provide a playable roster', () async {
    final storage = await AppStorage.create();
    final snapshot = storage.load();
    expect(snapshot.players.length, greaterThanOrEqualTo(2));
    expect(snapshot.settings.soundEnabled, isTrue);
  });

  test('corrupt and unsupported storage fall back safely', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pocket_party_v1_snapshot': '{broken',
    });
    expect((await AppStorage.create()).load().players, hasLength(4));

    SharedPreferences.setMockInitialValues(<String, Object>{
      'pocket_party_v1_snapshot': '{"schemaVersion":99}',
    });
    expect((await AppStorage.create()).load().players, hasLength(4));
  });

  test('saved settings, roster, and stats are restored', () async {
    final storage = await AppStorage.create();
    await storage.save(
      const AppSnapshot(
        players: <Player>[
          Player(id: '1', name: 'One', colorIndex: 0),
          Player(id: '2', name: 'Two', colorIndex: 1),
        ],
        settings: AppSettings(tutorialCompleted: true, hapticsEnabled: false),
        soloStats: SoloStats(attempts: 7, bestErrorMs: 12),
      ),
    );
    final restored = storage.load();
    expect(restored.players.map((Player player) => player.name), <String>[
      'One',
      'Two',
    ]);
    expect(restored.settings.tutorialCompleted, isTrue);
    expect(restored.soloStats.attempts, 7);
  });
}
