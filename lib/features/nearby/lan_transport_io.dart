import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:basic_utils/basic_utils.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:crypto/crypto.dart';

import 'lan_protocol.dart';
import 'lan_transport_types.dart';

export 'lan_transport_types.dart';

const String _serviceType = '_pocketparty._tcp';

class _NativeLanTransport implements LanTransport {
  final StreamController<LanDiscoveredRoom> _rooms =
      StreamController<LanDiscoveredRoom>.broadcast();
  final StreamController<String> _messages =
      StreamController<String>.broadcast();
  final Set<WebSocket> _clients = <WebSocket>{};
  final Map<String, List<DateTime>> _joinFailures = <String, List<DateTime>>{};
  HttpServer? _server;
  WebSocket? _socket;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  String? _roomId;
  String? _token;

  _NativeLanTransport() {
    unawaited(_startDiscovery());
  }

  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;
  @override
  Stream<LanDiscoveredRoom> get discoveredRooms => _rooms.stream;
  @override
  Stream<String> get messages => _messages.stream;

  Future<void> _startDiscovery() async {
    if (!isSupported) return;
    final discovery = BonsoirDiscovery(type: _serviceType, printLogs: false);
    _discovery = discovery;
    await discovery.initialize();
    discovery.eventStream?.listen((BonsoirDiscoveryEvent event) {
      if (event is BonsoirDiscoveryServiceFoundEvent) {
        discovery.serviceResolver.resolveService(event.service);
      }
      if (event is BonsoirDiscoveryServiceResolvedEvent ||
          event is BonsoirDiscoveryServiceUpdatedEvent) {
        final service = event.service!;
        final host = service.hostAddress ?? service.hostname;
        final roomId = service.attributes['room'];
        if (host != null && roomId != null) {
          _rooms.add(
            LanDiscoveredRoom(
              name: service.name,
              endpoint: '$host:${service.port}',
              roomId: roomId,
              fingerprint: service.attributes['fp'] ?? '',
            ),
          );
        }
      }
    });
    await discovery.start();
  }

