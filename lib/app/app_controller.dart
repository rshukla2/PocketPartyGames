import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/models/app_models.dart';
import '../core/services/app_storage.dart';
import '../core/services/runtime_services.dart';

class AppState {
  const AppState({
    required this.players,
    required this.settings,
    required this.soloStats,
  });
  final List<Player> players;
  final AppSettings settings;
  final SoloStats soloStats;

  AppState copyWith({
    List<Player>? players,
    AppSettings? settings,
    SoloStats? soloStats,
  }) => AppState(
    players: players ?? this.players,
    settings: settings ?? this.settings,
    soloStats: soloStats ?? this.soloStats,
  );
}

class AppController extends Notifier<AppState> {
  @override
  AppState build() {
    final snapshot = ref.read(appStorageProvider).load();
    return AppState(
      players: snapshot.players,
      settings: snapshot.settings,
      soloStats: snapshot.soloStats,
    );
  }

  Future<void> _persist() => ref
      .read(appStorageProvider)
      .save(
        AppSnapshot(
          players: state.players,
          settings: state.settings,
          soloStats: state.soloStats,
        ),
      );

  Future<String?> addPlayer(String rawName) async {
    final name = rawName.trim();
    if (name.length < 2) return 'Use at least 2 characters.';
    if (name.length > 16) return 'Names can be at most 16 characters.';
    if (state.players.length >= 20) return 'The roster already has 20 players.';
    if (state.players.any(
      (Player player) => player.name.toLowerCase() == name.toLowerCase(),
    )) {
      return 'That name is already in the roster.';
    }
    state = state.copyWith(
      players: <Player>[
        ...state.players,
        Player(
          id: const Uuid().v4(),
          name: name,
          colorIndex: state.players.length % 8,
        ),
      ],
    );
    await _persist();
    return null;
  }

  Future<String?> removePlayer(String id) async {
    if (state.players.length <= 2) {
      return 'Keep at least two players in the roster.';
    }
    state = state.copyWith(
      players: state.players.where((Player player) => player.id != id).toList(),
    );
    await _persist();
    return null;
  }

  Future<void> resetPlayers() async {
    state = state.copyWith(
      players: List<Player>.from(AppStorage.defaultPlayers),
    );
    await _persist();
  }

  Future<void> completeTutorial() async {
    state = state.copyWith(
      settings: state.settings.copyWith(tutorialCompleted: true),
    );
    await _persist();
  }

  Future<void> setSound(bool enabled) async {
    state = state.copyWith(
      settings: state.settings.copyWith(soundEnabled: enabled),
    );
    await _persist();
  }

  Future<void> setHaptics(bool enabled) async {
    state = state.copyWith(
      settings: state.settings.copyWith(hapticsEnabled: enabled),
    );
    await _persist();
  }

  Future<void> recordSoloAttempt(double target, double actual) async {
    final attempt = SoloAttempt(
      id: const Uuid().v4(),
      targetSeconds: target,
      actualSeconds: actual,
      timestamp: ref.read(appClockProvider)().millisecondsSinceEpoch,
    );
    state = state.copyWith(soloStats: state.soloStats.add(attempt));
    await _persist();
  }

  Future<void> resetAll() async {
    await ref.read(appStorageProvider).clear();
    final snapshot = ref.read(appStorageProvider).defaults();
    state = AppState(
      players: snapshot.players,
      settings: snapshot.settings,
      soloStats: snapshot.soloStats,
    );
  }
}

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);
