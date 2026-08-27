import 'dart:async';

class LanHostDetails {
  const LanHostDetails({
    required this.roomId,
    required this.joinCode,
    required this.qrPayload,
    required this.endpoint,
    required this.fingerprint,
  });
  final String roomId;
  final String joinCode;
  final String qrPayload;
  final String endpoint;
  final String fingerprint;
}

class LanDiscoveredRoom {
  const LanDiscoveredRoom({
    required this.name,
    required this.endpoint,
    required this.roomId,
    required this.fingerprint,
  });
  final String name;
  final String endpoint;
  final String roomId;
  final String fingerprint;
}

abstract class LanTransport {
  bool get isSupported;
  Stream<LanDiscoveredRoom> get discoveredRooms;
  Stream<String> get messages;
  Future<LanHostDetails> startHost({
    required String roomName,
    required String roomId,
    required String token,
  });
  Future<void> join({
    required String endpoint,
    required String roomId,
    required String token,
    required String fingerprint,
    required String deviceId,
    required String displayName,
  });
  Future<void> send(String message);
  Future<void> dispose();
}

LanTransport createLanTransport() =>
    throw UnsupportedError('Use conditional implementation');
