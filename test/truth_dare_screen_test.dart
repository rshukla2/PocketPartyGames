import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/app/theme.dart';
import 'package:pocket_party_games/core/data/game_data_repository.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/services/app_storage.dart';
import 'package:pocket_party_games/core/services/runtime_services.dart';
import 'package:pocket_party_games/features/games/truth_dare_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameDataRepository data;

  setUpAll(() async => data = await GameDataRepository.load());

  testWidgets('swap and free-skip limits are per player and quit is recorded', (
    WidgetTester tester,
  ) async {
    await _pumpTruthDare(tester, data);
    await _tapVisible(tester, find.text('START GAME'));

    await _tapVisible(tester, find.text('TRUTH'));
    expect(find.text('SWAP · 2 LEFT'), findsOneWidget);
    await _tapVisible(tester, find.text('SWAP · 2 LEFT'));
    expect(find.text('SWAP · 1 LEFT'), findsOneWidget);
    await _tapVisible(tester, find.text('SWAP · 1 LEFT'));
    final exhaustedSwap = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'SWAP · 0 LEFT'),
    );
    expect(exhaustedSwap.onPressed, isNull);

    await _tapVisible(tester, find.text('SKIP FREE · 1 LEFT'));
    expect(find.text('Player 2'), findsWidgets);
    await _tapVisible(tester, find.text('TRUTH'));
    expect(find.text('SWAP · 2 LEFT'), findsOneWidget);
    await _tapVisible(tester, find.text('DONE'));

    expect(find.text('Player 1'), findsWidgets);
    await _tapVisible(tester, find.text('TRUTH'));
    expect(find.text('QUIT'), findsOneWidget);
    await _tapVisible(tester, find.text('QUIT'));

    expect(find.text('Player 2'), findsWidgets);
    await _tapVisible(tester, find.text('END & VIEW SUMMARY'));
    expect(find.textContaining('FREE SKIP'), findsOneWidget);
    expect(find.textContaining('QUIT'), findsOneWidget);
    expect(find.textContaining('LEFT THE GAME: Player 1'), findsOneWidget);
  });

  testWidgets('resources reset when the game is replayed', (
    WidgetTester tester,
  ) async {
    await _pumpTruthDare(tester, data);
    await _tapVisible(tester, find.text('START GAME'));
    await _tapVisible(tester, find.text('DARE'));
    await _tapVisible(tester, find.text('SWAP · 2 LEFT'));
    await _tapVisible(tester, find.text('DONE'));
    await _tapVisible(tester, find.text('END & VIEW SUMMARY'));
    await _tapVisible(tester, find.text('PLAY AGAIN'));
    await _tapVisible(tester, find.text('DARE'));

    expect(find.text('SWAP · 2 LEFT'), findsOneWidget);
    expect(find.text('SKIP FREE · 1 LEFT'), findsOneWidget);
  });
}

Future<void> _pumpTruthDare(
  WidgetTester tester,
  GameDataRepository data,
) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final storage = await AppStorage.create();
  await storage.save(
    const AppSnapshot(
      players: <Player>[
        Player(id: 'p1', name: 'Player 1', colorIndex: 0),
        Player(id: 'p2', name: 'Player 2', colorIndex: 1),
      ],
      settings: AppSettings(tutorialCompleted: true),
      soloStats: SoloStats(),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStorageProvider.overrideWithValue(storage),
        gameDataProvider.overrideWithValue(data),
        randomProvider.overrideWithValue(Random(11)),
      ],
      child: MaterialApp(
        theme: buildPartyTheme(),
        home: const TruthDareScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}
