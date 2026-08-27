import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';

final appStorageProvider = Provider<AppStorage>(
  (Ref ref) => throw StateError('AppStorage was not initialized'),
);

class AppStorage {
  AppStorage._(this._preferences);
  static const _snapshotKey = 'pocket_party_v1_snapshot';
  static final defaultPlayers = <Player>[
    const Player(id: 'player-1', name: 'Rishi', colorIndex: 0),
    const Player(id: 'player-2', name: 'Alex', colorIndex: 1),
    const Player(id: 'player-3', name: 'Sam', colorIndex: 2),
    const Player(id: 'player-4', name: 'Priya', colorIndex: 3),
  ];
  final SharedPreferences _preferences;

  static Future<AppStorage> create() async =>
      AppStorage._(await SharedPreferences.getInstance());

  AppSnapshot load() {
    try {
      final value = _preferences.getString(_snapshotKey);
      if (value == null) return defaults();
      final json = jsonDecode(value) as Map<String, dynamic>;
      if (json['schemaVersion'] != 1) return defaults();
      final players = (json['players'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .map(Player.fromJson)
          .where((Player player) => player.name.trim().isNotEmpty)
          .take(20)
          .toList();
      return AppSnapshot(
        players: players.length >= 2
            ? players
            : List<Player>.from(defaultPlayers),
        settings: AppSettings.fromJson(
          json['settings'] as Map<String, dynamic>? ?? <String, dynamic>{},
        ),
        soloStats: SoloStats.fromJson(
          json['soloStats'] as Map<String, dynamic>? ?? <String, dynamic>{},
        ),
      );
    } catch (_) {
      return defaults();
    }
  }

  AppSnapshot defaults() => AppSnapshot(
    players: List<Player>.from(defaultPlayers),
    settings: const AppSettings(),
    soloStats: const SoloStats(),
  );

  Future<void> save(AppSnapshot snapshot) =>
      _preferences.setString(_snapshotKey, snapshot.encode());
  Future<void> clear() => _preferences.remove(_snapshotKey);
}
