import 'package:flutter_test/flutter_test.dart';
import 'package:pocket_party_games/features/nearby/lan_protocol.dart';

LanEnvelope command({
  required int revision,
  int sequence = 1,
  String id = 'm1',
  String sender = 'host',
  String type = 'transition',
}) => LanEnvelope(
  protocolVersion: lanProtocolVersion,
  roomId: 'room',
  messageId: id,
  senderId: sender,
  clientSequence: sequence,
  expectedRevision: revision,
  type: type,
  payload: const <String, dynamic>{'phase': 'question'},
);

void main() {
  test('codec preserves the versioned envelope', () {
    final original = command(revision: 4);
    final decoded = LanEnvelope.decode(original.encode());
    expect(decoded.protocolVersion, 1);
    expect(decoded.expectedRevision, 4);
    expect(decoded.type, 'transition');
  });

  test('host accepts first revision and rejects duplicate and stale races', () {
    final room = LanRoomEngine(
      roomId: 'room',
      creatorId: 'host',
      gameId: 'trivia',
    );
    room.requestJoin('host', 'Host');
    room.approve('host', playerId: 'p1');
    final expected = room.revision;
    expect(room.apply(command(revision: expected)).accepted, isTrue);
    expect(room.apply(command(revision: expected)).code, 'duplicate');
    final racer = command(revision: expected, sender: 'guest', id: 'racer');
    room.requestJoin('guest', 'Guest');
    room.approve('guest', playerId: 'p2');
    expect(room.apply(racer).accepted, isFalse);
    expect(room.apply(racer).code, anyOf('stale_revision', 'duplicate'));
  });

  test('private projections redact every other recipient secret', () {
    final room = LanRoomEngine(
      roomId: 'room',
      creatorId: 'host',
      gameId: 'imposter',
    );
    room.setPrivateState('a', <String, dynamic>{'role': 'imposter'});
    room.setPrivateState('b', <String, dynamic>{
      'role': 'player',
      'word': 'orbit',
    });
    expect(room.projectionFor('a')['private'], <String, dynamic>{
      'role': 'imposter',
    });
    expect(room.projectionFor('a').toString(), isNot(contains('orbit')));
    expect(room.projectionFor('b')['private'], <String, dynamic>{
      'role': 'player',
      'word': 'orbit',
    });
  });

  test('majority vote excludes ineligible and duplicate ballots', () {
    final vote = MajorityVote(
      id: 'v',
      eligibleDeviceIds: <String>{'a', 'b', 'c'},
      creatorId: 'host',
    );
    expect(vote.cast('answerer', true), isFalse);
    expect(vote.cast('a', true), isTrue);
    expect(vote.cast('a', false), isFalse);
    expect(vote.outcome, VoteOutcome.accepted);
  });

  test('tie and undersized electorates return control to creator', () {
    final small = MajorityVote(
      id: 'small',
      eligibleDeviceIds: <String>{'a'},
      creatorId: 'host',
    );
    expect(small.outcome, VoteOutcome.creatorDecision);
    final tie = MajorityVote(
      id: 'tie',
      eligibleDeviceIds: <String>{'a', 'b'},
      creatorId: 'host',
    );
    expect(tie.cast('a', true), isTrue);
    expect(tie.outcome, VoteOutcome.accepted);
    expect(tie.cast('b', false), isTrue);
    expect(tie.outcome, VoteOutcome.creatorDecision);
  });

  test('protocol rejects incompatible, wrong-room, unauthorized, and creator-only commands', () {
    final room = LanRoomEngine(
      roomId: 'room',
      creatorId: 'host',
      gameId: 'trivia',
    );
    room.requestJoin('host', 'Host');
    room.approve('host');
    room.requestJoin('guest', 'Guest');
    expect(
      room.apply(command(revision: room.revision, sender: 'guest')).code,
      'not_authorized',
    );
    final incompatible = LanEnvelope(
      protocolVersion: 99,
      roomId: 'room',
      messageId: 'bad-version',
      senderId: 'host',
      clientSequence: 1,
      expectedRevision: room.revision,
      type: 'transition',
      payload: const <String, dynamic>{},
    );
    expect(room.apply(incompatible).code, 'protocol_incompatible');
    final wrongRoom = LanEnvelope.fromJson(<String, dynamic>{
      ...command(revision: room.revision, id: 'wrong').toJson(),
      'roomId': 'other',
    });
    expect(room.apply(wrongRoom).code, 'wrong_room');
    room.approve('guest');
    final configure = LanEnvelope.fromJson(<String, dynamic>{
      ...command(
        revision: room.revision,
        sender: 'guest',
        id: 'config',
      ).toJson(),
      'type': 'configure',
    });
    expect(room.apply(configure).code, 'creator_only');
  });

  test(
    'configuration locks after start and readiness is recipient-addressed',
    () {
      final room = LanRoomEngine(
        roomId: 'room',
        creatorId: 'host',
        gameId: 'trivia',
      );
      room.requestJoin('host', 'Host');
      room.approve('host');
      var sequence = 1;
      LanEnvelope make(String type, Map<String, dynamic> payload) =>
          LanEnvelope(
            protocolVersion: 1,
            roomId: 'room',
            messageId: 'id-${sequence++}',
            senderId: 'host',
            clientSequence: sequence,
            expectedRevision: room.revision,
            type: type,
            payload: payload,
          );
      expect(
        room.apply(make('configure', <String, dynamic>{'rounds': 5})).accepted,
        isTrue,
      );
      expect(room.shared['rounds'], 5);
      expect(
        room.apply(make('setReady', <String, dynamic>{'ready': true})).accepted,
        isTrue,
      );
      expect((room.shared['ready'] as Map)['host'], isTrue);
      expect(
        room
            .apply(
              make('transition', <String, dynamic>{
                'phase': 'playing',
                'shared': <String, dynamic>{'question': 1},
              }),
            )
            .accepted,
        isTrue,
      );
      expect(room.phase, 'playing');
      expect(
        room.apply(make('configure', <String, dynamic>{'rounds': 9})).code,
        'phase_locked',
      );
      expect(
        room.apply(make('unknown', const <String, dynamic>{})).code,
        'unknown_command',
      );
    },
  );

  test('disconnected slot survives 60 seconds and expires afterward', () {
    var now = DateTime(2026);
    final room = LanRoomEngine(
      roomId: 'room',
      creatorId: 'host',
      gameId: 'trivia',
      now: () => now,
    );
    room.requestJoin('a', 'A');
    room.disconnected('a');
    now = now.add(const Duration(seconds: 59));
    room.removeExpiredMembers();
    expect(room.members, contains('a'));
    now = now.add(const Duration(seconds: 2));
    room.removeExpiredMembers();
    expect(room.members, isNot(contains('a')));
  });

  test('hybrid player claims are unique and room caps at 20 devices', () {
    final room = LanRoomEngine(
      roomId: 'room',
      creatorId: 'host',
      gameId: 'drawing',
    );
    for (var index = 0; index < 20; index++) {
      room.requestJoin('d$index', 'Device $index');
    }
    expect(() => room.requestJoin('overflow', 'Overflow'), throwsStateError);
    room.approve('d0', playerId: 'p1');
    expect(() => room.approve('d1', playerId: 'p1'), throwsStateError);
  });
}
