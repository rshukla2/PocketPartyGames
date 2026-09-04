import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/app/app_controller.dart';
import 'package:pocket_party_games/app/theme.dart';
import 'package:pocket_party_games/core/data/game_data_repository.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/services/app_storage.dart';
import 'package:pocket_party_games/core/services/runtime_services.dart';
import 'package:pocket_party_games/core/widgets/party_widgets.dart';
import 'package:pocket_party_games/features/games/imposter_engine.dart';
import 'package:pocket_party_games/features/games/imposter_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameDataRepository data;

  setUpAll(() async => data = await GameDataRepository.load());

  testWidgets('setup switches between Classic and Odd Word controls', (
    WidgetTester tester,
  ) async {
    await _pumpImposter(tester, data: data, players: _players(4));
    expect(find.text('IMPOSTER HINT'), findsOneWidget);
    expect(find.text('MULTIPLE ROUNDS'), findsOneWidget);
    expect(find.text('DEAL SECRET ROLES'), findsOneWidget);

    await tester.tap(find.text('ODD WORD'));
    await tester.pumpAndSettle();
    expect(find.text('IMPOSTER HINT'), findsNothing);
    expect(find.text('DEAL SECRET WORDS'), findsOneWidget);
  });

  testWidgets(
    'local game uses full names and immediate voting without Submit',
    (WidgetTester tester) async {
      final players = _players(4);
      await _pumpImposter(tester, data: data, players: players);
      await _tapVisible(tester, find.text('DEAL SECRET ROLES'));

      for (var index = 0; index < players.length; index++) {
        expect(find.byType(PlayerNameBadge), findsOneWidget);
        expect(find.text(players[index].name), findsWidgets);
        await tester.tap(find.text('SHOW MY ROLE'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.text(
            index + 1 == players.length ? 'START DISCUSSION' : 'HIDE & PASS',
          ),
        );
        await tester.pumpAndSettle();
      }

      expect(find.text('START VOTING'), findsOneWidget);
      await tester.tap(find.text('START VOTING'));
      await tester.pumpAndSettle();
      expect(find.text('WHO WAS VOTED OUT?'), findsOneWidget);
      expect(find.text('SUBMIT'), findsNothing);
      await tester.tap(find.text(players.first.name.toUpperCase()));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(RegExp(r'(CREW|IMPOSTER)S? WINS')),
        findsOneWidget,
      );
    },
  );

  testWidgets('multi-round Crew elimination restarts discussion with banner', (
    WidgetTester tester,
  ) async {
    final players = _players(4);
    final expected = const ImposterGameEngine().createMatch(
      setup: ImposterSetup(players: players, multipleRounds: true),
      words: data.imposterWords,
      random: Random(44),
    );
    final crewId = expected.assignments.values
        .firstWhere((value) => !value.isImposter)
        .playerId;
    final crew = players.firstWhere((value) => value.id == crewId);

    await _pumpImposter(tester, data: data, players: players);
    await _tapVisible(tester, find.text('MULTIPLE ROUNDS'));
    await _tapVisible(tester, find.text('DEAL SECRET ROLES'));
    for (var index = 0; index < players.length; index++) {
      await tester.tap(find.text('SHOW MY ROLE'));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(
          index + 1 == players.length ? 'START DISCUSSION' : 'HIDE & PASS',
        ),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('START VOTING'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(crew.name.toUpperCase()));
    await tester.pumpAndSettle();

    expect(find.textContaining('WAS NOT AN IMPOSTER'), findsOneWidget);
    expect(find.text('ROUND 2 · 3 PLAYERS LEFT'), findsOneWidget);
  });

  testWidgets('multiple rounds stays unavailable for three players', (
    WidgetTester tester,
  ) async {
    await _pumpImposter(tester, data: data, players: _players(3));
    expect(find.text('MULTIPLE ROUNDS'), findsNothing);
  });
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

List<Player> _players(int count) => List<Player>.generate(
  count,
  (int index) => Player(
    id: 'p$index',
    name: index == 0 ? 'Alexandria Rose' : 'Player ${index + 1}',
    colorIndex: index % 8,
  ),
);

Future<void> _pumpImposter(
  WidgetTester tester, {
  required GameDataRepository data,
  required List<Player> players,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final storage = await AppStorage.create();
  await storage.save(
    AppSnapshot(
      players: players,
      settings: const AppSettings(tutorialCompleted: true),
      soloStats: const SoloStats(),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appStorageProvider.overrideWithValue(storage),
        gameDataProvider.overrideWithValue(data),
        randomProvider.overrideWithValue(Random(44)),
      ],
      child: MaterialApp(
        theme: buildPartyTheme(),
        home: const ImposterScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
