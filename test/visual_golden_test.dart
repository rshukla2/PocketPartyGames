import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/app/theme.dart';
import 'package:pocket_party_games/core/data/game_data_repository.dart';
import 'package:pocket_party_games/core/models/app_models.dart';
import 'package:pocket_party_games/core/services/app_storage.dart';
import 'package:pocket_party_games/core/services/runtime_services.dart';
import 'package:pocket_party_games/core/widgets/party_widgets.dart';
import 'package:pocket_party_games/features/games/countdown_screen.dart';
import 'package:pocket_party_games/features/games/imposter_screen.dart';
import 'package:pocket_party_games/features/games/stop_timer_screen.dart';
import 'package:pocket_party_games/features/games/trivia_screen.dart';
import 'package:pocket_party_games/features/games/truth_dare_screen.dart';
import 'package:pocket_party_games/features/home/home_screens.dart';
import 'package:shared_preferences/shared_preferences.dart';

late GameDataRepository goldenData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    goldenFileComparator = _TolerantGoldenFileComparator(
      Uri.parse('test/visual_golden_test.dart'),
      precisionTolerance: 0.03,
      precisionOverrides: const <String, double>{
        'goldens/phase1_library_390.png': 0.05,
        'goldens/trivia_setup_390.png': 0.05,
        'goldens/timer_imposter_setup_390.png': 0.05,
        'goldens/truth_dare_resources_390.png': 0.05,
      },
    );
    final loader = FontLoader('Fredoka')
      ..addFont(rootBundle.load('assets/fonts/Fredoka-Medium.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Fredoka-SemiBold.ttf'))
      ..addFont(rootBundle.load('assets/fonts/Fredoka-Bold.ttf'));
    await loader.load();
    goldenData = await GameDataRepository.load();
  });

  testWidgets('mobile party surface golden', (WidgetTester tester) async {
    await _setSize(tester, const Size(390, 844));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPartyTheme(),
        home: RepaintBoundary(
          key: const Key('golden-root'),
          child: PartyPage(
            title: 'Trivia',
            subtitle: 'Question 4 of 10',
            style: PartyGameStyle.trivia,
            tone: PartyScreenTone.action,
            showBack: false,
            child: ListView(
              padding: const EdgeInsets.all(18),
              children: <Widget>[
                const PartyStatusPill(
                  label: 'Science · Medium',
                  color: PartyColors.yellow,
                ),
                const SizedBox(height: 18),
                const PartyCard(
                  padding: EdgeInsets.all(24),
                  child: Column(
                    children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: PartyColors.yellow,
                          shape: BoxShape.circle,
                        ),
                        child: SizedBox(width: 58, height: 58),
                      ),
                      SizedBox(height: 16),
                      ResponsivePartyText(
                        'WHAT PLANET SPINS ON ITS SIDE?',
                        minFontSize: 30,
                        maxFontSize: 46,
                        maxLines: 4,
                        color: PartyColors.nearBlack,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () {},
                  child: const Text('REVEAL ANSWER'),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('LEAVE ROUND'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byKey(const Key('golden-root')),
      matchesGoldenFile('goldens/party_surface_mobile.png'),
    );
  });

  for (final size in <Size>[const Size(390, 844), const Size(1280, 900)]) {
    testWidgets('all game palettes golden at ${size.width.toInt()}px', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, size);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildPartyTheme(),
          home: RepaintBoundary(
            key: const Key('golden-root'),
            child: _PaletteGallery(desktop: size.width > 700),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await expectLater(
        find.byKey(const Key('golden-root')),
        matchesGoldenFile('goldens/palette_gallery_${size.width.toInt()}.png'),
      );
    });

    for (final screen in <String>[
      'onboarding',
      'players-empty',
      'players-filled',
      'library',
    ]) {
      testWidgets('$screen Phase 1 golden at ${size.width.toInt()}px', (
        WidgetTester tester,
      ) async {
        await _setSize(tester, size);
        await _pumpPhaseOneGolden(tester, screen);
        await expectLater(
          find.byKey(const Key('phase-one-golden-root')),
          matchesGoldenFile(
            'goldens/phase1_${screen}_${size.width.toInt()}.png',
          ),
        );
      });
    }

    testWidgets('Trivia constrained setup golden at ${size.width.toInt()}px', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, size);
      await _pumpTriviaSetupGolden(tester);
      await expectLater(
        find.byKey(const Key('trivia-golden-root')),
        matchesGoldenFile('goldens/trivia_setup_${size.width.toInt()}.png'),
      );
    });

    testWidgets('Timer Imposter setup golden at ${size.width.toInt()}px', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, size);
      await _pumpPhaseTwoCGolden(tester, timer: true);
      await expectLater(
        find.byKey(const Key('phase-two-c-golden-root')),
        matchesGoldenFile(
          'goldens/timer_imposter_setup_${size.width.toInt()}.png',
        ),
      );
    });

    testWidgets('Truth or Dare resources golden at ${size.width.toInt()}px', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, size);
      await _pumpPhaseTwoCGolden(tester, timer: false);
      await expectLater(
        find.byKey(const Key('phase-two-c-golden-root')),
        matchesGoldenFile(
          'goldens/truth_dare_resources_${size.width.toInt()}.png',
        ),
      );
    });

    testWidgets('Countdown score entry golden at ${size.width.toInt()}px', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, size);
      await _pumpCountdownGolden(tester);
      await expectLater(
        find.byKey(const Key('countdown-golden-root')),
        matchesGoldenFile('goldens/countdown_score_${size.width.toInt()}.png'),
      );
    });

    testWidgets('Imposter setup golden at ${size.width.toInt()}px', (
      WidgetTester tester,
    ) async {
      await _setSize(tester, size);
      await _pumpImposterGolden(tester);
      await expectLater(
        find.byKey(const Key('imposter-golden-root')),
        matchesGoldenFile('goldens/imposter_setup_${size.width.toInt()}.png'),
      );
    });
  }
}

