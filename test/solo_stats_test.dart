import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/core/models/app_models.dart';

void main() {
  test('solo ratings use the documented error boundaries', () {
    expect(ratingForError(.05), SoloRating.unbelievable);
    expect(ratingForError(.10), SoloRating.almostPerfect);
    expect(ratingForError(.25), SoloRating.amazing);
    expect(ratingForError(.50), SoloRating.great);
    expect(ratingForError(.51), SoloRating.tryAgain);
  });

  test('solo statistics retain totals, best error, near-perfect count, and bounded history', () {
    var stats = const SoloStats();
    for (var index = 0; index < 60; index++) {
      stats = stats.add(
        SoloAttempt(
          id: '$index',
          targetSeconds: 5,
          actualSeconds: index == 17 ? 5.01 : 5.2,
          timestamp: index,
        ),
      );
    }
    expect(stats.attempts, 60);
    expect(stats.bestErrorMs, 10);
    expect(stats.nearPerfectCount, 1);
    expect(stats.history, hasLength(50));
    expect(stats.history.first.id, '59');
  });

  test('snapshot round-trips every persistent field', () {
    final snapshot = AppSnapshot(
      players: const <Player>[
        Player(id: 'a', name: 'Ada', colorIndex: 3),
        Player(id: 'b', name: 'Ben', colorIndex: 4),
      ],
      settings: const AppSettings(tutorialCompleted: true, soundEnabled: false),
      soloStats: const SoloStats(
        attempts: 2,
        bestErrorMs: 42,
        nearPerfectCount: 1,
      ),
    );
    expect(snapshot.encode(), contains('"schemaVersion":1'));
    expect(snapshot.encode(), contains('"bestErrorMs":42'));
    expect(snapshot.encode(), contains('"Ada"'));
  });
}
