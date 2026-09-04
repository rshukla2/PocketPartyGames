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

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/data/game_data_repository.dart';
import '../../core/models/app_models.dart';
import '../../core/services/runtime_services.dart';
import '../../core/widgets/party_widgets.dart';
import '../games/imposter_engine.dart';
import 'lan_protocol.dart';
import 'lan_transport.dart';
import 'nearby_imposter_session.dart';

class NearbyScreen extends ConsumerStatefulWidget {
  const NearbyScreen({this.gameId, this.imposterSetup, super.key});
  final String? gameId;
  final ImposterSetup? imposterSetup;

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
  Timer? gameTicker;
  Timer? reconnectTimer;
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
    roomSubscription?.cancel();
    messageSubscription?.cancel();
    endpoint.dispose();
    roomId.dispose();
    code.dispose();
    fingerprint.dispose();
    gameTicker?.cancel();
    reconnectTimer?.cancel();
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
                    if (widget.imposterSetup != null) ...<Widget>[
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
                              widget.imposterSetup != null &&
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
        if (widget.gameId != 'imposter')
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
            setState(
              () => status = 'A player disconnected. Their slot is reserved for 60 seconds.',
            );
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
    final setup = widget.imposterSetup;
    final player = setup == null || playerId == null
        ? null
        : setup.players.firstWhere((value) => value.id == playerId);
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
    final setup = widget.imposterSetup;
    if (setup == null) return const <Player>[];
    final reserved = <String>{
      ...approvedPlayerAssignments.values,
      ...pendingPlayerAssignments.entries
          .where((entry) => entry.key != pendingDeviceId)
          .map((entry) => entry.value),
    };
    final current = pendingPlayerAssignments[pendingDeviceId];
    return setup.players
        .where(
          (player) => player.id == current || !reserved.contains(player.id),
        )
        .toList(growable: false);
  }

  Future<void> _sendApproval(String joiningDevice, String name) async {
    final playerId = approvedPlayerAssignments[joiningDevice];
    final player = widget.imposterSetup?.players
        .where((value) => value.id == playerId)
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

  void _handleGameCommand(
    LanReceivedMessage received,
    Map<String, dynamic> message,
  ) {
    final room = roomEngine;
    final session = imposterSession;
    if (room == null || session == null) return;
    try {
      final envelope = LanEnvelope.fromJson(message);
      final result = room.apply(
        envelope,
        authenticatedSenderId: received.senderDeviceId,
      );
      if (!result.accepted) {
        unawaited(
          transport.sendTo(
            received.senderDeviceId,
            jsonEncode(<String, dynamic>{
              'type': 'commandRejected',
              'code': result.code,
              'revision': result.revision,
            }),
          ),
        );
        return;
      }
      final action = envelope.payload['action'] as String?;
      final playerId = session.devicePlayers[received.senderDeviceId];
      if (playerId == null) throw StateError('player_unassigned');
      switch (action) {
        case 'ready':
          session.markReady(playerId);
          _maybeBeginNearbyDiscussion(session);
        case 'startVoting':
          if (session.match.phase == ImposterPhase.discussion) {
            session.beginVoting();
          }
        case 'vote':
          session.castVote(playerId, envelope.payload['target'] as String);
        default:
          throw StateError('unknown_game_action');
      }
      setState(() {});
      unawaited(_sendAllImposterSnapshots());
    } catch (error) {
      unawaited(
        transport.sendTo(
          received.senderDeviceId,
          jsonEncode(<String, dynamic>{
            'type': 'commandRejected',
            'code': error.toString(),
            'revision': room.revision,
          }),
        ),
      );
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
