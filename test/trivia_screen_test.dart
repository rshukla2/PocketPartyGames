import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/app/theme.dart';
import 'package:pocket_party_games/core/data/game_data_repository.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/services/app_storage.dart';
import 'package:pocket_party_games/core/services/runtime_services.dart';
import 'package:pocket_party_games/core/widgets/party_widgets.dart';
import 'package:pocket_party_games/features/games/trivia_screen.dart';
import 'package:pocket_party_games/features/home/home_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GameDataRepository data;

  setUpAll(() async {
    data = await GameDataRepository.load();
  });

  testWidgets('uses the Trivia name and corrected Solo setup controls', (
    tester,
  ) async {
    await _pumpTrivia(tester, data: data, players: _players(2));

    expect(find.text('TRIVIA'), findsOneWidget);
    expect(find.textContaining('Trivia Vault'), findsNothing);
    expect(find.textContaining('1,300'), findsNothing);
    final page = tester.widget<PartyPage>(find.byType(PartyPage));
    expect(page.centerTitle, isTrue);

    await tester.tap(find.text('SOLO SPRINT'));
    await tester.pumpAndSettle();

    expect(find.text('Solo Sprint setup'), findsOneWidget);
    expect(find.text('CATEGORY'), findsOneWidget);
    expect(find.text('All Categories'), findsOneWidget);
    final medium = tester.widget<Text>(find.text('Medium'));
    expect(medium.maxLines, 1);
    expect(medium.softWrap, isFalse);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.min, 5);
    expect(slider.max, 25);
    expect(slider.divisions, 20);
    final sliderTheme = tester.widget<SliderTheme>(find.byType(SliderTheme));
    expect(sliderTheme.data.activeTrackColor, PartyColors.yellow);
    expect(sliderTheme.data.inactiveTrackColor, PartyColors.white);
    expect(sliderTheme.data.thumbColor, PartyColors.nearBlack);
  });

  testWidgets('Pass & Play clamps a six-player Medium category to five', (
    tester,
  ) async {
    await _pumpTrivia(tester, data: data, players: _players(6));
    await tester.tap(find.text('PASS & PLAY'));
    await tester.pumpAndSettle();

    expect(find.text('Full set each'), findsOneWidget);
    expect(
      find.text('Finish your whole set, then pass the phone.'),
      findsOneWidget,
    );
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('General').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medium'));
    await tester.pumpAndSettle();

    expect(find.text('QUESTIONS PER PLAYER: 5'), findsOneWidget);
    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.max, 5);
    expect(slider.onChanged, isNull);
    expect(
      find.textContaining('Up to 5 unique questions per player'),
      findsOneWidget,
    );
  });

  testWidgets('full-set play keeps separate player scores and handoffs', (
    tester,
  ) async {
    await _pumpTrivia(tester, data: data, players: _players(2));
    await tester.tap(find.text('PASS & PLAY'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Easy'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Slider), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('QUESTIONS PER PLAYER: 5'), findsOneWidget);

    await tester.tap(find.text('START TRIVIA'));
    await tester.pumpAndSettle();
    expect(find.text('PASS TO PLAYER 1'), findsOneWidget);
    await tester.tap(find.text('PLAYER 1 IS READY'));
    await tester.pumpAndSettle();
    await _answerSet(tester, correct: true);

    expect(find.text('5 / 5 correct'), findsOneWidget);
    expect(find.text('5 POINTS'), findsOneWidget);
    await tester.tap(find.text('PASS THE PHONE'));
    await tester.pumpAndSettle();
    expect(find.text('PASS TO PLAYER 2'), findsOneWidget);
    await tester.tap(find.text('PLAYER 2 IS READY'));
    await tester.pumpAndSettle();
    await _answerSet(tester, correct: false);

    expect(find.text('0 / 5 correct'), findsOneWidget);
    expect(find.text('0 POINTS'), findsOneWidget);
    await tester.tap(find.text('SEE FINAL RESULTS'));
    await tester.pumpAndSettle();
    expect(find.text('PARTY PODIUM'), findsOneWidget);
    expect(find.text('5 pts'), findsOneWidget);
    expect(find.text('0 pts'), findsOneWidget);
  });

  testWidgets('Trivia setup has no critical overflow at supported scales', (
    tester,
  ) async {
    for (final scale in <double>[1, 1.3, 2]) {
      await _pumpTrivia(
        tester,
        data: data,
        players: _players(3),
        textScale: scale,
      );
      await tester.tap(find.text('PASS & PLAY'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'Failed at ${scale}x');
    }
  });

  testWidgets('Question Vault keeps its name without a count subtitle', (
    tester,
  ) async {
    await _pumpScreen(tester, data: data, child: const DataBrowserScreen());
    expect(find.text('QUESTION VAULT'), findsOneWidget);
    expect(find.textContaining('1,300'), findsNothing);
    expect(tester.widget<PartyPage>(find.byType(PartyPage)).subtitle, isNull);
  });
}

Future<void> _answerSet(WidgetTester tester, {required bool correct}) async {
  for (var index = 0; index < 5; index++) {
    await tester.ensureVisible(find.text('REVEAL ANSWER'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('REVEAL ANSWER'));
    await tester.pumpAndSettle();
    final resultButton = find.text(correct ? 'CORRECT' : 'MISSED');
    await tester.ensureVisible(resultButton);
    await tester.pumpAndSettle();
    await tester.tap(resultButton);
    await tester.pumpAndSettle();
  }
}

List<Player> _players(int count) => List<Player>.generate(
  count,
  (index) => Player(
    id: 'player-${index + 1}',
    name: 'Player ${index + 1}',
    colorIndex: index,
  ),
);

Future<void> _pumpTrivia(
  WidgetTester tester, {
  required GameDataRepository data,
  required List<Player> players,
  double textScale = 1,
}) => _pumpScreen(
  tester,
  data: data,
  players: players,
  textScale: textScale,
  child: const TriviaScreen(),
);

Future<void> _pumpScreen(
  WidgetTester tester, {
  required GameDataRepository data,
  required Widget child,
  List<Player> players = const <Player>[],
  double textScale = 1,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
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
      overrides: [
        appStorageProvider.overrideWithValue(storage),
        gameDataProvider.overrideWithValue(data),
        randomProvider.overrideWithValue(Random(44)),
      ],
      child: MaterialApp(
        theme: buildPartyTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: TextScaler.linear(textScale),
          ),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