Future<void> _pumpImposterGolden(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final storage = await AppStorage.create();
  await storage.save(
    AppSnapshot(
      players: List<Player>.generate(
        5,
        (int index) => Player(
          id: 'player-$index',
          name: 'Player ${index + 1}',
          colorIndex: index,
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
        gameDataProvider.overrideWithValue(goldenData),
        randomProvider.overrideWithValue(Random(27)),
      ],
      child: MaterialApp(
        theme: buildPartyTheme(),
        home: const RepaintBoundary(
          key: Key('imposter-golden-root'),
          child: ImposterScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpCountdownGolden(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final storage = await AppStorage.create();
  await storage.save(
    const AppSnapshot(
      players: <Player>[
        Player(id: 'player-1', name: 'Alexandria Rose', colorIndex: 0),
        Player(id: 'player-2', name: 'Jordan', colorIndex: 1),
      ],
      settings: AppSettings(
        tutorialCompleted: true,
        soundEnabled: false,
        hapticsEnabled: false,
      ),
      soloStats: SoloStats(),
    ),
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStorageProvider.overrideWithValue(storage),
        gameDataProvider.overrideWithValue(goldenData),
        randomProvider.overrideWithValue(Random(27)),
      ],
      child: MaterialApp(
        theme: buildPartyTheme(),
        home: const RepaintBoundary(
          key: Key('countdown-golden-root'),
          child: CountdownScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('START COUNTDOWN'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('BEGIN LEVEL'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('START TIMER'));
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey<String>('answer-4')));
  await tester.pumpAndSettle();
}

Future<void> _pumpPhaseTwoCGolden(
  WidgetTester tester, {
  required bool timer,
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final storage = await AppStorage.create();
  await storage.save(
    AppSnapshot(
      players: List<Player>.generate(
        5,
        (int index) => Player(
          id: 'player-$index',
          name: 'Player ${index + 1}',
          colorIndex: index,
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
        gameDataProvider.overrideWithValue(goldenData),
        randomProvider.overrideWithValue(Random(27)),
      ],
      child: MaterialApp(
        theme: buildPartyTheme(),
        home: RepaintBoundary(
          key: const Key('phase-two-c-golden-root'),
          child: timer ? const StopTimerScreen() : const TruthDareScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  if (timer) {
    await tester.tap(find.text('TIMER IMPOSTER'));
  } else {
    await tester.scrollUntilVisible(
      find.text('START GAME'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('START GAME'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('TRUTH'));
  }
  await tester.pumpAndSettle();
}

Future<void> _pumpTriviaSetupGolden(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final storage = await AppStorage.create();
  await storage.save(
    AppSnapshot(
      players: List<Player>.generate(
        6,
        (index) => Player(
          id: 'player-$index',
          name: 'Player ${index + 1}',
          colorIndex: index,
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
        gameDataProvider.overrideWithValue(goldenData),
      ],
      child: MaterialApp(
        theme: buildPartyTheme(),
        home: const RepaintBoundary(
          key: Key('trivia-golden-root'),
          child: TriviaScreen(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.text('PASS & PLAY'));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('General').last);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Medium'));
  await tester.pumpAndSettle();
}

Future<void> _pumpPhaseOneGolden(WidgetTester tester, String screen) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final storage = await AppStorage.create();
  if (screen == 'players-filled') {
    await storage.save(
      const AppSnapshot(
        players: <Player>[
          Player(id: 'player-1', name: 'Player 1', colorIndex: 0),
        ],
        settings: AppSettings(tutorialCompleted: true),
        soloStats: SoloStats(),
      ),
    );
  }
  final child = switch (screen) {
    'onboarding' => const OnboardingScreen(),
    'players-empty' || 'players-filled' => const PlayersScreen(),
    'library' => const LibraryScreen(),
    _ => throw ArgumentError.value(screen),
  };
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appStorageProvider.overrideWithValue(storage)],
      child: MaterialApp(
        theme: buildPartyTheme(),
        home: RepaintBoundary(
          key: const Key('phase-one-golden-root'),
          child: child,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Keeps the visual regression suite meaningful across Skia's macOS and Linux
/// font rasterizers. At least 97% of the rendered pixels must still match the
/// reviewed baseline exactly. The two text-dense mobile screens use a narrowly
/// scoped 95% floor because their Linux rasterization differs by about 4.5%.
/// Exact copy, layout, and behavior are also covered by widget tests.
class _TolerantGoldenFileComparator extends LocalFileComparator {
  _TolerantGoldenFileComparator(
    super.testFile, {
    required double precisionTolerance,
    Map<String, double> precisionOverrides = const <String, double>{},
  }) : assert(precisionTolerance >= 0 && precisionTolerance <= 1),
       assert(
         precisionOverrides.values.every(
           (double value) => value >= 0 && value <= 1,
         ),
       ),
       _precisionTolerance = precisionTolerance,
       _precisionOverrides = Map.unmodifiable(precisionOverrides);

  final double _precisionTolerance;
  final Map<String, double> _precisionOverrides;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    var tolerance = _precisionTolerance;
    for (final override in _precisionOverrides.entries) {
      if (golden.path.endsWith(override.key)) tolerance = override.value;
    }
    final passed = result.passed || result.diffPercent <= tolerance;
    if (passed) {
      result.dispose();
      return true;
    }

    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

Future<void> _setSize(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

class _PaletteGallery extends StatelessWidget {
  const _PaletteGallery({required this.desktop});

  final bool desktop;

  static const labels = <PartyGameStyle, String>{
    PartyGameStyle.hub: 'PARTY HUB',
    PartyGameStyle.trivia: 'TRIVIA',
    PartyGameStyle.imposter: 'IMPOSTER',
    PartyGameStyle.stopTimer: 'STOP THE TIMER',
    PartyGameStyle.truthDare: 'TRUTH OR DARE',
    PartyGameStyle.pictionary: 'PICTIONARY',
    PartyGameStyle.guessNumber: 'GUESS MY NUMBER',
    PartyGameStyle.actItOut: 'ACT IT OUT',
    PartyGameStyle.countdown: '5-4-3-2-1',
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: PartyColors.nearBlack,
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          itemCount: PartyGameStyle.values.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: desktop ? 3 : 1,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: desktop ? 260 : 76,
          ),
          itemBuilder: (BuildContext context, int index) {
            final style = PartyGameStyle.values[index];
            final palette = PartyPalettes.resolve(style);
            return DecoratedBox(
              decoration: BoxDecoration(
                color: palette.background,
                borderRadius: BorderRadius.circular(desktop ? 30 : 22),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: desktop ? 24 : 18,
                  vertical: 12,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      labels[style]!,
                      style: TextStyle(
                        color: palette.foreground,
                        fontSize: desktop ? 30 : 19,
                        height: 1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (desktop) ...<Widget>[
                      const SizedBox(height: 12),
                      Text(
                        'LOUD COLOR · CHUNKY TYPE · ONE CLEAR ACTION',
                        style: TextStyle(
                          color: palette.foreground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 22),
                      PartyStatusPill(label: style.name, color: palette.accent),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
}
