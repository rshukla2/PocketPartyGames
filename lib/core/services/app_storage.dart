import 'dart:async';
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
  static const _schemaVersion = 2;
  final SharedPreferences _preferences;

  static Future<AppStorage> create() async =>
      AppStorage._(await SharedPreferences.getInstance());

  AppSnapshot load() {
    try {
      final value = _preferences.getString(_snapshotKey);
      if (value == null) return defaults();
      final json = jsonDecode(value) as Map<String, dynamic>;
      final schemaVersion = (json['schemaVersion'] as num?)?.toInt();
      if (schemaVersion != 1 && schemaVersion != _schemaVersion) {
        return defaults();
      }
      final storedPlayers = (json['players'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(Player.fromJson)
          .where(
            (Player player) =>
                player.name.trim().isNotEmpty &&
                player.name.trim().length <= 16,
          )
          .take(20)
          .toList();
      final snapshot = AppSnapshot(
        // Version 1 shipped with a sample roster. Clear every legacy roster
        // once while retaining the user's other local settings and stats.
        players: schemaVersion == 1 ? const <Player>[] : storedPlayers,
        settings: AppSettings.fromJson(
          json['settings'] as Map<String, dynamic>? ?? <String, dynamic>{},
        ),
        soloStats: SoloStats.fromJson(
          json['soloStats'] as Map<String, dynamic>? ?? <String, dynamic>{},
        ),
      );
      if (schemaVersion == 1) unawaited(save(snapshot));
      return snapshot;
    } catch (_) {
      return defaults();
    }
  }

  AppSnapshot defaults() => AppSnapshot(
    players: const <Player>[],
    settings: const AppSettings(),
    soloStats: const SoloStats(),
  );

  Future<void> save(AppSnapshot snapshot) =>
      _preferences.setString(_snapshotKey, snapshot.encode());
  Future<void> clear() => _preferences.remove(_snapshotKey);
}
