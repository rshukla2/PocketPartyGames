import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pocket_party_games/app/app.dart';
import 'package:pocket_party_games/app/app_controller.dart';
import 'package:pocket_party_games/app/theme.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/services/app_storage.dart';
import 'package:pocket_party_games/core/widgets/party_widgets.dart';
import 'package:pocket_party_games/features/home/home_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('onboarding covers all eight game families', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = await AppStorage.create();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStorageProvider.overrideWithValue(storage)],
        child: MaterialApp(
          theme: buildPartyTheme(),
          home: const OnboardingScreen(),
        ),
      ),
    );
    expect(find.text('PARTY GAMES'), findsOneWidget);
    expect(
      find.text('No accounts, subscriptions, or cloud required.'),
      findsOneWidget,
    );
    final expectedSlides = <(String, String)>[
      (
        'IMPOSTER',
        'Share a secret word, bluff confidently, discuss, and reveal the hidden imposters.',
      ),
      (
        'STOP THE TIMER',
        'Train solo, battle with buzzers, or give one timer imposter a false target.',
      ),
      (
        'TRUTH OR DARE',
        'Choose a Truth or Dare, pass the phone, and see how bold the party gets.',
      ),
      (
        'PICTIONARY',
        'Sketch, guess, and bluff your way through Quick Draw and Drawing Imposter.',
      ),
      (
        'GUESS MY NUMBER',
        'Hold the phone up, ask yes-or-no questions, and race the optional timer.',
      ),
      (
        'ACT IT OUT',
        'Act out wild prompts in Classic Charades or hide as the acting imposter.',
      ),
      (
        '5-4-3-2-1',
        'Name five things in five seconds, then descend through five rapid-fire levels.',
      ),
      (
        'TRIVIA',
        'Test your knowledge across several categories in solo, pass-and-play, or Nearby play.',
      ),
    ];
    for (final (title, body) in expectedSlides) {
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
      expect(find.text(title), findsOneWidget);
      expect(find.text(body), findsOneWidget);
      if (title == 'TRUTH OR DARE') {
        expect(
          tester.widget<StickerBadge>(find.byType(StickerBadge)).background,
          PartyColors.purple,
        );
      }
    }
    expect(find.textContaining('200 original'), findsNothing);
    expect(find.textContaining('194 drawing'), findsNothing);
    expect(find.textContaining('420 charades'), findsNothing);
    expect(find.textContaining('1,300 questions'), findsNothing);
  });

  testWidgets(
    'library offers eight reachable game cards with large touch targets',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = await AppStorage.create();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStorageProvider.overrideWithValue(storage)],
          child: MaterialApp(
            theme: buildPartyTheme(),
            home: const LibraryScreen(),
          ),
        ),
      );
      expect(find.text('TRIVIA'), findsOneWidget);
      expect(find.text('IMPOSTER'), findsOneWidget);
      expect(find.text('STOP THE TIMER'), findsOneWidget);
      expect(find.text('TRUTH OR DARE'), findsOneWidget);
      expect(find.text('Solo · Versus · Browse questions'), findsOneWidget);
      expect(find.text('Truth · Dare · Chill to Bold'), findsOneWidget);
      expect(find.text('Classic Charades · Acting Imposter'), findsOneWidget);
      expect(
        find.text('Rapid-fire · Score chase · Tiebreakers'),
        findsOneWidget,
      );
      expect(find.text('PICK A GAME.\nSTART SOME CHAOS.'), findsOneWidget);
      final libraryBackground = tester.widget<PartyBackground>(
        find.byType(PartyBackground),
      );
      expect(libraryBackground.palette, PartyPalettes.library);
      expect(
        libraryBackground.palette?.background,
        isNot(PartyPalettes.resolve(PartyGameStyle.imposter).background),
      );
      expect(find.textContaining('1,300'), findsNothing);
      expect(find.textContaining('200 cards'), findsNothing);
      expect(find.textContaining('420 prompts'), findsNothing);
      expect(find.text('8 games · One phone · Private LAN'), findsNothing);
      expect(
        find.text('100% playable offline · No accounts · No analytics'),
        findsNothing,
      );
      expect(find.text('PLAY ON NEARBY PHONES'), findsNWidgets(5));
      final truthDareSticker = tester
          .widgetList<StickerBadge>(find.byType(StickerBadge))
          .singleWhere((StickerBadge badge) => badge.emoji == '⚡');
      expect(truthDareSticker.background, PartyColors.purple);
    },
  );

  testWidgets(
    'player setup generates names and allows one player to continue',
    (WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = await AppStorage.create();
      final router = GoRouter(
        initialLocation: '/players',
        routes: <RouteBase>[
          GoRoute(path: '/players', builder: (_, _) => const PlayersScreen()),
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('GAME LIBRARY')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [appStorageProvider.overrideWithValue(storage)],
          child: MaterialApp.router(
            theme: buildPartyTheme(),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(const Key('player-name')),
      );
      expect(field.controller!.text, 'Player 1');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pick-a-game')))
            .onPressed,
        isNull,
      );
      expect(find.byTooltip('Go back'), findsNothing);
      expect(find.text('RESET DEFAULT ROSTER'), findsNothing);
      expect(find.text('Rishi'), findsNothing);

      field.controller!.clear();
      await tester.tap(find.byKey(const Key('add-player')));
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(PlayersScreen)),
      );
      expect(
        container.read(appControllerProvider).players.single.name,
        'Player 1',
      );
      expect(field.controller!.text, 'Player 2');
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('pick-a-game')))
            .onPressed,
        isNotNull,
      );

      await tester.tap(find.byKey(const Key('pick-a-game')));
      await tester.pumpAndSettle();
      expect(find.text('GAME LIBRARY'), findsOneWidget);
    },
  );

  testWidgets('completed onboarding with an empty roster opens player setup', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = await AppStorage.create();
    await storage.save(
      const AppSnapshot(
        players: <Player>[],
        settings: AppSettings(tutorialCompleted: true),
        soloStats: SoloStats(),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStorageProvider.overrideWithValue(storage)],
        child: const PocketPartyApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PlayersScreen), findsOneWidget);
  });

  testWidgets('completed onboarding with one player opens the library', (
    WidgetTester tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final storage = await AppStorage.create();
    await storage.save(
      const AppSnapshot(
        players: <Player>[Player(id: '1', name: 'Solo', colorIndex: 0)],
        settings: AppSettings(tutorialCompleted: true),
        soloStats: SoloStats(),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [appStorageProvider.overrideWithValue(storage)],
        child: const PocketPartyApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
  });

  for (final scale in <double>[1, 1.3, 2]) {
    testWidgets('Phase 1 screens fit at ${scale}x text', (
      WidgetTester tester,
    ) async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final storage = await AppStorage.create();
      for (final screen in <Widget>[
        const OnboardingScreen(),
        const PlayersScreen(),
        const LibraryScreen(),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appStorageProvider.overrideWithValue(storage)],
            child: MaterialApp(
              theme: buildPartyTheme(),
              builder: (BuildContext context, Widget? child) {
                final media = MediaQuery.of(context);
                return MediaQuery(
                  data: media.copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!,
                );
              },
              home: screen,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: screen.runtimeType.toString(),
        );
      }
    });
  }
}
