import 'dart:math';

import '../../core/models/app_models.dart';
import '../../core/models/game_models.dart';

enum TruthDareTurnOutcome { completed, skipped, quit }

class TruthDarePlayerState {
  const TruthDarePlayerState({
    required this.playerId,
    this.swapsRemaining = 2,
    this.freeSkipsRemaining = 1,
    this.active = true,
  });

  final String playerId;
  final int swapsRemaining;
  final int freeSkipsRemaining;
  final bool active;

  TruthDarePlayerState copyWith({
    int? swapsRemaining,
    int? freeSkipsRemaining,
    bool? active,
  }) => TruthDarePlayerState(
    playerId: playerId,
    swapsRemaining: swapsRemaining ?? this.swapsRemaining,
    freeSkipsRemaining: freeSkipsRemaining ?? this.freeSkipsRemaining,
    active: active ?? this.active,
  );
}

class TruthDareTurnResult {
  const TruthDareTurnResult({
    required this.player,
    required this.card,
    required this.outcome,
  });

  final Player player;
  final TruthDareCard card;
  final TruthDareTurnOutcome outcome;
}

class TruthDareSession {
  const TruthDareSession({
    required this.playerStates,
    this.history = const <TruthDareTurnResult>[],
  });

  final Map<String, TruthDarePlayerState> playerStates;
  final List<TruthDareTurnResult> history;

  List<String> get activePlayerIds => playerStates.values
      .where((TruthDarePlayerState state) => state.active)
      .map((TruthDarePlayerState state) => state.playerId)
      .toList(growable: false);
}

class TruthDareGameEngine {
  const TruthDareGameEngine();

  TruthDareSession start(List<Player> players) {
    if (players.length < 2) {
      throw ArgumentError.value(
        players.length,
        'players',
        'Truth or Dare requires at least two players.',
      );
    }
    return TruthDareSession(
      playerStates: Map<String, TruthDarePlayerState>.unmodifiable(
        <String, TruthDarePlayerState>{
          for (final player in players)
            player.id: TruthDarePlayerState(playerId: player.id),
        },
      ),
    );
  }

  TruthDareSession useSwap(TruthDareSession session, String playerId) {
    final current = _activePlayer(session, playerId);
    if (current.swapsRemaining <= 0) throw StateError('no_swaps_remaining');
    return _replacePlayer(
      session,
      current.copyWith(swapsRemaining: current.swapsRemaining - 1),
    );
  }

  TruthDareSession recordTurn(
    TruthDareSession session, {
    required Player player,
    required TruthDareCard card,
    required TruthDareTurnOutcome outcome,
  }) {
    final current = _activePlayer(session, player.id);
    var updated = current;
    if (outcome == TruthDareTurnOutcome.skipped) {
      if (current.freeSkipsRemaining <= 0) {
        throw StateError('no_free_skips_remaining');
      }
      updated = current.copyWith(
        freeSkipsRemaining: current.freeSkipsRemaining - 1,
      );
    } else if (outcome == TruthDareTurnOutcome.quit) {
      if (current.freeSkipsRemaining > 0) {
        throw StateError('free_skip_still_available');
      }
      updated = current.copyWith(active: false);
    }
    final states = Map<String, TruthDarePlayerState>.from(session.playerStates)
      ..[player.id] = updated;
    return TruthDareSession(
      playerStates: Map<String, TruthDarePlayerState>.unmodifiable(states),
      history: List<TruthDareTurnResult>.unmodifiable(<TruthDareTurnResult>[
        ...session.history,
        TruthDareTurnResult(player: player, card: card, outcome: outcome),
      ]),
    );
  }

  String? nextPlayerId(
    TruthDareSession session, {
    required List<Player> roster,
    required String currentPlayerId,
    required bool randomRotation,
    required Random random,
  }) {
    final active = roster
        .where(
          (Player player) => session.playerStates[player.id]?.active == true,
        )
        .toList(growable: false);
    if (active.isEmpty) return null;
    if (randomRotation) {
      return active[random.nextInt(active.length)].id;
    }
    final currentIndex = roster.indexWhere(
      (Player player) => player.id == currentPlayerId,
    );
    for (var offset = 1; offset <= roster.length; offset++) {
      final candidate = roster[(currentIndex + offset) % roster.length];
      if (session.playerStates[candidate.id]?.active == true) {
        return candidate.id;
      }
    }
    return null;
  }

  TruthDarePlayerState _activePlayer(
    TruthDareSession session,
    String playerId,
  ) {
    final state = session.playerStates[playerId];
    if (state == null || !state.active) throw StateError('player_inactive');
    return state;
  }

  TruthDareSession _replacePlayer(
    TruthDareSession session,
    TruthDarePlayerState player,
  ) {
    final states = Map<String, TruthDarePlayerState>.from(session.playerStates)
      ..[player.playerId] = player;
    return TruthDareSession(
      playerStates: Map<String, TruthDarePlayerState>.unmodifiable(states),
      history: session.history,
    );
  }
}
