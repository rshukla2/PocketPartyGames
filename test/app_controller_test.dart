import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/app/app_controller.dart';
import 'package:pocket_party_games/core/services/app_storage.dart';
import 'package:pocket_party_games/core/services/runtime_services.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = await AppStorage.create();
    container = ProviderContainer(
      overrides: [
        appStorageProvider.overrideWithValue(storage),
        appClockProvider.overrideWithValue(() => DateTime.utc(2026, 8, 26)),
      ],
    );
  });

  tearDown(() => container.dispose());

  test('player validation rejects bad and duplicate names', () async {
    final controller = container.read(appControllerProvider.notifier);
    expect(await controller.addPlayer('x'), contains('at least 2'));
    expect(
      await controller.addPlayer('a name that is much too long'),
      contains('at most 16'),
    );
    expect(await controller.addPlayer('RISHI'), contains('already'));
    expect(await controller.addPlayer('Taylor'), isNull);
    expect(container.read(appControllerProvider).players.last.name, 'Taylor');
  });

  test('roster enforces 20 maximum and 2 minimum', () async {
    final controller = container.read(appControllerProvider.notifier);
    for (var index = 0; index < 16; index++) {
      expect(await controller.addPlayer('Guest $index'), isNull);
    }
    expect(await controller.addPlayer('Overflow'), contains('20'));
    for (final player in List.of(
      container.read(appControllerProvider).players,
    ).take(18)) {
      await controller.removePlayer(player.id);
    }
    expect(container.read(appControllerProvider).players, hasLength(2));
    expect(
      await controller.removePlayer(
        container.read(appControllerProvider).players.first.id,
      ),
      contains('at least two'),
    );
  });

  test(
    'settings, onboarding, stats, player reset, and full reset persist',
    () async {
      final controller = container.read(appControllerProvider.notifier);
      await controller.completeTutorial();
      await controller.setSound(false);
      await controller.setHaptics(false);
      await controller.recordSoloAttempt(5, 5.04);
      expect(
        container.read(appControllerProvider).settings.tutorialCompleted,
        isTrue,
      );
      expect(
        container.read(appControllerProvider).settings.soundEnabled,
        isFalse,
      );
      expect(
        container.read(appControllerProvider).settings.hapticsEnabled,
        isFalse,
      );
      expect(
        container.read(appControllerProvider).soloStats.nearPerfectCount,
        1,
      );
      expect(
        container
            .read(appControllerProvider)
            .soloStats
            .history
            .single
            .timestamp,
        DateTime.utc(2026, 8, 26).millisecondsSinceEpoch,
      );
      await controller.addPlayer('Taylor');
      await controller.resetPlayers();
      expect(
        container
            .read(appControllerProvider)
            .players
            .map((player) => player.name),
        AppStorage.defaultPlayers.map((player) => player.name),
      );
      await controller.resetAll();
      expect(
        container.read(appControllerProvider).settings.tutorialCompleted,
        isFalse,
      );
      expect(container.read(appControllerProvider).soloStats.attempts, 0);
    },
  );
}
