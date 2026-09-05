import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/app/theme.dart';
import 'package:pocket_party_games/core/data/game_data_repository.dart';
import 'package:pocket_party_games/core/services/app_storage.dart';
import 'package:pocket_party_games/core/widgets/party_widgets.dart';
import 'package:pocket_party_games/features/games/act_it_out_screen.dart';
import 'package:pocket_party_games/features/games/countdown_screen.dart';
import 'package:pocket_party_games/features/games/guess_number_screen.dart';
import 'package:pocket_party_games/features/games/imposter_screen.dart';
import 'package:pocket_party_games/features/games/pictionary_screen.dart';
import 'package:pocket_party_games/features/games/stop_timer_screen.dart';
import 'package:pocket_party_games/features/games/trivia_screen.dart';
import 'package:pocket_party_games/features/games/truth_dare_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppStorage storage;
  late GameDataRepository data;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    storage = await AppStorage.create();
    data = await GameDataRepository.load();
  });

  testWidgets('Act It Out setup fits a compact phone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStorageProvider.overrideWithValue(storage),
          gameDataProvider.overrideWithValue(data),
        ],
        child: MaterialApp(
          theme: buildPartyTheme(),
          home: const ActItOutScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('START LOCAL GAME'), findsOneWidget);
  });

  testWidgets('Guess My Number setup fits a compact phone', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStorageProvider.overrideWithValue(storage),
          gameDataProvider.overrideWithValue(data),
        ],
        child: MaterialApp(
          theme: buildPartyTheme(),
          home: const GuessNumberScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('START GAME'), findsOneWidget);
  });

  testWidgets('every game setup uses shared visible fields and sliders', (
    WidgetTester tester,
  ) async {
    final setupScreens = <(Widget, int, int)>[
      (const ImposterScreen(), 1, 1),
      (const TruthDareScreen(), 1, 0),
      (const PictionaryScreen(), 3, 0),
      (const GuessNumberScreen(), 1, 1),
      (const ActItOutScreen(), 3, 0),
    ];
    for (final (screen, fieldCount, sliderCount) in setupScreens) {
      await _pumpScreen(tester, screen, storage: storage, data: data);
      expect(
        _partyDropdownFields(),
        findsNWidgets(fieldCount),
        reason: '${screen.runtimeType} fields',
      );
      expect(
        find.byType(PartySlider),
        findsNWidgets(sliderCount),
        reason: '${screen.runtimeType} sliders',
      );
    }

    await _pumpScreen(
      tester,
      const TriviaScreen(),
      storage: storage,
      data: data,
    );
    await tester.tap(find.text('SOLO SPRINT'));
    await tester.pumpAndSettle();
    expect(_partyDropdownFields(), findsOneWidget);
    expect(find.byType(PartySlider), findsOneWidget);

    await _pumpScreen(
      tester,
      const StopTimerScreen(),
      storage: storage,
      data: data,
    );
    await tester.tap(find.text('BUZZER BATTLE'));
    await tester.pumpAndSettle();
    expect(find.byType(PartySlider), findsOneWidget);
  });

  for (final size in <Size>[const Size(390, 844), const Size(1280, 900)]) {
    testWidgets(
      'all eight setup screens render at ${size.width.toInt()}×${size.height.toInt()}',
      (WidgetTester tester) async {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final screens = <Widget>[
          const TriviaScreen(),
          const ImposterScreen(),
          const StopTimerScreen(),
          const TruthDareScreen(),
          const PictionaryScreen(),
          const GuessNumberScreen(),
          const ActItOutScreen(),
          const CountdownScreen(),
        ];
        for (final screen in screens) {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                appStorageProvider.overrideWithValue(storage),
                gameDataProvider.overrideWithValue(data),
              ],
              child: MaterialApp(theme: buildPartyTheme(), home: screen),
            ),
          );
          await tester.pumpAndSettle();
          final page = tester.widget<PartyPage>(find.byType(PartyPage));
          expect(
            page.centerTitle,
            isTrue,
            reason: '${screen.runtimeType} should center its game title',
          );
          expect(
            page.subtitle,
            isNull,
            reason: '${screen.runtimeType} setup should not market itself',
          );
          final exception = tester.takeException();
          if (exception is FlutterError) {
            // Keep the full render diagnostics visible when a responsive
            // regression is introduced.
            debugPrint(exception.toStringDeep());
          }
          expect(
            exception,
            isNull,
            reason: '${screen.runtimeType} should render at $size',
          );
        }
      },
    );
  }

  testWidgets('all eight setup screens support 130 and 200 percent text', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final screens = <Widget>[
      const TriviaScreen(),
      const ImposterScreen(),
      const StopTimerScreen(),
      const TruthDareScreen(),
      const PictionaryScreen(),
      const GuessNumberScreen(),
      const ActItOutScreen(),
      const CountdownScreen(),
    ];
    for (final scale in <double>[1.3, 2]) {
      for (final screen in screens) {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              appStorageProvider.overrideWithValue(storage),
              gameDataProvider.overrideWithValue(data),
            ],
            child: MaterialApp(
              theme: buildPartyTheme(),
              home: MediaQuery(
                data: MediaQueryData(
                  size: const Size(390, 844),
                  textScaler: TextScaler.linear(scale),
                ),
                child: screen,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final exception = tester.takeException();
        expect(
          exception,
          isNull,
          reason: '${screen.runtimeType} should support ${scale * 100}% text',
        );
      }
    }
  });
}

Finder _partyDropdownFields() =>
    find.byWidgetPredicate((widget) => widget is PartyDropdownField);

Future<void> _pumpScreen(
  WidgetTester tester,
  Widget screen, {
  required AppStorage storage,
  required GameDataRepository data,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appStorageProvider.overrideWithValue(storage),
        gameDataProvider.overrideWithValue(data),
      ],
      child: MaterialApp(theme: buildPartyTheme(), home: screen),
    ),
  );
  await tester.pumpAndSettle();
}
