import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/data/game_data_repository.dart';
import '../../core/models/app_models.dart';
import '../../core/services/runtime_services.dart';
import '../../core/widgets/party_widgets.dart';
import '../games/imposter_engine.dart';
import '../games/stop_timer_engine.dart';
import 'lan_protocol.dart';
import 'lan_transport.dart';
import 'nearby_imposter_session.dart';
import 'nearby_stop_timer_session.dart';

class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({
    this.gameId,
    this.imposterSetup,
    this.stopTimerSetup,
    super.key,
  });
  final String? gameId;
  final ImposterSetup? imposterSetup;
  final StopTimerSetup? stopTimerSetup;

  @override
  ConsumerState<NearbyScreen> createState() => _NearbyScreenState();
}

class _NearbyScreenState extends ConsumerState<NearbyScreen> {
  final Stopwatch monotonicClock = Stopwatch()..start();
  late final LanTransport transport = createLanTransport();
  final endpoint = TextEditingController();
  final roomId = TextEditingController();
  final code = TextEditingController();
  final fingerprint = TextEditingController();
  final List<LanDiscoveredRoom> rooms = <LanDiscoveredRoom>[];
  final List<String> participants = <String>[];
  final Map<String, String> pendingApprovals = <String, String>{};
  final Map<String, String> pendingPlayerAssignments = <String, String>{};
  final Map<String, String> approvedPlayerAssignments = <String, String>{};
  StreamSubscription<LanDiscoveredRoom>? roomSubscription;
  StreamSubscription<LanReceivedMessage>? messageSubscription;
  LanHostDetails? host;
  String status = 'Choose how to connect.';
  bool busy = false;
  bool connected = false;
  bool ready = false;
  bool privateShowing = false;
  int localRevealIndex = 0;
  int clientSequence = 0;
  Map<String, dynamic>? clientSnapshot;
  LanRoomEngine? roomEngine;
  NearbyImposterSession? imposterSession;
  NearbyStopTimerSession? stopTimerSession;
  Timer? gameTicker;
  Timer? reconnectTimer;
  Timer? scheduledStartTimer;
  DateTime? hostLostAt;
  int? alertedDeadline;
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
    monotonicClock.stop();
    roomSubscription?.cancel();
    messageSubscription?.cancel();
    endpoint.dispose();
    roomId.dispose();
    code.dispose();
    fingerprint.dispose();
    gameTicker?.cancel();
    reconnectTimer?.cancel();
    scheduledStartTimer?.cancel();
    unawaited(WakelockPlus.disable());
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
    if (widget.gameId == 'imposter' &&
        (imposterSession != null || clientSnapshot != null)) {
      return _nearbyImposterGame();
    }
    if ((widget.gameId == 'timer-buzzer' ||
            widget.gameId == 'timer-imposter') &&
        (stopTimerSession != null ||
            clientSnapshot?['type'] == 'stopTimerSnapshot')) {
      return _nearbyStopTimerGame();
    }
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
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      request.value,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_configuredPlayers != null) ...<Widget>[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: pendingPlayerAssignments[request.key],
                        decoration: const InputDecoration(
                          labelText: 'Assign this phone',
                        ),
                        items: _availablePlayers(request.key)
                            .map(
                              (player) => DropdownMenuItem<String>(
                                value: player.id,
                                child: Text(player.name),
                              ),
                            )
                            .toList(),
                        onChanged: (String? value) => setState(() {
                          if (value != null) {
                            pendingPlayerAssignments[request.key] = value;
                          }
                        }),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        TextButton.icon(
                          onPressed: () => _resolveApproval(
                            request.key,
                            request.value,
                            false,
                          ),
                          icon: const Icon(Icons.close),
                          label: const Text('DECLINE'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed:
                              _configuredPlayers != null &&
                                  pendingPlayerAssignments[request.key] == null
                              ? null
                              : () => _resolveApproval(
                                  request.key,
                                  request.value,
                                  true,
                                ),
                          icon: const Icon(Icons.check),
                          label: const Text('APPROVE'),
                        ),
                      ],
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
        if (widget.gameId != 'imposter' &&
            widget.gameId != 'timer-buzzer' &&
            widget.gameId != 'timer-imposter')
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

  Widget _nearbyImposterGame() {
    if (hostLostAt != null) return _pausedNearbyGame();
    final session = imposterSession;
    return session != null
        ? _hostImposterGame(session)
        : _clientImposterGame(clientSnapshot!);
  }

  Widget _pausedNearbyGame() {
    final elapsed = ref
        .read(appClockProvider)()
        .difference(hostLostAt!)
        .inSeconds;
    final remaining = max(0, 60 - elapsed);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const StickerBadge(emoji: '📡', size: 96),
            const SizedBox(height: 22),
            Text(
              'HOST CONNECTION LOST',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall,
            ),
            const SizedBox(height: 10),
            Text(
              remaining > 0
                  ? 'Game paused. Reconnecting for $remaining more seconds…'
                  : 'The room closed after the 60-second reconnect window.',
              textAlign: TextAlign.center,
            ),
            if (remaining == 0) ...<Widget>[
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('LEAVE ROOM'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hostImposterGame(NearbyImposterSession session) {
    return switch (session.match.phase) {
      ImposterPhase.privateReveal => _hostPrivateReveal(session),
      ImposterPhase.discussion => _nearbyDiscussion(
        round: session.match.rounds.last.number,
        activeCount: session.match.activePlayerIds.length,
        banner: session.match.rounds.last.banner,
        deadline: session.discussionDeadline,
        onVote: _hostBeginVoting,
      ),
      ImposterPhase.voting => _hostVoting(session),
      ImposterPhase.result => _nearbyResult(
        setup: session.setup,
        outcome: session.match.outcome!,
        crewWord: session.match.crewWord,
        assignments: session.match.assignments.values
            .where((assignment) => assignment.isImposter)
            .map(
              (assignment) => <String, dynamic>{
                'playerId': assignment.playerId,
                'word': assignment.word,
              },
            )
            .toList(),
      ),
    };
  }

  Widget _hostPrivateReveal(NearbyImposterSession session) {
    final localIds = session.localPlayerIds;
    if (localIds.isEmpty || localRevealIndex >= localIds.length) {
      return _waitingCard(
        'WAITING FOR PRIVATE ROLES',
        '${session.readyPlayerIds.length}/${session.setup.players.length} players ready',
      );
    }
    final playerId = localIds[localRevealIndex];
    final player = session.setup.players.firstWhere(
      (value) => value.id == playerId,
    );
    final assignment = session.match.assignments[playerId]!;
    return ListView(
      key: ValueKey<String>('nearby-host-reveal-$playerId-$privateShowing'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const SizedBox(height: 40),
        Center(child: PlayerNameBadge(player: player)),
        const SizedBox(height: 18),
        Text(
          privateShowing
              ? session.setup.mode == ImposterMode.oddWord
                    ? 'YOUR SECRET WORD'
                    : 'YOUR SECRET ROLE'
              : 'PASS TO ${player.name.toUpperCase()}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 18),
        PartyCard(
          color: PartyColors.nearBlack,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: privateShowing
                ? _nearbyPrivateContent(
                    mode: session.setup.mode,
                    assignment: assignment.privateProjection(
                      session.setup.mode,
                    ),
                  )
                : const Text(
                    'Hold the phone privately, then tap below.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: PartyColors.white),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () => _advanceHostPrivateReveal(session, playerId),
          icon: Icon(privateShowing ? Icons.check : Icons.visibility),
          label: Text(
            privateShowing
                ? localRevealIndex + 1 == localIds.length
                      ? 'READY'
                      : 'HIDE & PASS'
                : session.setup.mode == ImposterMode.oddWord
                ? 'SHOW MY WORD'
                : 'SHOW MY ROLE',
          ),
        ),
      ],
    );
  }

  Widget _clientImposterGame(Map<String, dynamic> snapshot) {
    final phase = ImposterPhase.values.byName(snapshot['phase'] as String);
    final players = (snapshot['players'] as List<dynamic>)
        .map(
          (dynamic value) =>
              Player.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList(growable: false);
    final private = Map<String, dynamic>.from(snapshot['private'] as Map);
    final mode = ImposterMode.values.byName(snapshot['mode'] as String);
    return switch (phase) {
      ImposterPhase.privateReveal => _clientPrivateReveal(
        players,
        private,
        mode,
      ),
      ImposterPhase.discussion => _nearbyDiscussion(
        round: snapshot['round'] as int,
        activeCount: (snapshot['activePlayerIds'] as List<dynamic>).length,
        banner: snapshot['banner'] as String?,
        deadline: snapshot['discussionDeadline'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(
                snapshot['discussionDeadline'] as int,
              ),
        onVote: () => _sendImposterCommand('startVoting'),
      ),
      ImposterPhase.voting => _clientVoting(snapshot, players, private),
      ImposterPhase.result => _nearbyResult(
        setup: ImposterSetup(
          players: players,
          mode: mode,
          imposterCount: (snapshot['imposters'] as List<dynamic>).length,
        ),
        outcome: ImposterOutcome.values.byName(snapshot['outcome'] as String),
        crewWord: snapshot['crewWord'] as String,
        assignments: (snapshot['imposters'] as List<dynamic>)
            .map((dynamic value) => Map<String, dynamic>.from(value as Map))
            .toList(),
      ),
    };
  }

  Widget _clientPrivateReveal(
    List<Player> players,
    Map<String, dynamic> private,
    ImposterMode mode,
  ) {
    final player = players.firstWhere(
      (value) => value.id == private['playerId'],
    );
    if (private['ready'] == true) {
      return _waitingCard(
        'ROLE HIDDEN',
        'Waiting for every player to finish their private reveal.',
      );
    }
    return ListView(
      key: ValueKey<String>('nearby-client-reveal-$privateShowing'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        const SizedBox(height: 40),
        Center(child: PlayerNameBadge(player: player)),
        const SizedBox(height: 18),
        Text(
          privateShowing
              ? mode == ImposterMode.oddWord
                    ? 'YOUR SECRET WORD'
                    : 'YOUR SECRET ROLE'
              : 'PRIVATE FOR ${player.name.toUpperCase()}',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 18),
        PartyCard(
          color: PartyColors.nearBlack,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: privateShowing
                ? _nearbyPrivateContent(mode: mode, assignment: private)
                : const Text(
                    'Make sure only you can see this screen.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: PartyColors.white),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: privateShowing
              ? () => _sendImposterCommand('ready')
              : () => setState(() => privateShowing = true),
          icon: Icon(privateShowing ? Icons.check : Icons.visibility),
          label: Text(
            privateShowing
                ? 'READY & HIDE'
                : mode == ImposterMode.oddWord
                ? 'SHOW MY WORD'
                : 'SHOW MY ROLE',
          ),
        ),
      ],
    );
  }

  Widget _nearbyPrivateContent({
    required ImposterMode mode,
    required Map<String, dynamic> assignment,
  }) {
    final knownImposter =
        mode == ImposterMode.classic && assignment['isImposter'] == true;
    final text = knownImposter
        ? '🕵️ IMPOSTER'
        : (assignment['word'] as String).toUpperCase();
    final detail = knownImposter
        ? assignment['hint'] == null
              ? 'Bluff your way through the clues.'
              : 'YOUR HINT: ${(assignment['hint'] as String).toUpperCase()}'
        : 'Give a clue without saying the word.';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ResponsivePartyText(
          text,
          minFontSize: 32,
          maxFontSize: 58,
          maxLines: 3,
          color: PartyColors.white,
        ),
        const SizedBox(height: 12),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: PartyColors.white),
        ),
      ],
    );
  }

  Widget _nearbyDiscussion({
    required int round,
    required int activeCount,
    required String? banner,
    required DateTime? deadline,
    required VoidCallback onVote,
  }) {
    final remaining = deadline == null
        ? null
        : max(0, deadline.difference(ref.read(appClockProvider)()).inSeconds);
    return ListView(
      key: ValueKey<String>('nearby-discussion-$round-$remaining'),
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        if (banner != null) ...<Widget>[
          PartyCard(
            color: PartyColors.yellow,
            child: Text(
              banner,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 20),
        ],
        const Center(child: StickerBadge(emoji: '💬', size: 104)),
        const SizedBox(height: 20),
        Text(
          'DISCUSS & ACCUSE',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall,
        ),
        Text(
          'ROUND $round · $activeCount PLAYERS LEFT',
          textAlign: TextAlign.center,
        ),
        if (remaining != null) ...<Widget>[
          const SizedBox(height: 24),
          ResponsivePartyText(
            '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}',
            minFontSize: 52,
            maxFontSize: 84,
            maxLines: 1,
          ),
          if (remaining == 0)
            const Center(
              child: PartyStatusPill(
                label: 'TIME IS UP · VOTE WHEN READY',
                color: PartyColors.yellow,
              ),
            ),
        ],
        const SizedBox(height: 28),
        FilledButton.icon(
          onPressed: onVote,
          icon: const Icon(Icons.how_to_vote),
          label: const Text('START VOTING'),
        ),
      ],
    );
  }

  Widget _hostVoting(NearbyImposterSession session) {
    if (session.creatorDecisionCandidates.isNotEmpty) {
      return _voteChoices(
        heading: 'BREAK THE RUNOFF TIE',
        voter: null,
        candidateIds: session.creatorDecisionCandidates,
        players: session.setup.players,
        onSelected: _hostResolveCreator,
      );
    }
    final box = session.ballotBox!;
    final localVoters = session.localPlayerIds.where(
      session.match.activePlayerIds.contains,
    );
    final voterId = localVoters
        .where((String id) => !box.votes.containsKey(id))
        .firstOrNull;
    if (voterId == null) {
      return _waitingCard(
        box.runoff == 0 ? 'VOTES ARE PRIVATE' : 'RUNOFF IN PROGRESS',
        '${box.votes.length}/${box.activePlayerIds.length} ballots received',
      );
    }
    final voter = session.setup.players.firstWhere(
      (value) => value.id == voterId,
    );
    final candidates = (box.candidates ?? session.match.activePlayerIds)
        .where((String id) => id != voterId)
        .toList();
    return _voteChoices(
      heading: box.runoff == 0 ? 'CAST A PRIVATE VOTE' : 'RUNOFF VOTE',
      voter: voter,
      candidateIds: candidates,
      players: session.setup.players,
      onSelected: (String target) => _hostCastVote(voterId, target),
    );
  }

  Widget _clientVoting(
    Map<String, dynamic> snapshot,
    List<Player> players,
    Map<String, dynamic> private,
  ) {
    if (private['hasVoted'] == true) {
      return _waitingCard(
        'VOTE LOCKED IN',
        'Ballot totals stay hidden until everyone has voted.',
      );
    }
    final voterId = private['playerId'] as String;
    final runoff = (snapshot['runoffCandidates'] as List<dynamic>)
        .cast<String>();
    final active = (snapshot['activePlayerIds'] as List<dynamic>)
        .cast<String>();
    final candidates = (runoff.isEmpty ? active : runoff)
        .where((String id) => id != voterId)
        .toList();
    return _voteChoices(
      heading: runoff.isEmpty ? 'CAST A PRIVATE VOTE' : 'RUNOFF VOTE',
      voter: players.firstWhere((value) => value.id == voterId),
      candidateIds: candidates,
      players: players,
      onSelected: (String target) =>
          _sendImposterCommand('vote', <String, dynamic>{'target': target}),
    );
  }

  Widget _voteChoices({
    required String heading,
    required Player? voter,
    required List<String> candidateIds,
    required List<Player> players,
    required ValueChanged<String> onSelected,
  }) => ListView(
    padding: const EdgeInsets.all(20),
    children: <Widget>[
      const Center(child: StickerBadge(emoji: '🗳️', size: 96)),
      const SizedBox(height: 20),
      Text(
        heading,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.displaySmall,
      ),
      if (voter != null) ...<Widget>[
        const SizedBox(height: 12),
        Center(child: PlayerNameBadge(player: voter)),
        const SizedBox(height: 8),
        const Text('Keep this choice private.', textAlign: TextAlign.center),
      ],
      const SizedBox(height: 22),
      ...candidateIds.map((String id) {
        final player = players.firstWhere((value) => value.id == id);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: FilledButton(
            onPressed: () => onSelected(id),
            child: Text(player.name.toUpperCase()),
          ),
        );
      }),
    ],
  );

  Widget _nearbyResult({
    required ImposterSetup setup,
    required ImposterOutcome outcome,
    required String crewWord,
    required List<Map<String, dynamic>> assignments,
  }) => ListView(
    padding: const EdgeInsets.all(20),
    children: <Widget>[
      Center(
        child: StickerBadge(
          emoji: outcome == ImposterOutcome.crew ? '🏆' : '🎭',
          size: 104,
        ),
      ),
      const SizedBox(height: 20),
      ResponsivePartyText(
        outcome == ImposterOutcome.crew
            ? 'CREW WINS'
            : assignments.length == 1
            ? 'IMPOSTER WINS'
            : 'IMPOSTERS WIN',
        minFontSize: 42,
        maxFontSize: 72,
        maxLines: 2,
      ),
      const SizedBox(height: 14),
      Text('THE CREW WORD WAS', textAlign: TextAlign.center),
      ResponsivePartyText(
        crewWord.toUpperCase(),
        minFontSize: 36,
        maxFontSize: 62,
        maxLines: 3,
      ),
      const SizedBox(height: 18),
      ...assignments.map((Map<String, dynamic> assignment) {
        final player = setup.players.firstWhere(
          (value) => value.id == assignment['playerId'],
        );
        return PartyCard(
          child: ListTile(
            title: Text(player.name),
            subtitle: Text(
              setup.mode == ImposterMode.oddWord
                  ? 'IMPOSTER · ODD WORD: ${assignment['word']}'
                  : 'IMPOSTER',
            ),
          ),
        );
      }),
      const SizedBox(height: 18),
      FilledButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('BACK TO SETUP'),
      ),
    ],
  );

  Widget _nearbyStopTimerGame() {
    if (hostLostAt != null) return _pausedNearbyGame();
    final session = stopTimerSession;
    return session == null
        ? _clientStopTimerGame(clientSnapshot!)
        : _hostStopTimerGame(session);
  }

  Widget _hostStopTimerGame(NearbyStopTimerSession session) {
    if (session.endedReason != null) {
      return _waitingCard('ROOM ENDED', session.endedReason!);
    }
    final state = session.game;
    return switch (state.phase) {
      StopTimerPhase.targetReveal => _timerTargetReveal(
        state.plan.targetSeconds,
        state.plan.number,
        onContinue: _hostBeginTimerTurns,
      ),
      StopTimerPhase.privateReveal => _hostTimerPrivateReveal(session),
      StopTimerPhase.handoff => _hostTimerHandoff(session),
      StopTimerPhase.running => _hostTimerRunning(session),
      StopTimerPhase.roundResult => _timerRoundResults(
        players: state.setup.players,
        target: state.plan.targetSeconds,
        attempts: state.attempts.values.toList(),
        scores: state.scores,
        pointsAwarded: state.roundResults.last.pointsAwarded,
        onContinue: _hostContinueTimer,
        complete: const StopTimerGameEngine().matchComplete(state),
      ),
      StopTimerPhase.voting => _hostTimerVoting(session),
      StopTimerPhase.finalResult => _timerFinalResults(
        players: state.setup.players,
        mode: state.setup.mode,
        target: state.plan.targetSeconds,
        falseTarget: state.plan.falseTargetSeconds,
        attempts: state.attempts.values.toList(),
        scores: state.scores,
        imposterIds: state.plan.imposterPlayerIds,
        outcome: state.outcome,
        pointsGoal: state.setup.pointsGoal,
      ),
    };
  }

  Widget _clientStopTimerGame(Map<String, dynamic> snapshot) {
    if (snapshot['endedReason'] != null) {
      return _waitingCard('ROOM ENDED', snapshot['endedReason'] as String);
    }
    final phase = StopTimerPhase.values.byName(snapshot['phase'] as String);
    final mode = StopTimerMode.values.byName(snapshot['mode'] as String);
    final players = (snapshot['players'] as List<dynamic>)
        .map(
          (dynamic value) =>
              Player.fromJson(Map<String, dynamic>.from(value as Map)),
        )
        .toList(growable: false);
    final private = Map<String, dynamic>.from(snapshot['private'] as Map);
    final attempts = (snapshot['attempts'] as List<dynamic>? ?? const [])
        .map(
          (dynamic value) => TimerAttempt(
            playerId: (value as Map)['playerId'] as String,
            durationSeconds: (value['durationSeconds'] as num).toDouble(),
          ),
        )
        .toList(growable: false);
    return switch (phase) {
      StopTimerPhase.targetReveal => _timerTargetReveal(
        (snapshot['targetSeconds'] as num).toDouble(),
        snapshot['round'] as int,
      ),
      StopTimerPhase.privateReveal => _clientTimerPrivateReveal(
        players,
        private,
      ),
      StopTimerPhase.handoff => _clientTimerHandoff(
        players,
        private,
        snapshot['currentPlayerId'] as String,
      ),
      StopTimerPhase.running => _clientTimerRunning(players, private, snapshot),
      StopTimerPhase.roundResult => _timerRoundResults(
        players: players,
        target: (snapshot['targetSeconds'] as num).toDouble(),
        attempts: attempts,
        scores: Map<String, dynamic>.from(snapshot['scores'] as Map).map(
          (String key, dynamic value) => MapEntry(key, (value as num).toInt()),
        ),
        pointsAwarded:
            Map<String, dynamic>.from(snapshot['pointsAwarded'] as Map).map(
              (String key, dynamic value) =>
                  MapEntry(key, (value as num).toInt()),
            ),
        complete: false,
      ),
      StopTimerPhase.voting => _clientTimerVoting(snapshot, players, private),
      StopTimerPhase.finalResult => _timerFinalResults(
        players: players,
        mode: mode,
        target: (snapshot['targetSeconds'] as num?)?.toDouble(),
        falseTarget: (snapshot['falseTargetSeconds'] as num?)?.toDouble(),
        attempts: attempts,
        scores: Map<String, dynamic>.from(snapshot['scores'] as Map).map(
          (String key, dynamic value) => MapEntry(key, (value as num).toInt()),
        ),
        imposterIds:
            (snapshot['imposterPlayerIds'] as List<dynamic>? ?? const [])
                .cast<String>()
                .toSet(),
        outcome: snapshot['outcome'] == null
            ? null
            : StopTimerOutcome.values.byName(snapshot['outcome'] as String),
        pointsGoal: snapshot['pointsGoal'] as int,
      ),
    };
  }

  Widget _timerTargetReveal(
    double target,
    int round, {
    VoidCallback? onContinue,
  }) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const StickerBadge(emoji: '⏱️', size: 104),
          const SizedBox(height: 18),
          Text('ROUND $round TARGET'),
          ResponsivePartyText(
            '${target.toStringAsFixed(2)}s',
            minFontSize: 54,
            maxFontSize: 90,
            maxLines: 1,
          ),
          const SizedBox(height: 12),
          const Text(
            'Everyone memorizes this target. Attempts stay hidden until the round ends.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (onContinue != null)
            FilledButton.icon(
              onPressed: onContinue,
              icon: const Icon(Icons.visibility_off),
              label: const Text('HIDE TARGET & START TURNS'),
            )
          else
            const PartyStatusPill(
              label: 'WAITING FOR HOST',
              color: PartyColors.yellow,
            ),
        ],
      ),
    ),
  );

  Widget _hostTimerPrivateReveal(NearbyStopTimerSession session) {
    final localIds = session.localPlayerIds;
    if (localRevealIndex >= localIds.length) {
      return _waitingCard(
        'WAITING FOR SECRET INFO',
        '${session.readyPlayerIds.length}/${session.game.setup.players.length} players ready',
      );
    }
    final playerId = localIds[localRevealIndex];
    final player = session.game.setup.players.firstWhere(
      (Player value) => value.id == playerId,
    );
    final target = session.game.plan.targetFor(
      playerId,
      session.game.setup.imposterInfoMode,
    );
    return _timerPrivateReveal(
      player: player,
      showing: privateShowing,
      target: target,
      onPressed: () => _advanceHostTimerSecret(session, playerId),
    );
  }

  Widget _clientTimerPrivateReveal(
    List<Player> players,
    Map<String, dynamic> private,
  ) {
    final player = players.firstWhere(
      (Player value) => value.id == private['playerId'],
    );
    if (private['ready'] == true) {
      return _waitingCard(
        'SECRET HIDDEN',
        'Waiting for every player to finish their private reveal.',
      );
    }
    return _timerPrivateReveal(
      player: player,
      showing: privateShowing,
      target: private['targetSeconds'] == null
          ? null
          : (private['targetSeconds'] as num).toDouble(),
      onPressed: () {
        if (!privateShowing) {
          setState(() => privateShowing = true);
        } else {
          setState(() => privateShowing = false);
          unawaited(_sendTimerCommand('ready'));
        }
      },
    );
  }

  Widget _timerPrivateReveal({
    required Player player,
    required bool showing,
    required double? target,
    required VoidCallback onPressed,
  }) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PlayerNameBadge(player: player),
          const SizedBox(height: 18),
          Text(
            showing
                ? 'YOUR SECRET INFO'
                : 'PRIVATE FOR ${player.name.toUpperCase()}',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 18),
          PartyCard(
            color: PartyColors.nearBlack,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: showing
                  ? ResponsivePartyText(
                      target == null
                          ? 'IMPOSTER'
                          : '${target.toStringAsFixed(2)}s',
                      minFontSize: 42,
                      maxFontSize: 72,
                      maxLines: 2,
                      color: PartyColors.white,
                    )
                  : const Icon(Icons.lock, size: 90, color: PartyColors.white),
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onPressed,
            icon: Icon(showing ? Icons.check : Icons.visibility),
            label: Text(showing ? 'READY & HIDE' : 'SHOW SECRET INFO'),
          ),
        ],
      ),
    ),
  );

  Widget _hostTimerHandoff(NearbyStopTimerSession session) {
    final playerId = session.game.currentPlayerId;
    final player = session.game.setup.players.firstWhere(
      (Player value) => value.id == playerId,
    );
    final remote = session.devicePlayers.containsValue(playerId);
    return _timerHandoff(
      player,
      remote
          ? null
          : () {
              try {
                session.scheduleAttempt(playerId, _nowMicros);
                roomEngine?.recordHostMutation();
                setState(() {});
                _refreshAtScheduledStart(session.scheduledStartHostMicros);
                unawaited(_sendAllTimerSnapshots());
              } catch (error) {
                setState(() => status = _friendlyTimerError(error));
              }
            },
      remote ? 'Waiting for ${player.name} to start on their phone.' : null,
    );
  }

  Widget _clientTimerHandoff(
    List<Player> players,
    Map<String, dynamic> private,
    String activePlayerId,
  ) {
    final player = players.firstWhere(
      (Player value) => value.id == activePlayerId,
    );
    final active = private['isActivePlayer'] == true;
    final calibrated = private['clockCalibrated'] == true;
    return _timerHandoff(
      player,
      active && calibrated
          ? () => unawaited(_sendTimerCommand('startAttempt'))
          : null,
      active
          ? calibrated
                ? null
                : 'Calibrating this phone for a fair scheduled start…'
          : 'Waiting for ${player.name} to finish their private turn.',
    );
  }

  Widget _timerHandoff(Player player, VoidCallback? onStart, String? waiting) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              PlayerNameBadge(player: player),
              const SizedBox(height: 18),
              Text(
                'TURN: ${player.name.toUpperCase()}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                waiting ??
                    'Your stopped time will stay secret until everyone plays.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (onStart != null)
                FilledButton.icon(
                  onPressed: onStart,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('START TIMER'),
                )
              else
                const CircularProgressIndicator(),
            ],
          ),
        ),
      );

  Widget _hostTimerRunning(NearbyStopTimerSession session) {
    final playerId = session.game.currentPlayerId;
    final remote = session.devicePlayers.containsValue(playerId);
    if (remote) {
      return _waitingCard(
        'ATTEMPT IN PROGRESS',
        'Waiting for ${_timerPlayer(session.game.setup.players, playerId).name} to stop on their phone.',
      );
    }
    return _scheduledStopButton(
      player: _timerPlayer(session.game.setup.players, playerId),
      scheduledStartMicros: session.scheduledStartHostMicros!,
      onStop: () {
        try {
          session.stopHostAttempt(
            playerId: playerId,
            attemptId: session.activeAttemptId!,
            hostStopMicros: _nowMicros,
          );
          roomEngine?.recordHostMutation();
          _refreshAtScheduledStart(null);
          unawaited(WakelockPlus.disable());
          setState(() {});
          unawaited(_sendAllTimerSnapshots());
        } catch (error) {
          setState(() => status = _friendlyTimerError(error));
        }
      },
    );
  }

  Widget _clientTimerRunning(
    List<Player> players,
    Map<String, dynamic> private,
    Map<String, dynamic> snapshot,
  ) {
    final activeId = snapshot['currentPlayerId'] as String;
    final player = _timerPlayer(players, activeId);
    if (private['isActivePlayer'] != true) {
      return _waitingCard(
        'ATTEMPT IN PROGRESS',
        'Waiting for ${player.name} to stop on their phone.',
      );
    }
    return _scheduledStopButton(
      player: player,
      scheduledStartMicros: snapshot['scheduledStartMicros'] as int,
      onStop: () => unawaited(
        _sendTimerCommand('stopAttempt', <String, dynamic>{
          'attemptId': snapshot['activeAttemptId'],
          'clientStopMicros': _nowMicros,
        }),
      ),
    );
  }

  Widget _scheduledStopButton({
    required Player player,
    required int scheduledStartMicros,
    required VoidCallback onStop,
  }) {
    final started = _nowMicros >= scheduledStartMicros;
    return Center(
      child: Semantics(
        button: started,
        label: started ? 'Stop timer for ${player.name}' : 'Get ready',
        child: FilledButton(
          onPressed: started ? onStop : null,
          style: FilledButton.styleFrom(
            fixedSize: const Size(260, 260),
            shape: const CircleBorder(),
            backgroundColor: PartyColors.yellow,
            foregroundColor: PartyColors.nearBlack,
          ),
          child: Text(
            started ? 'STOP!' : 'GET READY',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  Widget _timerRoundResults({
    required List<Player> players,
    required double target,
    required List<TimerAttempt> attempts,
    required Map<String, int> scores,
    required Map<String, int> pointsAwarded,
    required bool complete,
    VoidCallback? onContinue,
  }) {
    final ranked = List<TimerAttempt>.from(attempts)
      ..sort(
        (TimerAttempt a, TimerAttempt b) =>
            a.absoluteErrorFrom(target).compareTo(b.absoluteErrorFrom(target)),
      );
    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Text(
          'TARGET ${target.toStringAsFixed(2)}s',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 14),
        ...ranked.indexed.map((entry) {
          final (index, attempt) = entry;
          final player = _timerPlayer(players, attempt.playerId);
          return PartyCard(
            child: ListTile(
              leading: Text(index == 0 ? '🏆' : '#${index + 1}'),
              title: Text(player.name),
              subtitle: Text('${attempt.durationSeconds.toStringAsFixed(2)}s'),
              trailing: pointsAwarded[player.id] == null
                  ? null
                  : Text('+${pointsAwarded[player.id]}'),
            ),
          );
        }),
        const SizedBox(height: 12),
        ScoreBoard(players: players, scores: scores),
        const SizedBox(height: 16),
        if (onContinue != null)
          FilledButton(
            onPressed: onContinue,
            child: Text(complete ? 'VIEW FINAL RESULTS' : 'NEXT ROUND'),
          )
        else
          const Center(
            child: PartyStatusPill(
              label: 'WAITING FOR HOST',
              color: PartyColors.yellow,
            ),
          ),
      ],
    );
  }

  Widget _hostTimerVoting(NearbyStopTimerSession session) {
    if (session.creatorDecisionCandidates.isNotEmpty) {
      return _voteChoices(
        heading: 'BREAK THE RUNOFF TIE',
        voter: null,
        candidateIds: session.creatorDecisionCandidates,
        players: session.game.setup.players,
        onSelected: _hostResolveTimerVote,
      );
    }
    final box = session.ballotBox!;
    final voterId = session.localPlayerIds
        .where((String id) => !box.votes.containsKey(id))
        .firstOrNull;
    if (voterId == null) {
      return _waitingCard(
        box.runoff == 0 ? 'VOTES ARE PRIVATE' : 'RUNOFF IN PROGRESS',
        '${box.votes.length}/${box.voterIds.length} ballots received',
      );
    }
    return _voteChoices(
      heading: box.runoff == 0 ? 'WHO IS AN IMPOSTER?' : 'RUNOFF VOTE',
      voter: _timerPlayer(session.game.setup.players, voterId),
      candidateIds: (box.candidates ?? box.voterIds)
          .where((String id) => id != voterId)
          .toList(),
      players: session.game.setup.players,
      onSelected: (String target) => _hostCastTimerVote(voterId, target),
    );
  }

  Widget _clientTimerVoting(
    Map<String, dynamic> snapshot,
    List<Player> players,
    Map<String, dynamic> private,
  ) {
    if (private['hasVoted'] == true) {
      return _waitingCard(
        'VOTE LOCKED IN',
        'Ballot totals stay hidden until everyone votes.',
      );
    }
    final voterId = private['playerId'] as String;
    final runoff = (snapshot['runoffCandidates'] as List<dynamic>)
        .cast<String>();
    return _voteChoices(
      heading: runoff.isEmpty ? 'WHO IS AN IMPOSTER?' : 'RUNOFF VOTE',
      voter: _timerPlayer(players, voterId),
      candidateIds:
          (runoff.isEmpty ? players.map((Player player) => player.id) : runoff)
              .where((String id) => id != voterId)
              .toList(),
      players: players,
      onSelected: (String target) => unawaited(
        _sendTimerCommand('vote', <String, dynamic>{'target': target}),
      ),
    );
  }

  Widget _timerFinalResults({
    required List<Player> players,
    required StopTimerMode mode,
    required double? target,
    required double? falseTarget,
    required List<TimerAttempt> attempts,
    required Map<String, int> scores,
    required Set<String> imposterIds,
    required StopTimerOutcome? outcome,
    required int pointsGoal,
  }) {
    if (mode == StopTimerMode.buzzer) {
      final best = scores.values.isEmpty ? 0 : scores.values.reduce(max);
      final winners = players.where(
        (Player player) => scores[player.id] == best,
      );
      return ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          const Center(child: StickerBadge(emoji: '🏆', size: 104)),
          const SizedBox(height: 18),
          ResponsivePartyText(
            winners.length == 1
                ? '${winners.single.name.toUpperCase()} WINS'
                : 'CO-WINNERS!',
            minFontSize: 40,
            maxFontSize: 68,
            maxLines: 2,
          ),
          Text('FIRST TO $pointsGoal', textAlign: TextAlign.center),
          const SizedBox(height: 16),
          ScoreBoard(players: players, scores: scores),
        ],
      );
    }
    final attemptByPlayer = <String, TimerAttempt>{
      for (final attempt in attempts) attempt.playerId: attempt,
    };
    return ListView(
      padding: const EdgeInsets.all(20),
      children: <Widget>[
        Center(
          child: StickerBadge(
            emoji: outcome == StopTimerOutcome.crew ? '🏆' : '🎭',
            size: 104,
          ),
        ),
        const SizedBox(height: 18),
        ResponsivePartyText(
          outcome == StopTimerOutcome.crew
              ? 'CREW WINS'
              : imposterIds.length == 1
              ? 'IMPOSTER WINS'
              : 'IMPOSTERS WIN',
          minFontSize: 40,
          maxFontSize: 68,
          maxLines: 2,
        ),
        Text(
          'CREW TARGET · ${target!.toStringAsFixed(2)}s',
          textAlign: TextAlign.center,
        ),
        if (falseTarget != null)
          Text(
            'IMPOSTER TARGET · ${falseTarget.toStringAsFixed(2)}s',
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 16),
        ...players.map((Player player) {
          final attempt = attemptByPlayer[player.id];
          return PartyCard(
            child: ListTile(
              title: Text(player.name),
              subtitle: Text(
                attempt == null
                    ? 'NO ATTEMPT'
                    : '${attempt.durationSeconds.toStringAsFixed(2)}s',
              ),
              trailing: Text(
                imposterIds.contains(player.id) ? 'IMPOSTER' : 'CREW',
              ),
            ),
          );
        }),
      ],
    );
  }

  Player _timerPlayer(List<Player> players, String id) =>
      players.firstWhere((Player player) => player.id == id);

  void _hostBeginTimerTurns() {
    stopTimerSession!.beginBuzzerTurns();
    roomEngine?.recordHostMutation();
    setState(() {});
    unawaited(_sendAllTimerSnapshots());
  }

  void _advanceHostTimerSecret(
    NearbyStopTimerSession session,
    String playerId,
  ) {
    if (!privateShowing) {
      setState(() => privateShowing = true);
      return;
    }
    session.markSecretReady(playerId);
    roomEngine?.recordHostMutation();
    setState(() {
      localRevealIndex++;
      privateShowing = false;
    });
    unawaited(_sendAllTimerSnapshots());
  }

  void _hostContinueTimer() {
    stopTimerSession!.continueBuzzer();
    roomEngine?.recordHostMutation();
    setState(() {});
    unawaited(_sendAllTimerSnapshots());
  }

  void _hostCastTimerVote(String voterId, String targetId) {
    stopTimerSession!.castVote(voterId, targetId);
    roomEngine?.recordHostMutation();
    setState(() {});
    unawaited(_sendAllTimerSnapshots());
  }

  void _hostResolveTimerVote(String targetId) {
    stopTimerSession!.resolveCreator(targetId);
    roomEngine?.recordHostMutation();
    setState(() {});
    unawaited(_sendAllTimerSnapshots());
  }

  void _refreshAtScheduledStart(int? scheduledMicros) {
    scheduledStartTimer?.cancel();
    scheduledStartTimer = null;
    if (scheduledMicros == null) return;
    final delay = max(0, scheduledMicros - _nowMicros);
    scheduledStartTimer = Timer(Duration(microseconds: delay), () {
      final stillRunning =
          stopTimerSession?.game.phase == StopTimerPhase.running ||
          clientSnapshot?['phase'] == StopTimerPhase.running.name;
      if (mounted && stillRunning) {
        unawaited(WakelockPlus.enable());
        setState(() {});
      }
    });
  }

  String _friendlyTimerError(Object error) {
    final value = error.toString();
    if (value.contains('clock_not_calibrated')) {
      return 'Still calibrating this phone. Wait a moment and try again.';
    }
    if (value.contains('invalid_attempt_time')) {
      return 'That stop arrived before the scheduled start. Wait for STOP, then try again.';
    }
    return 'That timer action is no longer valid. The room was refreshed.';
  }

  Widget _waitingCard(String title, String body) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: PartyHero(emoji: '📱', title: title, body: body),
    ),
  );

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
        roomEngine = LanRoomEngine(
          roomId: details.roomId,
          creatorId: deviceId,
          gameId: widget.gameId ?? 'nearby',
          now: ref.read(appClockProvider),
        )..requestJoin(deviceId, 'Room creator');
        roomEngine!.approve(deviceId);
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

  void _handleMessage(LanReceivedMessage received) {
    if (!mounted) return;
    try {
      final message = Map<String, dynamic>.from(
        jsonDecode(received.payload) as Map,
      );
      if (message['protocolVersion'] != null && host != null) {
        _handleGameCommand(received, message);
        return;
      }
      switch (message['type']) {
        case 'joinRequest':
          final name = message['displayName'] as String? ?? 'Nearby player';
          final joiningDevice = message['deviceId'] as String? ?? '';
          final existing = roomEngine?.members[joiningDevice];
          if (existing?.approved == true &&
              approvedPlayerAssignments[joiningDevice] != null) {
            unawaited(_sendApproval(joiningDevice, name));
            if (imposterSession != null) {
              unawaited(_sendImposterSnapshot(joiningDevice));
            }
            if (stopTimerSession != null) {
              unawaited(_resyncTimerDevice(joiningDevice));
            }
            return;
          }
          roomEngine?.requestJoin(joiningDevice, name);
          setState(() {
            pendingApprovals[joiningDevice] = name;
            final available = _availablePlayers(joiningDevice);
            if (available.isNotEmpty) {
              pendingPlayerAssignments[joiningDevice] = available.first.id;
            }
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
              status =
                  'Approved and connected securely as ${message['playerName'] ?? 'a roster player'}.';
            });
          }
        case 'rejected':
          if (message['deviceId'] == deviceId) {
            setState(
              () => status = 'The room creator declined this device. Ask the host before trying again.',
            );
          }
        case 'hostDisconnected':
          _beginReconnectGrace();
        case 'deviceDisconnected':
          if (host != null) {
            roomEngine?.disconnected(received.senderDeviceId);
            stopTimerSession?.deviceDisconnected(received.senderDeviceId);
            setState(
              () => status = 'A player disconnected. Their slot is reserved for 60 seconds.',
            );
            if (stopTimerSession != null) {
              unawaited(_sendAllTimerSnapshots());
            }
          }
        case 'started':
          setState(
            () => status =
                'Room started. Shared controls are active for ${_gameName(widget.gameId ?? 'selected game')}.',
          );
        case 'imposterSnapshot':
          setState(() {
            final sameReveal =
                clientSnapshot?['phase'] == message['phase'] &&
                message['phase'] == ImposterPhase.privateReveal.name;
            clientSnapshot = message;
            connected = true;
            if (!sameReveal ||
                (Map<String, dynamic>.from(
                      message['private'] as Map,
                    ))['ready'] ==
                    true) {
              privateShowing = false;
            }
            hostLostAt = null;
          });
          reconnectTimer?.cancel();
          reconnectTimer = null;
          _startGameTicker();
        case 'stopTimerSnapshot':
          if (message['gameStateVersion'] != nearbyTimerGameVersion) {
            setState(() {
              status = 'This timer room requires a different app version.';
            });
            return;
          }
          setState(() {
            final sameReveal =
                clientSnapshot?['phase'] == message['phase'] &&
                message['phase'] == StopTimerPhase.privateReveal.name;
            clientSnapshot = message;
            connected = true;
            hostLostAt = null;
            final timerPrivate = Map<String, dynamic>.from(
              message['private'] as Map,
            );
            if (!sameReveal || timerPrivate['ready'] == true) {
              privateShowing = false;
            }
          });
          reconnectTimer?.cancel();
          reconnectTimer = null;
          final timerPrivate = Map<String, dynamic>.from(
            message['private'] as Map,
          );
          if (message['phase'] == StopTimerPhase.running.name &&
              timerPrivate['isActivePlayer'] == true) {
            _refreshAtScheduledStart(message['scheduledStartMicros'] as int?);
          } else {
            _refreshAtScheduledStart(null);
            unawaited(WakelockPlus.disable());
          }
          _startGameTicker();
        case 'clockPing':
          final receivedMicros = _nowMicros;
          unawaited(
            _sendTimerCommand('clockSample', <String, dynamic>{
              'hostSentMicros': message['hostSentMicros'],
              'clientReceivedMicros': receivedMicros,
              'clientSentMicros': _nowMicros,
            }),
          );
        case 'commandRejected':
          setState(
            () => status = 'That action was already handled or is no longer valid. The room has been refreshed.',
          );
      }
    } catch (_) {
      // Game-specific protocol envelopes are handled by their feature controller.
    }
  }

  Future<void> _startNearby() async {
    if (widget.gameId == 'imposter' && widget.imposterSetup != null) {
      final session = NearbyImposterSession(
        setup: widget.imposterSetup!,
        words: ref.read(gameDataProvider).imposterWords,
        random: ref.read(randomProvider),
        now: ref.read(appClockProvider),
      );
      for (final assignment in approvedPlayerAssignments.entries) {
        session.assignDevice(assignment.key, assignment.value);
      }
      setState(() {
        imposterSession = session;
        localRevealIndex = 0;
        privateShowing = false;
        status = 'Private words are ready.';
      });
      roomEngine?.recordHostMutation();
      await _sendAllImposterSnapshots();
      _startGameTicker();
      return;
    }
    if (widget.stopTimerSetup != null) {
      final session = NearbyStopTimerSession(
        setup: widget.stopTimerSetup!,
        random: ref.read(randomProvider),
      );
      for (final assignment in approvedPlayerAssignments.entries) {
        session.assignDevice(assignment.key, assignment.value);
      }
      setState(() {
        stopTimerSession = session;
        localRevealIndex = 0;
        privateShowing = false;
        status = 'Timer match ready.';
      });
      roomEngine?.recordHostMutation();
      await _sendAllTimerSnapshots();
      for (final device in session.devicePlayers.keys) {
        await _sendClockPing(device);
      }
      _startGameTicker();
      return;
    }
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
    final playerId = pendingPlayerAssignments[joiningDevice];
    final players = _configuredPlayers;
    final player = players == null || playerId == null
        ? null
        : players.firstWhere((value) => value.id == playerId);
    setState(() {
      pendingApprovals.remove(joiningDevice);
      pendingPlayerAssignments.remove(joiningDevice);
      if (approve && !participants.contains(player?.name ?? name)) {
        participants.add(player?.name ?? name);
        if (playerId != null) {
          approvedPlayerAssignments[joiningDevice] = playerId;
        }
      }
      status = approve
          ? '$name was approved by the room creator.'
          : '$name was declined.';
    });
    if (approve) {
      roomEngine?.approve(joiningDevice, playerId: playerId);
    }
    await transport.sendTo(
      joiningDevice,
      jsonEncode(<String, dynamic>{
        'type': approve ? 'approved' : 'rejected',
        'deviceId': joiningDevice,
        'displayName': name,
        'playerId': playerId,
        'playerName': player?.name,
      }),
    );
  }

  List<Player> _availablePlayers(String pendingDeviceId) {
    final players = _configuredPlayers;
    if (players == null) return const <Player>[];
    final reserved = <String>{
      ...approvedPlayerAssignments.values,
      ...pendingPlayerAssignments.entries
          .where((entry) => entry.key != pendingDeviceId)
          .map((entry) => entry.value),
    };
    final current = pendingPlayerAssignments[pendingDeviceId];
    return players
        .where(
          (player) => player.id == current || !reserved.contains(player.id),
        )
        .toList(growable: false);
  }

  Future<void> _sendApproval(String joiningDevice, String name) async {
    final playerId = approvedPlayerAssignments[joiningDevice];
    final player = _configuredPlayers
        ?.where((value) => value.id == playerId)
        .firstOrNull;
    await transport.sendTo(
      joiningDevice,
      jsonEncode(<String, dynamic>{
        'type': 'approved',
        'deviceId': joiningDevice,
        'displayName': name,
        'playerId': playerId,
        'playerName': player?.name,
      }),
    );
  }

  List<Player>? get _configuredPlayers =>
      widget.imposterSetup?.players ?? widget.stopTimerSetup?.players;

  void _handleGameCommand(
    LanReceivedMessage received,
    Map<String, dynamic> message,
  ) {
    final room = roomEngine;
    if (room == null) return;
    try {
      final envelope = LanEnvelope.fromJson(message);
      final result = room.apply(
        envelope,
        authenticatedSenderId: received.senderDeviceId,
        gameCommandHandler: () {
          if (stopTimerSession != null) {
            _applyTimerCommand(received.senderDeviceId, envelope);
          } else {
            _applyImposterCommand(received.senderDeviceId, envelope);
          }
        },
      );
      if (!result.accepted) {
        unawaited(
          _rejectGameCommand(
            received.senderDeviceId,
            result.code,
            result.revision,
          ),
        );
        return;
      }
      if (stopTimerSession != null) {
        setState(() {});
        unawaited(
          _finishTimerCommand(
            received.senderDeviceId,
            envelope.payload['action'] as String?,
          ),
        );
        return;
      }
      setState(() {});
      unawaited(_sendAllImposterSnapshots());
    } catch (error) {
      unawaited(
        _rejectGameCommand(
          received.senderDeviceId,
          error.toString(),
          room.revision,
        ),
      );
    }
  }

  void _applyImposterCommand(String senderDeviceId, LanEnvelope envelope) {
    final session = imposterSession;
    if (session == null) throw StateError('game_not_started');
    final action = envelope.payload['action'] as String?;
    final playerId = session.devicePlayers[senderDeviceId];
    if (playerId == null) throw StateError('player_unassigned');
    switch (action) {
      case 'ready':
        session.markReady(playerId);
        _maybeBeginNearbyDiscussion(session);
      case 'startVoting':
        if (session.match.phase != ImposterPhase.discussion) {
          throw StateError('wrong_phase');
        }
        session.beginVoting();
      case 'vote':
        session.castVote(playerId, envelope.payload['target'] as String);
      default:
        throw StateError('unknown_game_action');
    }
  }

  Future<void> _rejectGameCommand(
    String senderDeviceId,
    String code,
    int revision,
  ) async {
    await transport.sendTo(
      senderDeviceId,
      jsonEncode(<String, dynamic>{
        'type': 'commandRejected',
        'code': code,
        'revision': revision,
      }),
    );
    if (stopTimerSession != null) {
      await _sendTimerSnapshot(senderDeviceId);
    } else if (imposterSession != null) {
      await _sendImposterSnapshot(senderDeviceId);
    }
  }

  void _applyTimerCommand(String senderDeviceId, LanEnvelope envelope) {
    final session = stopTimerSession!;
    final action = envelope.payload['action'] as String?;
    final playerId = session.devicePlayers[senderDeviceId];
    if (playerId == null) throw StateError('player_unassigned');
    switch (action) {
      case 'clockSample':
        session.recordClockSample(
          deviceId: senderDeviceId,
          hostSentMicros: envelope.payload['hostSentMicros'] as int,
          clientReceivedMicros: envelope.payload['clientReceivedMicros'] as int,
          clientSentMicros: envelope.payload['clientSentMicros'] as int,
          hostReceivedMicros: _nowMicros,
        );
      case 'ready':
        session.markSecretReady(playerId);
      case 'startAttempt':
        session.scheduleAttempt(playerId, _nowMicros);
      case 'stopAttempt':
        session.stopRemoteAttempt(
          deviceId: senderDeviceId,
          attemptId: envelope.payload['attemptId'] as String,
          clientStopMicros: envelope.payload['clientStopMicros'] as int,
        );
      case 'vote':
        session.castVote(playerId, envelope.payload['target'] as String);
      default:
        throw StateError('unknown_timer_action');
    }
  }

  Future<void> _finishTimerCommand(
    String senderDeviceId,
    String? action,
  ) async {
    await _sendAllTimerSnapshots();
    if (action == 'clockSample' &&
        (stopTimerSession?.clockSampleCount(senderDeviceId) ?? 5) < 5) {
      await _sendClockPing(senderDeviceId);
    }
  }

  Future<void> _sendImposterCommand(
    String action, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) async {
    final snapshot = clientSnapshot;
    if (snapshot == null) return;
    final envelope = LanEnvelope(
      protocolVersion: lanProtocolVersion,
      roomId: snapshot['roomId'] as String,
      messageId: const Uuid().v4(),
      senderId: deviceId,
      clientSequence: ++clientSequence,
      expectedRevision: snapshot['revision'] as int,
      type: 'gameCommand',
      payload: <String, dynamic>{'action': action, ...payload},
    );
    await transport.send(envelope.encode());
  }

  Future<void> _sendTimerCommand(
    String action, [
    Map<String, dynamic> payload = const <String, dynamic>{},
  ]) async {
    final snapshot = clientSnapshot;
    if (snapshot == null) return;
    final envelope = LanEnvelope(
      protocolVersion: lanProtocolVersion,
      roomId: snapshot['roomId'] as String,
      messageId: const Uuid().v4(),
      senderId: deviceId,
      clientSequence: ++clientSequence,
      expectedRevision: snapshot['revision'] as int,
      type: 'gameCommand',
      payload: <String, dynamic>{'action': action, ...payload},
    );
    await transport.send(envelope.encode());
  }

  Future<void> _sendClockPing(String targetDeviceId) async {
    await transport.sendTo(
      targetDeviceId,
      jsonEncode(<String, dynamic>{
        'type': 'clockPing',
        'hostSentMicros': _nowMicros,
      }),
    );
  }

  Future<void> _resyncTimerDevice(String targetDeviceId) async {
    await _sendTimerSnapshot(targetDeviceId);
    await _sendClockPing(targetDeviceId);
  }

  Future<void> _sendTimerSnapshot(String targetDeviceId) async {
    final session = stopTimerSession;
    final room = roomEngine;
    if (session == null || room == null) return;
    await transport.sendTo(
      targetDeviceId,
      jsonEncode(<String, dynamic>{
        ...session.projectionFor(targetDeviceId),
        'roomId': room.roomId,
        'revision': room.revision,
      }),
    );
  }

  Future<void> _sendAllTimerSnapshots() async {
    final session = stopTimerSession;
    if (session == null) return;
    for (final target in session.devicePlayers.keys) {
      try {
        await _sendTimerSnapshot(target);
      } catch (_) {
        // Reconnecting devices receive an authoritative snapshot on return.
      }
    }
  }

  Future<void> _sendImposterSnapshot(String targetDeviceId) async {
    final session = imposterSession;
    final room = roomEngine;
    if (session == null || room == null) return;
    await transport.sendTo(
      targetDeviceId,
      jsonEncode(<String, dynamic>{
        ...session.projectionFor(targetDeviceId),
        'roomId': room.roomId,
        'revision': room.revision,
      }),
    );
  }

  Future<void> _sendAllImposterSnapshots() async {
    final session = imposterSession;
    if (session == null) return;
    for (final target in session.devicePlayers.keys) {
      try {
        await _sendImposterSnapshot(target);
      } catch (_) {
        // A disconnected device keeps its slot and receives a fresh snapshot
        // when it authenticates again during the grace period.
      }
    }
  }

  void _advanceHostPrivateReveal(
    NearbyImposterSession session,
    String playerId,
  ) {
    if (!privateShowing) {
      setState(() => privateShowing = true);
      return;
    }
    session.markReady(playerId);
    setState(() {
      localRevealIndex++;
      privateShowing = false;
    });
    _maybeBeginNearbyDiscussion(session);
    roomEngine?.recordHostMutation();
    unawaited(_sendAllImposterSnapshots());
  }

  void _maybeBeginNearbyDiscussion(NearbyImposterSession session) {
    if (session.allPlayersReady &&
        session.match.phase == ImposterPhase.privateReveal) {
      session.beginDiscussion(ref.read(appClockProvider)());
      roomEngine?.recordHostMutation();
      _startGameTicker();
    }
  }

  void _hostBeginVoting() {
    final session = imposterSession!;
    if (session.match.phase != ImposterPhase.discussion) return;
    session.beginVoting();
    roomEngine?.recordHostMutation();
    setState(() {});
    unawaited(_sendAllImposterSnapshots());
  }

  void _hostCastVote(String voterId, String targetId) {
    imposterSession!.castVote(voterId, targetId);
    roomEngine?.recordHostMutation();
    setState(() {});
    unawaited(_sendAllImposterSnapshots());
  }

  void _hostResolveCreator(String targetId) {
    imposterSession!.resolveCreator(targetId);
    roomEngine?.recordHostMutation();
    setState(() {});
    unawaited(_sendAllImposterSnapshots());
  }

  void _startGameTicker() {
    gameTicker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final room = roomEngine;
      final imposter = imposterSession;
      final timer = stopTimerSession;
      if (mounted && room != null && (imposter != null || timer != null)) {
        final expired = room.removeExpiredMembers();
        if (expired.isNotEmpty) {
          for (final member in expired) {
            imposter?.expireDevice(member.deviceId);
            timer?.expireDevice(member.deviceId);
            final playerId = approvedPlayerAssignments.remove(member.deviceId);
            final player = _configuredPlayers
                ?.where((value) => value.id == playerId)
                .firstOrNull;
            if (player != null) participants.remove(player.name);
          }
          if (imposter?.match.phase == ImposterPhase.privateReveal) {
            _maybeBeginNearbyDiscussion(imposter!);
          }
          localRevealIndex = min(
            localRevealIndex,
            max(0, (timer?.localPlayerIds.length ?? 1) - 1),
          );
          status = expired.length == 1
              ? 'A disconnected player left after the 60-second reconnect window.'
              : '${expired.length} disconnected players left after the reconnect window.';
          setState(() {});
          if (imposter != null) unawaited(_sendAllImposterSnapshots());
          if (timer != null) unawaited(_sendAllTimerSnapshots());
        }
      }
      if (mounted &&
          (imposterSession?.match.phase == ImposterPhase.discussion ||
              clientSnapshot?['phase'] == ImposterPhase.discussion.name)) {
        final deadline =
            imposterSession?.discussionDeadline?.millisecondsSinceEpoch ??
            clientSnapshot?['discussionDeadline'] as int?;
        if (deadline != null &&
            ref.read(appClockProvider)().millisecondsSinceEpoch >= deadline &&
            alertedDeadline != deadline) {
          alertedDeadline = deadline;
          _playNearbyTimerAlert();
        }
        setState(() {});
      }
      if (mounted && hostLostAt != null) setState(() {});
    });
  }

  void _playNearbyTimerAlert() {
    final settings = ref.read(appControllerProvider).settings;
    if (settings.soundEnabled) {
      unawaited(SystemSound.play(SystemSoundType.alert));
    }
    if (settings.hapticsEnabled) {
      unawaited(HapticFeedback.heavyImpact());
    }
  }

  void _beginReconnectGrace() {
    if (host != null || hostLostAt != null) return;
    setState(() {
      hostLostAt = ref.read(appClockProvider)();
      status = 'Host connection lost. The game is paused for up to 60 seconds.';
    });
    reconnectTimer?.cancel();
    reconnectTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      if (!mounted || hostLostAt == null) {
        timer.cancel();
        return;
      }
      final elapsed = ref.read(appClockProvider)().difference(hostLostAt!);
      if (elapsed >= lanReconnectGrace) {
        timer.cancel();
        setState(() {});
        return;
      }
      unawaited(_attemptReconnect());
    });
  }

  Future<void> _attemptReconnect() async {
    try {
      await transport.join(
        endpoint: endpoint.text.trim(),
        roomId: roomId.text.trim(),
        token: code.text.trim(),
        fingerprint: fingerprint.text.trim(),
        deviceId: deviceId,
        displayName: ref.read(appControllerProvider).players.first.name,
      );
    } catch (_) {
      // The recurring grace-period timer will try again until 60 seconds.
    }
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

  int get _nowMicros => monotonicClock.elapsedMicroseconds;

  static String _gameName(String id) => switch (id) {
    'trivia' => 'Trivia Versus',
    'imposter' => 'Imposter',
    'stop-timer' => 'Stop the Timer',
    'timer-buzzer' => 'Buzzer Battle',
    'timer-imposter' => 'Timer Imposter',
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
