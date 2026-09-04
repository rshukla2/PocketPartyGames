import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/party_widgets.dart';
import '../features/games/act_it_out_screen.dart';
import '../features/games/countdown_screen.dart';
import '../features/games/guess_number_screen.dart';
import '../features/games/imposter_screen.dart';
import '../features/games/imposter_engine.dart';
import '../features/games/pictionary_screen.dart';
import '../features/games/stop_timer_screen.dart';
import '../features/games/trivia_screen.dart';
import '../features/games/truth_dare_screen.dart';
import '../features/home/home_screens.dart';
import '../features/nearby/nearby_screen.dart';
import 'app_controller.dart';
import 'theme.dart';

class PocketPartyApp extends ConsumerStatefulWidget {
  const PocketPartyApp({super.key});

  @override
  ConsumerState<PocketPartyApp> createState() => _PocketPartyAppState();
}

class _PocketPartyAppState extends ConsumerState<PocketPartyApp> {
  late final GoRouter router = GoRouter(
    initialLocation: _initialLocation(ref.read(appControllerProvider)),
    routes: <RouteBase>[
      GoRoute(
        path: '/',
        builder: (BuildContext context, GoRouterState state) =>
            const LibraryScreen(),
      ),
      GoRoute(
        path: '/onboarding',
        builder: (BuildContext context, GoRouterState state) =>
            const OnboardingScreen(),
      ),
      GoRoute(
        path: '/players',
        builder: (BuildContext context, GoRouterState state) =>
            const PlayersScreen(),
      ),
      GoRoute(
        path: '/settings',
        builder: (BuildContext context, GoRouterState state) =>
            const SettingsScreen(),
      ),
      GoRoute(
        path: '/trivia-browser',
        builder: (BuildContext context, GoRouterState state) =>
            const DataBrowserScreen(),
      ),
      GoRoute(
        path: '/nearby',
        builder: (BuildContext context, GoRouterState state) => NearbyScreen(
          gameId: state.uri.queryParameters['game'],
          imposterSetup: state.extra is ImposterSetup
              ? state.extra! as ImposterSetup
              : null,
        ),
      ),
      GoRoute(
        path: '/game/:id',
        builder: (BuildContext context, GoRouterState state) =>
            switch (state.pathParameters['id']) {
              'trivia' => const TriviaScreen(),
              'imposter' => const ImposterScreen(),
              'stop-timer' => const StopTimerScreen(),
              'truth-dare' => const TruthDareScreen(),
              'pictionary' => const PictionaryScreen(),
              'guess-number' => const GuessNumberScreen(),
              'act-it-out' => const ActItOutScreen(),
              'countdown' => const CountdownScreen(),
              _ => const LibraryScreen(),
            },
      ),
    ],
    errorBuilder: (BuildContext context, GoRouterState state) => Scaffold(
      body: PartyBackground(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const PartyHero(
                  emoji: '🌀',
                  title: 'Room not found',
                  body: 'That party room does not exist.',
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => context.go('/'),
                  child: const Text('BACK TO GAMES'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  static String _initialLocation(AppState state) {
    if (!state.settings.tutorialCompleted) return '/onboarding';
    return state.players.isEmpty ? '/players' : '/';
  }

  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Pocket Party Games',
    debugShowCheckedModeBanner: false,
    theme: buildPartyTheme(),
    routerConfig: router,
  );
}
