import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/app/theme.dart';
import 'package:pocket_party_games/core/data/game_data_repository.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/services/app_storage.dart';
import 'package:pocket_party_games/core/services/runtime_services.dart';
import 'package:pocket_party_games/features/games/countdown_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late GameDataRepository data;

  setUpAll(() async => data = await GameDataRepository.load());

  testWidgets('timer expires into bounded answer selection', (
    WidgetTester tester,
  ) async {
    await _pumpCountdown(tester, data: data, players: _players(2));
    await _tapVisible(tester, find.text('START COUNTDOWN'));
    expect(find.text('NAME 5 · IN 5 SECONDS'), findsOneWidget);

    await _tapVisible(tester, find.text('BEGIN LEVEL'));
    await _tapVisible(tester, find.text('START TIMER'));
    expect(find.text('THEY DID IT!'), findsNothing);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.text('TIME’S UP'), findsOneWidget);
    expect(find.text('HOW MANY DID THEY ANSWER?'), findsOneWidget);
    for (var answer = 0; answer <= 5; answer++) {
      expect(find.byKey(ValueKey<String>('answer-$answer')), findsOneWidget);
    }
    expect(find.byKey(const ValueKey<String>('answer-6')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('countdown-continue')))
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const ValueKey<String>('answer-4')));
    await tester.pumpAndSettle();
    expect(find.text('+4 this level · 4 total'), findsOneWidget);
    await tester.tap(find.byKey(const Key('countdown-continue')));
    await tester.pumpAndSettle();

    expect(find.text('NAME 4 · IN 4 SECONDS'), findsOneWidget);
    expect(find.text('Player 1'), findsWidgets);
    expect(find.text('Player 2'), findsNothing);
  });

  testWidgets('timer feedback fires once and respects disabled settings', (
    WidgetTester tester,
  ) async {
    final enabledFeedback = _FakeFeedbackService();
    await _pumpCountdown(
      tester,
      data: data,
      players: _players(1),
      soundEnabled: true,
      hapticsEnabled: true,
      feedback: enabledFeedback,
    );
    await _tapVisible(tester, find.text('START COUNTDOWN'));
    await _tapVisible(tester, find.text('BEGIN LEVEL'));
    await _tapVisible(tester, find.text('START TIMER'));
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(enabledFeedback.alerts, 1);
    expect(enabledFeedback.impacts, 1);

    final disabledFeedback = _FakeFeedbackService();
    await _pumpCountdown(
      tester,
      data: data,
      players: _players(1),
      feedback: disabledFeedback,
    );
    await _tapVisible(tester, find.text('START COUNTDOWN'));
    await _tapVisible(tester, find.text('BEGIN LEVEL'));
    await _tapVisible(tester, find.text('START TIMER'));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(disabledFeedback.alerts, 0);
    expect(disabledFeedback.impacts, 0);
  });

  testWidgets('a player completes all levels before the next player', (
    WidgetTester tester,
  ) async {
    await _pumpCountdown(tester, data: data, players: _players(2));
    await _tapVisible(tester, find.text('START COUNTDOWN'));

    for (var level = 5; level >= 1; level--) {
      expect(find.text('Player 1'), findsWidgets);
      expect(find.text('NAME $level · IN $level SECONDS'), findsOneWidget);
      await _completeLevel(tester, level: level, answer: 0);
    }

    expect(find.text('Player 2'), findsWidgets);
    expect(find.text('NAME 5 · IN 5 SECONDS'), findsOneWidget);
  });

  testWidgets('equal final scores display co-winners without random tiebreak', (
    WidgetTester tester,
  ) async {
    await _pumpCountdown(tester, data: data, players: _players(2));
    await _tapVisible(tester, find.text('START COUNTDOWN'));

    for (var turn = 0; turn < 10; turn++) {
      final level = 5 - (turn % 5);
      await _completeLevel(tester, level: level, answer: 0);
    }

    expect(find.text('CO-WINNERS'), findsOneWidget);
    expect(find.text('PLAYER 1 & PLAYER 2'), findsOneWidget);
    expect(find.text('RUN RANDOM TIEBREAKER'), findsNothing);
    expect(find.text('🏆'), findsNWidgets(3));
  });

  testWidgets('score controls wrap at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    await _pumpCountdown(
      tester,
      data: data,
      players: _players(1),
      textScaler: const TextScaler.linear(2),
    );
    await _tapVisible(tester, find.text('START COUNTDOWN'));
    await _tapVisible(tester, find.text('BEGIN LEVEL'));
    await _tapVisible(tester, find.text('START TIMER'));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey<String>('answer-5')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disposing an active timer cancels future callbacks', (
    WidgetTester tester,
  ) async {
    await _pumpCountdown(tester, data: data, players: _players(1));
    await _tapVisible(tester, find.text('START COUNTDOWN'));
    await _tapVisible(tester, find.text('BEGIN LEVEL'));
    await _tapVisible(tester, find.text('START TIMER'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _completeLevel(
  WidgetTester tester, {
  required int level,
  required int answer,
}) async {
  await _tapVisible(tester, find.text('BEGIN LEVEL'));
  await _tapVisible(tester, find.text('START TIMER'));
  await tester.pump(Duration(seconds: level));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey<String>('answer-$answer')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('countdown-continue')));
  await tester.pumpAndSettle();
}

Future<void> _pumpCountdown(
  WidgetTester tester, {
  required GameDataRepository data,
  required List<Player> players,
  TextScaler textScaler = TextScaler.noScaling,
  bool soundEnabled = false,
  bool hapticsEnabled = false,
  PartyFeedbackService? feedback,
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
      settings: AppSettings(
        tutorialCompleted: true,
        soundEnabled: soundEnabled,
        hapticsEnabled: hapticsEnabled,
      ),
      soloStats: const SoloStats(),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStorageProvider.overrideWithValue(storage),
        gameDataProvider.overrideWithValue(data),
        randomProvider.overrideWithValue(Random(18)),
        partyFeedbackProvider.overrideWithValue(
          feedback ?? _FakeFeedbackService(),
        ),
      ],
      child: MaterialApp(
        theme: buildPartyTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: textScaler,
          ),
          child: const CountdownScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _FakeFeedbackService extends PartyFeedbackService {
  int alerts = 0;
  int impacts = 0;

  @override
  Future<void> playAlert() async => alerts++;

  @override
  Future<void> heavyImpact() async => impacts++;
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
    id: 'p${index + 1}',
    name: 'Player ${index + 1}',
    colorIndex: index % 8,
  ),
);
