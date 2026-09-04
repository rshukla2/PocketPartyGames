import 'dart:convert';

const int lanProtocolVersion = 2;
const Duration lanReconnectGrace = Duration(seconds: 60);

class LanEnvelope {
  const LanEnvelope({
    required this.protocolVersion,
    required this.roomId,
    required this.messageId,
    required this.senderId,
    required this.clientSequence,
    required this.expectedRevision,
    required this.type,
    required this.payload,
  });

  final int protocolVersion;
  final String roomId;
  final String messageId;
  final String senderId;
  final int clientSequence;
  final int expectedRevision;
  final String type;
  final Map<String, dynamic> payload;

  factory LanEnvelope.fromJson(Map<String, dynamic> json) => LanEnvelope(
    protocolVersion: json['protocolVersion'] as int,
    roomId: json['roomId'] as String,
    messageId: json['messageId'] as String,
    senderId: json['senderId'] as String,
    clientSequence: json['clientSequence'] as int,
    expectedRevision: json['expectedRevision'] as int,
    type: json['type'] as String,
    payload: Map<String, dynamic>.from(json['payload'] as Map),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'protocolVersion': protocolVersion,
    'roomId': roomId,
    'messageId': messageId,
    'senderId': senderId,
    'clientSequence': clientSequence,
    'expectedRevision': expectedRevision,
    'type': type,
    'payload': payload,
  };

  String encode() => jsonEncode(toJson());
  factory LanEnvelope.decode(String value) =>
      LanEnvelope.fromJson(Map<String, dynamic>.from(jsonDecode(value) as Map));
}

class RoomMember {
  const RoomMember({
    required this.deviceId,
    required this.displayName,
    required this.connected,
    this.playerId,
    this.disconnectedAt,
    this.approved = false,
  });
  final String deviceId;
  final String displayName;
  final String? playerId;
  final bool approved;
  final bool connected;
  final DateTime? disconnectedAt;

  RoomMember copyWith({
    String? playerId,
    bool? approved,
    bool? connected,
    DateTime? disconnectedAt,
    bool clearDisconnectedAt = false,
  }) => RoomMember(
    deviceId: deviceId,
    displayName: displayName,
    playerId: playerId ?? this.playerId,
    approved: approved ?? this.approved,
    connected: connected ?? this.connected,
    disconnectedAt: clearDisconnectedAt
        ? null
        : disconnectedAt ?? this.disconnectedAt,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'deviceId': deviceId,
    'displayName': displayName,
    'playerId': playerId,
    'approved': approved,
    'connected': connected,
  };
}

class MajorityVote {
  MajorityVote({
    required this.id,
    required this.eligibleDeviceIds,
    required this.creatorId,
  });
  final String id;
  final Set<String> eligibleDeviceIds;
  final String creatorId;
  final Map<String, bool> ballots = <String, bool>{};

  VoteOutcome get outcome {
    final cast = ballots.values;
    final yes = cast.where((bool value) => value).length;
    final no = cast.length - yes;
    if (eligibleDeviceIds.length < 2) return VoteOutcome.creatorDecision;
    if (yes > cast.length / 2) return VoteOutcome.accepted;
    if (no > cast.length / 2) return VoteOutcome.rejected;
    if (cast.length == eligibleDeviceIds.length) {
      return VoteOutcome.creatorDecision;
    }
    return VoteOutcome.pending;
  }

  bool cast(String deviceId, bool value) {
    if (!eligibleDeviceIds.contains(deviceId) ||
        ballots.containsKey(deviceId)) {
      return false;
    }
    ballots[deviceId] = value;
    return true;
  }
}

enum VoteOutcome { pending, accepted, rejected, creatorDecision }

class LanCommandResult {
  const LanCommandResult({
    required this.accepted,
    required this.revision,
    required this.code,
    required this.snapshot,
  });
  final bool accepted;
  final int revision;
  final String code;
  final Map<String, dynamic> snapshot;
}

