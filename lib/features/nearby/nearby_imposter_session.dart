import 'dart:math';

import '../../core/models/game_models.dart';
import '../games/imposter_engine.dart';
import 'lan_protocol.dart';

class NearbyImposterSession {
  NearbyImposterSession({
    required this.setup,
    required List<ImposterWord> words,
    required Random random,
    ImposterGameEngine engine = const ImposterGameEngine(),
    DateTime Function()? now,
  }) : _engine = engine,
       _now = now ?? DateTime.now,
       match = engine.createMatch(setup: setup, words: words, random: random);

  final ImposterSetup setup;
  final ImposterGameEngine _engine;
  final DateTime Function() _now;
  ImposterMatch match;
  final Map<String, String> devicePlayers = <String, String>{};
  final Set<String> readyPlayerIds = <String>{};
  ImposterBallotBox? ballotBox;
  List<String> creatorDecisionCandidates = <String>[];
  DateTime? discussionDeadline;

  List<String> get remotePlayerIds =>
      devicePlayers.values.toList(growable: false);

  List<String> get localPlayerIds => setup.players
      .map((player) => player.id)
      .where((String id) => !devicePlayers.containsValue(id))
      .toList(growable: false);

  void assignDevice(String deviceId, String playerId) {
    if (!setup.players.any((player) => player.id == playerId)) {
      throw StateError('player_missing');
    }
    if (devicePlayers.entries.any(
      (entry) => entry.key != deviceId && entry.value == playerId,
    )) {
      throw StateError('player_claimed');
    }
    devicePlayers[deviceId] = playerId;
  }

  void expireDevice(String deviceId) {
    final playerId = devicePlayers.remove(deviceId);
    if (playerId == null) return;
    readyPlayerIds.remove(playerId);
    if (!match.activePlayerIds.contains(playerId)) return;

    final oldBox = ballotBox;
    match = _engine.removeDisconnectedPlayer(match, playerId);
    creatorDecisionCandidates = creatorDecisionCandidates
        .where(match.activePlayerIds.contains)
        .toList(growable: false);
    if (match.phase == ImposterPhase.result || oldBox == null) {
      ballotBox = null;
      return;
    }

    final candidates = oldBox.candidates
        ?.where(match.activePlayerIds.contains)
        .toList(growable: false);
    final replacement = ImposterBallotBox(
      activePlayerIds: match.activePlayerIds,
      candidates: candidates?.isEmpty == true ? null : candidates,
      round: oldBox.round,
      runoff: oldBox.runoff,
    );
    for (final vote in oldBox.votes.values) {
      if (match.activePlayerIds.contains(vote.voterId) &&
          (replacement.candidates ?? match.activePlayerIds).contains(
            vote.targetPlayerId,
          )) {
        replacement.cast(vote.voterId, vote.targetPlayerId);
      }
    }
    ballotBox = replacement;
    _applyResolution(replacement.resolve());
  }

  void markReady(String playerId) {
    if (!match.activePlayerIds.contains(playerId)) {
      throw StateError('player_inactive');
    }
    readyPlayerIds.add(playerId);
  }

  bool get allPlayersReady =>
      match.activePlayerIds.every(readyPlayerIds.contains);

  void beginDiscussion(DateTime now) {
    if (!allPlayersReady && match.rounds.length == 1) {
      throw StateError('players_not_ready');
    }
    match = _engine.beginDiscussion(match);
    discussionDeadline = setup.discussionSeconds == 0
        ? null
        : now.add(Duration(seconds: setup.discussionSeconds));
  }

  void beginVoting() {
    if (match.phase != ImposterPhase.discussion) {
      throw StateError('wrong_phase');
    }
    match = _engine.beginVoting(match);
    ballotBox = ImposterBallotBox(
      activePlayerIds: match.activePlayerIds,
      round: match.rounds.last.number,
    );
    creatorDecisionCandidates = <String>[];
    discussionDeadline = null;
  }

  ImposterVoteResolution castVote(String voterId, String targetPlayerId) {
    final box = ballotBox;
    if (match.phase != ImposterPhase.voting || box == null) {
      throw StateError('wrong_phase');
    }
    if (!box.cast(voterId, targetPlayerId)) {
      throw StateError('invalid_vote');
    }
    final resolution = box.resolve();
    _applyResolution(resolution);
    return resolution;
  }

  void _applyResolution(ImposterVoteResolution resolution) {
    if (resolution.eliminatedPlayerId != null) {
      _eliminate(resolution.eliminatedPlayerId!);
    } else if (resolution.runoffCandidates.isNotEmpty) {
      if (resolution.creatorDecisionRequired) {
        creatorDecisionCandidates = resolution.runoffCandidates;
      } else {
        ballotBox = ImposterBallotBox(
          activePlayerIds: match.activePlayerIds,
          candidates: resolution.runoffCandidates,
          round: match.rounds.last.number,
          runoff: 1,
        );
      }
    }
  }

  void resolveCreator(String targetPlayerId) {
    if (!creatorDecisionCandidates.contains(targetPlayerId)) {
      throw StateError('invalid_creator_decision');
    }
    _eliminate(targetPlayerId);
  }

  void _eliminate(String playerId) {
    match = _engine.eliminate(match, playerId);
    ballotBox = null;
    creatorDecisionCandidates = <String>[];
    if (match.phase == ImposterPhase.discussion) {
      discussionDeadline = setup.discussionSeconds == 0
          ? null
          : _now().add(Duration(seconds: setup.discussionSeconds));
    }
  }

  Map<String, dynamic> projectionFor(String deviceId) {
    final playerId = devicePlayers[deviceId];
    final assignment = playerId == null ? null : match.assignments[playerId];
    final isResult = match.phase == ImposterPhase.result;
    return <String, dynamic>{
      'type': 'imposterSnapshot',
      'protocolVersion': lanProtocolVersion,
      'phase': match.phase.name,
      'mode': setup.mode.name,
      'players': setup.players.map((player) => player.toJson()).toList(),
      'activePlayerIds': match.activePlayerIds,
      'round': match.rounds.last.number,
      'banner': match.rounds.last.banner,
      'discussionDeadline': discussionDeadline?.millisecondsSinceEpoch,
      'runoffCandidates': ballotBox?.candidates ?? const <String>[],
      'creatorDecisionCandidates': creatorDecisionCandidates,
      if (isResult) ...<String, dynamic>{
        'outcome': match.outcome!.name,
        'crewWord': match.crewWord,
        'imposters': match.assignments.values
            .where((assignment) => assignment.isImposter)
            .map(
              (assignment) => <String, dynamic>{
                'playerId': assignment.playerId,
                if (setup.mode == ImposterMode.oddWord) 'word': assignment.word,
              },
            )
            .toList(),
      },
      'private': <String, dynamic>{
        'playerId': ?playerId,
        ...?assignment != null && !isResult
            ? assignment.privateProjection(setup.mode)
            : null,
        if (playerId != null) 'ready': readyPlayerIds.contains(playerId),
        if (playerId != null)
          'hasVoted': ballotBox?.votes.containsKey(playerId) ?? false,
      },
    };
  }
}
