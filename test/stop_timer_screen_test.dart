import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/app/theme.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/services/app_storage.dart';
import 'package:pocket_party_games/core/services/runtime_services.dart';
import 'package:pocket_party_games/core/widgets/party_widgets.dart';
import 'package:pocket_party_games/features/games/stop_timer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Buzzer uses first-to scoring and private sequential attempts', (
    WidgetTester tester,
  ) async {
    await _pumpStopTimer(tester, playerCount: 4);
    await _tapVisible(tester, find.text('BUZZER BATTLE'));

    expect(find.text('FIRST TO: 5 POINTS'), findsOneWidget);
    expect(find.textContaining('ROUNDS'), findsNothing);
    expect(find.byType(PartySlider), findsOneWidget);
    await _tapVisible(tester, find.text('START MATCH'));
    expect(find.text('TARGET TIME'), findsOneWidget);

    await _tapVisible(tester, find.text('HIDE TARGET & START TURNS'));
    for (var attempt = 0; attempt < 4; attempt++) {
      expect(
        find.text('START TIMER'),
        findsOneWidget,
        reason: 'attempt $attempt: ${_renderedText(tester)}',
      );
      expect(find.textContaining('Stopped'), findsNothing);
      await _tapVisible(tester, find.text('START TIMER'));
      expect(find.text('STOP!'), findsOneWidget);
      await tester.tap(find.text('STOP!'));
      await tester.pumpAndSettle();
    }

    expect(find.textContaining('TARGET '), findsWidgets);
    await _scrollVisible(tester, find.text('NEXT ROUND'));
    expect(
      find.text('NEXT ROUND'),
      findsOneWidget,
      reason: _renderedText(tester),
    );
    expect(find.textContaining('Player '), findsWidgets);
  });

  testWidgets('Timer Imposter offers both info modes and one-tap voting', (
    WidgetTester tester,
  ) async {
    await _pumpStopTimer(tester, playerCount: 5);
    await _tapVisible(tester, find.text('TIMER IMPOSTER'));

    expect(find.text('IMPOSTERS: 1'), findsOneWidget);
    expect(find.text('FALSE TARGET'), findsOneWidget);
    expect(find.text('NO TARGET'), findsOneWidget);
    await _tapVisible(tester, find.text('NO TARGET'));
    await _tapVisible(tester, find.text('DEAL SECRET INFO'));

    var sawImposter = false;
    for (var reveal = 0; reveal < 5; reveal++) {
      await _tapVisible(tester, find.text('SHOW SECRET INFO'));
      sawImposter = sawImposter || find.text('IMPOSTER').evaluate().isNotEmpty;
      await _tapVisible(
        tester,
        find.text(reveal == 4 ? 'START PRIVATE TURNS' : 'HIDE & PASS'),
      );
    }
    expect(sawImposter, isTrue);

    for (var attempt = 0; attempt < 5; attempt++) {
      expect(
        find.textContaining('previous times stay hidden'),
        findsOneWidget,
        reason: 'attempt $attempt: ${_renderedText(tester)}',
      );
      await _tapVisible(tester, find.text('START TIMER'));
      await tester.tap(find.text('STOP!'));
      await tester.pumpAndSettle();
    }

    expect(find.text('WHO IS AN IMPOSTER?'), findsOneWidget);
    expect(find.text('SUBMIT'), findsNothing);
    await _tapVisible(
      tester,
      find.byKey(const ValueKey<String>('timer-vote-p1')),
    );
    expect(
      find.textContaining(RegExp(r'(CREW|IMPOSTER)S? WINS')),
      findsOneWidget,
    );
    expect(find.textContaining('CREW TARGET'), findsOneWidget);
    expect(find.textContaining('NO TARGET'), findsWidgets);
  });

  testWidgets('timer setup remains usable at 200 percent text scale', (
    WidgetTester tester,
  ) async {
    await _pumpStopTimer(
      tester,
      playerCount: 5,
      textScaler: const TextScaler.linear(2),
    );
    await _tapVisible(tester, find.text('TIMER IMPOSTER'));
    await _scrollVisible(tester, find.text('DEAL SECRET INFO'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('DEAL SECRET INFO'), findsOneWidget);
  });
}

Future<void> _pumpStopTimer(
  WidgetTester tester, {
  required int playerCount,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final storage = await AppStorage.create();
  await storage.save(
    AppSnapshot(
      players: List<Player>.generate(
        playerCount,
        (int index) => Player(
          id: 'p${index + 1}',
          name: 'Player ${index + 1}',
          colorIndex: index % 8,
        ),
      ),
      settings: const AppSettings(tutorialCompleted: true),
      soloStats: const SoloStats(),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStorageProvider.overrideWithValue(storage),
        randomProvider.overrideWithValue(Random(19)),
      ],
      child: MaterialApp(
        theme: buildPartyTheme(),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(390, 844),
            textScaler: textScaler,
          ),
          child: const StopTimerScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await _scrollVisible(tester, finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _scrollVisible(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      finder,
      250,
      scrollable: find.byType(Scrollable).first,
    );
  } else {
    await tester.ensureVisible(finder);
  }
}

String _renderedText(WidgetTester tester) => tester
    .widgetList<Text>(find.byType(Text))
    .map((Text widget) => widget.data)
    .whereType<String>()
    .join(' | ');
