import 'lan_transport_types.dart';

export 'lan_transport_types.dart';

class _WebLanTransport implements LanTransport {
  @override
  bool get isSupported => false;
  @override
  Stream<LanDiscoveredRoom> get discoveredRooms =>
      const Stream<LanDiscoveredRoom>.empty();
  @override
  Stream<String> get messages => const Stream<String>.empty();
  @override
  Future<LanHostDetails> startHost({
    required String roomName,
    required String roomId,
    required String token,
  }) => throw UnsupportedError(
    'Nearby is available in the installed mobile app.',
  );
  @override
  Future<void> join({
    required String endpoint,
    required String roomId,
    required String token,
    required String fingerprint,
    required String deviceId,
    required String displayName,
  }) => throw UnsupportedError(
    'Nearby is available in the installed mobile app.',
  );
  @override
  Future<void> send(String message) => throw UnsupportedError(
    'Nearby is available in the installed mobile app.',
  );
  @override
  Future<void> dispose() async {}
}

LanTransport createLanTransport() => _WebLanTransport();
