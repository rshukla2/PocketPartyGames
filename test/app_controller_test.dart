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

  test('player names support generated defaults and one character', () async {
    final controller = container.read(appControllerProvider.notifier);
    expect(container.read(appControllerProvider).players, isEmpty);
    expect(controller.suggestedPlayerName(), 'Player 1');
    expect(await controller.addPlayer('x'), isNull);
    expect(controller.suggestedPlayerName(), 'Player 2');
    expect(
      await controller.addPlayer('a name that is much too long'),
      contains('at most 16'),
    );
    expect(await controller.addPlayer('X'), contains('already'));
    expect(await controller.addPlayer(''), isNull);
    expect(container.read(appControllerProvider).players.last.name, 'Player 2');
    expect(controller.suggestedPlayerName(), 'Player 3');
  });

  test('roster enforces 20 maximum and permits zero players', () async {
    final controller = container.read(appControllerProvider.notifier);
    for (var index = 0; index < 20; index++) {
      expect(await controller.addPlayer('Guest $index'), isNull);
    }
    expect(await controller.addPlayer('Overflow'), contains('20'));
    for (final player in List.of(
      container.read(appControllerProvider).players,
    )) {
      expect(await controller.removePlayer(player.id), isNull);
    }
    expect(container.read(appControllerProvider).players, isEmpty);
  });

  test('settings, onboarding, stats, and full reset persist', () async {
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
    expect(container.read(appControllerProvider).soloStats.nearPerfectCount, 1);
    expect(
      container.read(appControllerProvider).soloStats.history.single.timestamp,
      DateTime.utc(2026, 8, 26).millisecondsSinceEpoch,
    );
    await controller.addPlayer('Taylor');
    await controller.resetAll();
    expect(
      container.read(appControllerProvider).settings.tutorialCompleted,
      isFalse,
    );
    expect(container.read(appControllerProvider).soloStats.attempts, 0);
    expect(container.read(appControllerProvider).players, isEmpty);
  });
}
