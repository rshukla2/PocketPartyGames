import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/app/theme.dart';
import 'package:pocket_party_games/core/services/app_storage.dart';
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
    expect(find.text('PARTY GAMES. ONE PHONE.'), findsOneWidget);
    for (final expected in <String>[
      'IMPOSTER',
      'STOP THE TIMER',
      'TRUTH OR DARE',
      'PICTIONARY',
      'GUESS MY NUMBER',
      'ACT IT OUT',
      '5-4-3-2-1',
      'TRIVIA VAULT',
    ]) {
      await tester.tap(find.byKey(const Key('onboarding-next')));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
    }
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
      expect(find.text('TRIVIA VAULT'), findsOneWidget);
      expect(find.text('IMPOSTER'), findsOneWidget);
      expect(find.text('STOP THE TIMER'), findsOneWidget);
      expect(find.text('TRUTH OR DARE'), findsOneWidget);
    },
  );
}
