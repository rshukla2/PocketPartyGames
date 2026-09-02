import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/services/app_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('defaults provide an empty roster', () async {
    final storage = await AppStorage.create();
    final snapshot = storage.load();
    expect(snapshot.players, isEmpty);
    expect(snapshot.settings.soundEnabled, isTrue);
  });

  test('corrupt and unsupported storage fall back safely', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pocket_party_v1_snapshot': '{broken',
    });
    expect((await AppStorage.create()).load().players, isEmpty);

    SharedPreferences.setMockInitialValues(<String, Object>{
      'pocket_party_v1_snapshot': '{"schemaVersion":99}',
    });
    expect((await AppStorage.create()).load().players, isEmpty);
  });

  test('schema 1 clears roster but preserves settings and stats', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pocket_party_v1_snapshot': jsonEncode(<String, Object>{
        'schemaVersion': 1,
        'players': <Map<String, Object>>[
          <String, Object>{'id': '1', 'name': 'Rishi', 'colorIndex': 0},
          <String, Object>{'id': '2', 'name': 'Alex', 'colorIndex': 1},
        ],
        'settings': <String, Object>{
          'tutorialCompleted': true,
          'soundEnabled': false,
          'hapticsEnabled': false,
        },
        'soloStats': <String, Object>{
          'attempts': 7,
          'bestErrorMs': 12,
          'nearPerfectCount': 2,
          'history': <Object>[],
        },
      }),
    });
    final storage = await AppStorage.create();
    final migrated = storage.load();
    expect(migrated.players, isEmpty);
    expect(migrated.settings.tutorialCompleted, isTrue);
    expect(migrated.settings.soundEnabled, isFalse);
    expect(migrated.soloStats.attempts, 7);
    await Future<void>.delayed(Duration.zero);
    final preferences = await SharedPreferences.getInstance();
    final migratedJson = jsonDecode(
      preferences.getString('pocket_party_v1_snapshot')!,
    ) as Map<String, dynamic>;
    expect(migratedJson['schemaVersion'], 2);
    final reloaded = (await AppStorage.create()).load();
    expect(reloaded.players, isEmpty);
    expect(reloaded.settings.tutorialCompleted, isTrue);
  });

  test('schema 2 restores zero, one, and multiple players', () async {
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

    await storage.save(
      const AppSnapshot(
        players: <Player>[Player(id: '1', name: 'Solo', colorIndex: 0)],
        settings: AppSettings(tutorialCompleted: true),
        soloStats: SoloStats(),
      ),
    );
    expect(storage.load().players.single.name, 'Solo');

    await storage.save(
      const AppSnapshot(
        players: <Player>[],
        settings: AppSettings(tutorialCompleted: true),
        soloStats: SoloStats(),
      ),
    );
    expect(storage.load().players, isEmpty);
  });
}