  @override
  Future<LanHostDetails> startHost({
    required String roomName,
    required String roomId,
    required String token,
  }) async {
    if (!isSupported) throw UnsupportedError('Nearby requires Android or iOS.');
    await _server?.close(force: true);
    _roomId = roomId;
    _token = token;
    final keyPair = CryptoUtils.generateRSAKeyPair();
    final privateKey = keyPair.privateKey as RSAPrivateKey;
    final publicKey = keyPair.publicKey as RSAPublicKey;
    final csr = X509Utils.generateRsaCsrPem(
      <String, String>{'CN': 'Pocket Party $roomId'},
      privateKey,
      publicKey,
      san: <String>['pocketparty.local'],
    );
    final certificate = X509Utils.generateSelfSignedCertificate(
      privateKey,
      csr,
      1,
      sans: <String>['pocketparty.local'],
    );
    final privatePem = CryptoUtils.encodeRSAPrivateKeyToPem(privateKey);
    final context = SecurityContext()
      ..useCertificateChainBytes(utf8.encode(certificate))
      ..usePrivateKeyBytes(utf8.encode(privatePem));
    final fingerprint = sha256.convert(_pemBytes(certificate)).toString();
    final server = await HttpServer.bindSecure(
      InternetAddress.anyIPv4,
      0,
      context,
      shared: true,
    );
    _server = server;
    server.listen(_handleRequest);
    final endpoint = '${await _localAddress()}:${server.port}';
    final service = BonsoirService(
      name: roomName,
      type: _serviceType,
      port: server.port,
      attributes: <String, String>{
        'room': roomId,
        'v': '$lanProtocolVersion',
        'fp': fingerprint,
      },
    );
    final broadcast = BonsoirBroadcast(service: service, printLogs: false);
    _broadcast = broadcast;
    await broadcast.initialize();
    await broadcast.start();
    final joinCode = token.substring(0, 6).toUpperCase();
    final qr = jsonEncode(<String, dynamic>{
      'protocolVersion': lanProtocolVersion,
      'roomId': roomId,
      'endpoint': endpoint,
      'fingerprint': fingerprint,
      'token': token,
    });
    return LanHostDetails(
      roomId: roomId,
      joinCode: joinCode,
      qrPayload: qr,
      endpoint: endpoint,
      fingerprint: fingerprint,
    );
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (!WebSocketTransformer.isUpgradeRequest(request)) {
      request.response
        ..statusCode = HttpStatus.upgradeRequired
        ..write('Pocket Party Games room');
      await request.response.close();
      return;
    }
    final ip = request.connectionInfo?.remoteAddress.address ?? 'unknown';
    final failures = (_joinFailures[ip] ?? <DateTime>[])
        .where(
          (DateTime time) =>
              DateTime.now().difference(time) < const Duration(minutes: 1),
        )
        .toList();
    _joinFailures[ip] = failures;
    if (failures.length >= 5) {
      request.response.statusCode = HttpStatus.tooManyRequests;
      await request.response.close();
      return;
    }
    final socket = await WebSocketTransformer.upgrade(request);
    var authorized = false;
    _clients.add(socket);
    Timer(const Duration(seconds: 8), () {
      if (!authorized) {
        unawaited(
          socket.close(WebSocketStatus.policyViolation, 'Join timed out'),
        );
      }
    });
    socket.listen(
      (dynamic raw) {
        if (raw is! String) return;
        if (!authorized) {
          try {
            final auth = Map<String, dynamic>.from(jsonDecode(raw) as Map);
            final supplied = (auth['token'] as String? ?? '').toUpperCase();
            final valid =
                supplied == _token ||
                supplied == _token!.substring(0, 6).toUpperCase();
            if (auth['roomId'] != _roomId || !valid) {
              throw const FormatException('Invalid room token');
            }
            authorized = true;
            _messages.add(
              jsonEncode(<String, dynamic>{'type': 'joinRequest', ...auth}),
            );
            socket.add(jsonEncode(<String, dynamic>{'type': 'authenticated'}));
          } catch (_) {
            failures.add(DateTime.now());
            unawaited(
              socket.close(
                WebSocketStatus.policyViolation,
                'Invalid join details',
              ),
            );
          }
          return;
        }
        _messages.add(raw);
        for (final peer in _clients.where((WebSocket peer) => peer != socket)) {
          peer.add(raw);
        }
      },
      onDone: () => _clients.remove(socket),
      onError: (_) => _clients.remove(socket),
      cancelOnError: true,
    );
  }

  @override
  Future<void> join({
    required String endpoint,
    required String roomId,
    required String token,
    required String fingerprint,
    required String deviceId,
    required String displayName,
  }) async {
    if (!isSupported) throw UnsupportedError('Nearby requires Android or iOS.');
    final client = HttpClient()
      ..badCertificateCallback =
          (X509Certificate certificate, String host, int port) =>
              sha256.convert(certificate.der).toString().toLowerCase() ==
              fingerprint.toLowerCase();
    final socket = await WebSocket.connect(
      'wss://$endpoint',
      customClient: client,
    ).timeout(const Duration(seconds: 8));
    _socket = socket;
    socket.add(
      jsonEncode(<String, dynamic>{
        'roomId': roomId,
        'token': token,
        'deviceId': deviceId,
        'displayName': displayName,
      }),
    );
    socket.listen(
      (dynamic message) {
        if (message is String) _messages.add(message);
      },
      onDone: () => _messages.add(
        jsonEncode(<String, dynamic>{'type': 'hostDisconnected'}),
      ),
      cancelOnError: true,
    );
  }

  @override
  Future<void> send(String message) async {
    final socket = _socket;
    if (socket != null) {
      socket.add(message);
    } else {
      _messages.add(message);
      for (final client in _clients) {
        client.add(message);
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _socket?.close();
    for (final client in _clients) {
      await client.close();
    }
    await _server?.close(force: true);
    if (_broadcast?.isStopped == false) await _broadcast?.stop();
    if (_discovery?.isStopped == false) await _discovery?.stop();
    await _rooms.close();
    await _messages.close();
  }

  static Uint8List _pemBytes(String pem) => Uint8List.fromList(
    base64.decode(pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), '')),
  );

  static Future<String> _localAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        if (!address.isLoopback && !address.address.startsWith('169.254.')) {
          return address.address;
        }
      }
    }
    throw const SocketException('No local Wi-Fi address found');
  }
}

LanTransport createLanTransport() => _NativeLanTransport();
