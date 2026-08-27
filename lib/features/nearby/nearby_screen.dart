import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/widgets/party_widgets.dart';
import 'lan_protocol.dart';
import 'lan_transport.dart';

class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({this.gameId, super.key});
  final String? gameId;

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  late final LanTransport transport = createLanTransport();
  final endpoint = TextEditingController();
  final roomId = TextEditingController();
  final code = TextEditingController();
  final fingerprint = TextEditingController();
  final List<LanDiscoveredRoom> rooms = <LanDiscoveredRoom>[];
  final List<String> participants = <String>[];
  final Map<String, String> pendingApprovals = <String, String>{};
  StreamSubscription<LanDiscoveredRoom>? roomSubscription;
  StreamSubscription<String>? messageSubscription;
  LanHostDetails? host;
  String status = 'Choose how to connect.';
  bool busy = false;
  bool connected = false;
  bool ready = false;
  late final String deviceId = const Uuid().v4();

  @override
  void initState() {
    super.initState();
    roomSubscription = transport.discoveredRooms.listen((
      LanDiscoveredRoom room,
    ) {
      if (!mounted) return;
      setState(() {
        rooms.removeWhere((LanDiscoveredRoom old) => old.roomId == room.roomId);
        rooms.add(room);
      });
    });
    messageSubscription = transport.messages.listen(_handleMessage);
  }

  @override
  void dispose() {
    roomSubscription?.cancel();
    messageSubscription?.cancel();
    endpoint.dispose();
    roomId.dispose();
    code.dispose();
    fingerprint.dispose();
    unawaited(transport.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PartyPage(
    title: 'Nearby Room',
    style: PartyGameStyle.hub,
    subtitle: widget.gameId == null
        ? 'Private same-Wi-Fi play'
        : _gameName(widget.gameId!),
    child: kIsWeb || !transport.isSupported ? _webMessage() : _nativeBody(),
  );

  Widget _webMessage() => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        const PartyHero(
          emoji: '📱',
          title: 'Nearby needs the mobile app',
          body: 'The GitHub Pages edition stays single-device. Install Pocket Party Games on Android or iOS, then put every phone on the same Wi-Fi network.',
        ),
      ],
    ),
  );

  Widget _nativeBody() {
    if (connected || host != null) return _lobby();
    return ListView(
      key: const ValueKey<String>('nearby-connect'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        const Text(
          'No account or internet is used. The host phone creates a temporary encrypted room on this Wi-Fi network.',
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: busy ? null : _host,
          icon: const Icon(Icons.add_circle),
          label: const Text('HOST A ROOM'),
        ),
        const SizedBox(height: 18),
        if (rooms.isNotEmpty) ...<Widget>[
          Text(
            'Discovered rooms',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ...rooms.map(
            (LanDiscoveredRoom room) => PartyCard(
              child: ListTile(
                leading: const Icon(Icons.wifi),
                title: Text(room.name),
                subtitle: Text(room.endpoint),
                onTap: () => setState(() {
                  endpoint.text = room.endpoint;
                  roomId.text = room.roomId;
                  fingerprint.text = room.fingerprint;
                }),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Text('Join a room', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 10),
        TextField(
          controller: endpoint,
          decoration: const InputDecoration(
            labelText: 'Local address',
            hintText: '192.168.1.10:43210',
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: roomId,
          decoration: const InputDecoration(labelText: 'Room ID'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: code,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: '6-character join code'),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: fingerprint,
          decoration: const InputDecoration(
            labelText: 'Certificate fingerprint',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : _join,
                icon: const Icon(Icons.login),
                label: const Text('JOIN'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: busy ? null : _scanQr,
              tooltip: 'Scan room QR code',
              icon: const Icon(Icons.qr_code_scanner),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _StatusCard(status: status),
        const SizedBox(height: 12),
        const Text(
          'Can’t connect? Confirm both phones use the same non-guest Wi-Fi, disable client isolation, allow Local Network and Camera permissions, and keep the host app in the foreground.',
        ),
      ],
    );
  }

  Widget _lobby() {
    final details = host;
    return ListView(
      key: const ValueKey<String>('nearby-lobby'),
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        if (details != null) ...<Widget>[
          Text(
            'ROOM CODE',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          SelectableText(
            details.joinCode,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.displayMedium
                ?.copyWith(letterSpacing: 8),
          ),
          const SizedBox(height: 12),
          Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: QrImageView(data: details.qrPayload, size: 210),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SelectableText(details.endpoint, textAlign: TextAlign.center),
          const Divider(height: 32),
        ],
        Text(
          host != null ? 'Host lobby' : 'Connected lobby',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        _StatusCard(status: status),
        if (pendingApprovals.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            'Approval needed',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          ...pendingApprovals.entries.map(
            (MapEntry<String, String> request) => PartyCard(
              child: ListTile(
                leading: const Icon(Icons.phonelink_lock),
                title: Text(request.value),
                subtitle: const Text('Claim one roster player after approval'),
                trailing: Wrap(
                  children: <Widget>[
                    IconButton(
                      tooltip: 'Reject device',
                      onPressed: () =>
                          _resolveApproval(request.key, request.value, false),
                      icon: const Icon(Icons.close),
                    ),
                    IconButton.filled(
                      tooltip: 'Approve device',
                      onPressed: () =>
                          _resolveApproval(request.key, request.value, true),
                      icon: const Icon(Icons.check),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
        ...participants.map(
          (String name) => PartyCard(
            child: ListTile(
              leading: const Icon(Icons.phone_iphone),
              title: Text(name),
              trailing: const Chip(label: Text('APPROVED')),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: ready,
          onChanged: (bool value) async {
            setState(() => ready = value);
            await transport.send(
              jsonEncode(<String, dynamic>{
                'type': 'ready',
                'deviceId': deviceId,
                'ready': value,
              }),
            );
          },
          title: const Text('I’m ready'),
          subtitle: const Text(
            'The host controls setup; shared phase buttons unlock after readiness checks.',
          ),
        ),
        if (host != null)
          FilledButton.icon(
            onPressed: participants.isEmpty ? null : _startNearby,
            icon: const Icon(Icons.play_arrow),
            label: const Text('START ROOM'),
          ),
        const SizedBox(height: 12),
        const Text(
          'If the host disconnects, clients pause immediately and retain their player slot for 60 seconds before the room closes.',
        ),
      ],
    );
  }

  Future<void> _host() async {
    setState(() {
      busy = true;
      status = 'Creating a TLS certificate and advertising the room…';
    });
    try {
      final token =
          const Uuid().v4().replaceAll('-', '') +
          const Uuid().v4().replaceAll('-', '');
      final id = const Uuid().v4().substring(0, 8);
      final details = await transport.startHost(
        roomName:
            'Pocket Party · ${ref.read(appControllerProvider).players.first.name}',
        roomId: id,
        token: token,
      );
      if (!mounted) return;
      setState(() {
        host = details;
        status = 'Room is encrypted and visible on the local network.';
      });
    } catch (error) {
      if (mounted) setState(() => status = _friendlyError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _join() async {
    if (endpoint.text.trim().isEmpty ||
        roomId.text.trim().isEmpty ||
        code.text.trim().isEmpty ||
        fingerprint.text.trim().isEmpty) {
      setState(
        () => status = 'Enter the discovered room, code, and certificate fingerprint—or scan the host QR.',
      );
      return;
    }
    setState(() {
      busy = true;
      status = 'Verifying the host certificate…';
    });
    try {
      await transport.join(
        endpoint: endpoint.text.trim(),
        roomId: roomId.text.trim(),
        token: code.text.trim(),
        fingerprint: fingerprint.text.trim(),
        deviceId: deviceId,
        displayName: ref.read(appControllerProvider).players.first.name,
      );
      if (mounted) {
        setState(
          () => status = 'Waiting for the room creator to approve this device…',
        );
      }
    } catch (error) {
      if (mounted) setState(() => status = _friendlyError(error));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _scanQr() async {
    final payload = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const _QrScannerPage()),
    );
    if (payload == null) return;
    try {
      final value = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      if (value['protocolVersion'] != lanProtocolVersion) {
        throw const FormatException('This room uses a different app protocol.');
      }
      endpoint.text = value['endpoint'] as String;
      roomId.text = value['roomId'] as String;
      code.text = value['token'] as String;
      fingerprint.text = value['fingerprint'] as String;
      await _join();
    } catch (_) {
      if (mounted) {
        setState(
          () => status = 'That QR code is not a compatible Pocket Party room.',
        );
      }
    }
  }

  void _handleMessage(String raw) {
    if (!mounted) return;
    try {
      final message = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      switch (message['type']) {
        case 'joinRequest':
          final name = message['displayName'] as String? ?? 'Nearby player';
          final joiningDevice = message['deviceId'] as String? ?? '';
          setState(() {
            pendingApprovals[joiningDevice] = name;
            status = '$name is waiting for the room creator’s approval.';
          });
        case 'authenticated':
          setState(() {
            status = 'Secure channel established. Waiting for the room creator to approve this device…';
          });
        case 'approved':
          if (message['deviceId'] == deviceId) {
            setState(() {
              connected = true;
              status = 'Approved and connected securely. Claim one roster player when the host starts.';
            });
          }
        case 'rejected':
          if (message['deviceId'] == deviceId) {
            setState(
              () => status = 'The room creator declined this device. Ask the host before trying again.',
            );
          }
        case 'hostDisconnected':
          setState(
            () => status = 'Host connection lost. The game is paused for up to 60 seconds.',
          );
        case 'started':
          setState(
            () => status =
                'Room started. Shared controls are active for ${_gameName(widget.gameId ?? 'selected game')}.',
          );
      }
    } catch (_) {
      // Game-specific protocol envelopes are handled by their feature controller.
    }
  }

  Future<void> _startNearby() async {
    await transport.send(
      jsonEncode(<String, dynamic>{
        'type': 'started',
        'gameId': widget.gameId,
        'revision': 1,
      }),
    );
    if (mounted) {
      setState(
        () => status =
            'Room started. First valid shared transition wins each revision.',
      );
    }
  }

  Future<void> _resolveApproval(
    String joiningDevice,
    String name,
    bool approve,
  ) async {
    setState(() {
      pendingApprovals.remove(joiningDevice);
      if (approve && !participants.contains(name)) {
        participants.add(name);
      }
      status = approve
          ? '$name was approved by the room creator.'
          : '$name was declined.';
    });
    await transport.send(
      jsonEncode(<String, dynamic>{
        'type': approve ? 'approved' : 'rejected',
        'deviceId': joiningDevice,
        'displayName': name,
      }),
    );
  }

  String _friendlyError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('permission')) {
      return 'Local Network or Camera permission was denied. Enable it in system settings and try again.';
    }
    if (text.contains('certificate')) {
      return 'The host identity did not match. Rescan the host QR code instead of bypassing the warning.';
    }
    if (text.contains('timeout')) {
      return 'The host could not be reached. Check Wi-Fi, guest isolation, and that the host app is foregrounded.';
    }
    if (text.contains('full')) return 'This room already has 20 players.';
    return 'Could not connect. Check that both devices share the same Wi-Fi and use the same app version.';
  }

  static String _gameName(String id) => switch (id) {
    'trivia' => 'Trivia Versus',
    'imposter' => 'Imposter',
    'stop-timer' => 'Stop the Timer',
    'pictionary' => 'Pictionary',
    'acting' || 'act-it-out' => 'Act It Out',
    _ => 'Nearby game',
  };
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) => PartyCard(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: <Widget>[
          const Icon(Icons.info_outline),
          const SizedBox(width: 10),
          Expanded(child: Text(status)),
        ],
      ),
    ),
  );
}

class _QrScannerPage extends StatefulWidget {
  const _QrScannerPage();
  @override
  State<_QrScannerPage> createState() => _QrScannerPageState();
}

class _QrScannerPageState extends State<_QrScannerPage> {
  bool returned = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan host QR')),
    body: MobileScanner(
      onDetect: (BarcodeCapture capture) {
        final value = capture.barcodes.firstOrNull?.rawValue;
        if (!returned && value != null) {
          returned = true;
          Navigator.pop(context, value);
        }
      },
    ),
  );
}