/// Authoritative, deterministic room state. The host owns this object and sends
/// only [projectionFor] results to clients, never the raw private-state map.
class LanRoomEngine {
  LanRoomEngine({
    required this.roomId,
    required this.creatorId,
    required this.gameId,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  final String roomId;
  final String creatorId;
  final String gameId;
  final DateTime Function() now;
  int revision = 0;
  String phase = 'lobby';
  final Map<String, RoomMember> members = <String, RoomMember>{};
  final Map<String, dynamic> shared = <String, dynamic>{};
  final Map<String, Map<String, dynamic>> privateByDevice =
      <String, Map<String, dynamic>>{};
  final Set<String> _messageIds = <String>{};
  final Map<String, int> _sequences = <String, int>{};

  void requestJoin(String deviceId, String displayName) {
    if (members.length >= 20 && !members.containsKey(deviceId)) {
      throw StateError('room_full');
    }
    final old = members[deviceId];
    members[deviceId] = old == null
        ? RoomMember(
            deviceId: deviceId,
            displayName: displayName,
            connected: true,
          )
        : old.copyWith(connected: true, clearDisconnectedAt: true);
    revision++;
  }

  void approve(String deviceId, {String? playerId}) {
    final member = members[deviceId];
    if (member == null) throw StateError('member_missing');
    if (playerId != null &&
        members.values.any(
          (RoomMember other) =>
              other.deviceId != deviceId && other.playerId == playerId,
        )) {
      throw StateError('player_claimed');
    }
    members[deviceId] = member.copyWith(approved: true, playerId: playerId);
    revision++;
  }

  void disconnected(String deviceId) {
    final member = members[deviceId];
    if (member == null) return;
    members[deviceId] = member.copyWith(
      connected: false,
      disconnectedAt: now(),
    );
    revision++;
  }

  List<RoomMember> removeExpiredMembers() {
    final cutoff = now().subtract(lanReconnectGrace);
    final expired = members.values
        .where(
          (RoomMember member) =>
              !member.connected &&
              member.disconnectedAt != null &&
              !member.disconnectedAt!.isAfter(cutoff),
        )
        .toList(growable: false);
    for (final member in expired) {
      members.remove(member.deviceId);
      privateByDevice.remove(member.deviceId);
    }
    if (expired.isNotEmpty) revision++;
    return expired;
  }

  LanCommandResult apply(
    LanEnvelope envelope, {
    String? authenticatedSenderId,
  }) {
    String? error;
    if (envelope.protocolVersion != lanProtocolVersion) {
      error = 'protocol_incompatible';
    } else if (envelope.roomId != roomId) {
      error = 'wrong_room';
    } else if (authenticatedSenderId != null &&
        authenticatedSenderId != envelope.senderId) {
      error = 'sender_mismatch';
    } else if (_messageIds.contains(envelope.messageId)) {
      error = 'duplicate';
    } else if (envelope.clientSequence <=
        (_sequences[envelope.senderId] ?? -1)) {
      error = 'stale_sequence';
    } else if (envelope.expectedRevision != revision) {
      error = 'stale_revision';
    }
    final member = members[envelope.senderId];
    if (error == null && (member == null || !member.approved)) {
      error = 'not_authorized';
    }
    if (error != null) {
      return LanCommandResult(
        accepted: false,
        revision: revision,
        code: error,
        snapshot: projectionFor(envelope.senderId),
      );
    }

    final creatorOnly = <String>{
      'configure',
      'removeMember',
      'resolveVote',
      'assignPlayer',
    };
    if (creatorOnly.contains(envelope.type) && envelope.senderId != creatorId) {
      return LanCommandResult(
        accepted: false,
        revision: revision,
        code: 'creator_only',
        snapshot: projectionFor(envelope.senderId),
      );
    }
    _messageIds.add(envelope.messageId);
    _sequences[envelope.senderId] = envelope.clientSequence;
    switch (envelope.type) {
      case 'configure':
        if (phase != 'lobby') {
          return LanCommandResult(
            accepted: false,
            revision: revision,
            code: 'phase_locked',
            snapshot: projectionFor(envelope.senderId),
          );
        }
        shared.addAll(envelope.payload);
      case 'transition':
        phase = envelope.payload['phase'] as String? ?? phase;
        shared.addAll(
          Map<String, dynamic>.from(
            envelope.payload['shared'] as Map? ?? const <String, dynamic>{},
          ),
        );
      case 'setReady':
        final ready = Map<String, dynamic>.from(
          shared['ready'] as Map? ?? const <String, dynamic>{},
        );
        ready[envelope.senderId] = envelope.payload['ready'] == true;
        shared['ready'] = ready;
      case 'gameCommand':
      // Game-specific validation and mutation are performed by the host's
      // authoritative feature session after this envelope is accepted.
      default:
        return LanCommandResult(
          accepted: false,
          revision: revision,
          code: 'unknown_command',
          snapshot: projectionFor(envelope.senderId),
        );
    }
    revision++;
    return LanCommandResult(
      accepted: true,
      revision: revision,
      code: 'accepted',
      snapshot: projectionFor(envelope.senderId),
    );
  }

  void setPrivateState(String deviceId, Map<String, dynamic> value) =>
      privateByDevice[deviceId] = Map<String, dynamic>.from(value);

  void recordHostMutation() => revision++;

  Map<String, dynamic> projectionFor(String deviceId) => <String, dynamic>{
    'protocolVersion': lanProtocolVersion,
    'roomId': roomId,
    'gameId': gameId,
    'revision': revision,
    'phase': phase,
    'members': members.values
        .map((RoomMember member) => member.toJson())
        .toList(),
    'shared': Map<String, dynamic>.from(shared),
    'private': Map<String, dynamic>.from(
      privateByDevice[deviceId] ?? const <String, dynamic>{},
    ),
  };
}
