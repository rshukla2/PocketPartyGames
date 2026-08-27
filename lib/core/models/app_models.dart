import 'dart:convert';

class Player {
  const Player({
    required this.id,
    required this.name,
    required this.colorIndex,
  });
  final String id;
  final String name;
  final int colorIndex;

  Player copyWith({String? id, String? name, int? colorIndex}) => Player(
    id: id ?? this.id,
    name: name ?? this.name,
    colorIndex: colorIndex ?? this.colorIndex,
  );

  factory Player.fromJson(Map<String, dynamic> json) => Player(
    id: json['id'] as String,
    name: json['name'] as String,
    colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'colorIndex': colorIndex,
  };
}

class AppSettings {
  const AppSettings({
    this.tutorialCompleted = false,
    this.soundEnabled = true,
    this.hapticsEnabled = true,
  });
  final bool tutorialCompleted;
  final bool soundEnabled;
  final bool hapticsEnabled;

  AppSettings copyWith({
    bool? tutorialCompleted,
    bool? soundEnabled,
    bool? hapticsEnabled,
  }) => AppSettings(
    tutorialCompleted: tutorialCompleted ?? this.tutorialCompleted,
    soundEnabled: soundEnabled ?? this.soundEnabled,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
  );

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    tutorialCompleted: json['tutorialCompleted'] as bool? ?? false,
    soundEnabled: json['soundEnabled'] as bool? ?? true,
    hapticsEnabled: json['hapticsEnabled'] as bool? ?? true,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'tutorialCompleted': tutorialCompleted,
    'soundEnabled': soundEnabled,
    'hapticsEnabled': hapticsEnabled,
  };
}

enum SoloRating { unbelievable, almostPerfect, amazing, great, tryAgain }

class SoloAttempt {
  const SoloAttempt({
    required this.id,
    required this.targetSeconds,
    required this.actualSeconds,
    required this.timestamp,
  });
  final String id;
  final double targetSeconds;
  final double actualSeconds;
  final int timestamp;
  double get errorSeconds => actualSeconds - targetSeconds;
  double get absoluteErrorSeconds => errorSeconds.abs();
  SoloRating get rating => ratingForError(absoluteErrorSeconds);

  factory SoloAttempt.fromJson(Map<String, dynamic> json) => SoloAttempt(
    id: json['id'] as String,
    targetSeconds: (json['targetSeconds'] as num).toDouble(),
    actualSeconds: (json['actualSeconds'] as num).toDouble(),
    timestamp: (json['timestamp'] as num).toInt(),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'targetSeconds': targetSeconds,
    'actualSeconds': actualSeconds,
    'timestamp': timestamp,
  };
}

SoloRating ratingForError(double error) {
  if (error <= .05) return SoloRating.unbelievable;
  if (error <= .10) return SoloRating.almostPerfect;
  if (error <= .25) return SoloRating.amazing;
  if (error <= .50) return SoloRating.great;
  return SoloRating.tryAgain;
}

class SoloStats {
  const SoloStats({
    this.attempts = 0,
    this.bestErrorMs,
    this.nearPerfectCount = 0,
    this.history = const <SoloAttempt>[],
  });
  final int attempts;
  final int? bestErrorMs;
  final int nearPerfectCount;
  final List<SoloAttempt> history;

  SoloStats add(SoloAttempt attempt) {
    final errorMs = (attempt.absoluteErrorSeconds * 1000).round();
    return SoloStats(
      attempts: attempts + 1,
      bestErrorMs: bestErrorMs == null || errorMs < bestErrorMs!
          ? errorMs
          : bestErrorMs,
      nearPerfectCount:
          nearPerfectCount + (attempt.absoluteErrorSeconds <= .10 ? 1 : 0),
      history: <SoloAttempt>[attempt, ...history].take(50).toList(),
    );
  }

  factory SoloStats.fromJson(Map<String, dynamic> json) => SoloStats(
    attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    bestErrorMs: (json['bestErrorMs'] as num?)?.toInt(),
    nearPerfectCount: (json['nearPerfectCount'] as num?)?.toInt() ?? 0,
    history: (json['history'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(SoloAttempt.fromJson)
        .take(50)
        .toList(),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'attempts': attempts,
    'bestErrorMs': bestErrorMs,
    'nearPerfectCount': nearPerfectCount,
    'history': history.map((SoloAttempt value) => value.toJson()).toList(),
  };
}

class AppSnapshot {
  const AppSnapshot({
    required this.players,
    required this.settings,
    required this.soloStats,
  });
  final List<Player> players;
  final AppSettings settings;
  final SoloStats soloStats;

  String encode() => jsonEncode(<String, dynamic>{
    'schemaVersion': 1,
    'players': players.map((Player player) => player.toJson()).toList(),
    'settings': settings.toJson(),
    'soloStats': soloStats.toJson(),
  });
}
