# Nearby LAN protocol v1

Nearby is available only in installed Android/iOS builds. A room creator hosts an ephemeral WSS server on a random local port and advertises `_pocketparty._tcp` using Bonjour/Android NSD. TXT records contain the room ID, protocol version, and certificate fingerprint—never the room token, secret roles, or prompts.

## Join and trust

The host generates a room-lifetime RSA key and self-signed TLS certificate. QR payloads contain `protocolVersion`, `roomId`, local `endpoint`, SHA-256 certificate `fingerprint`, and a high-entropy one-time `token`. Discovered/manual joins use a six-character code and are rate-limited to five failed attempts per IP per minute. Clients pin the presented certificate fingerprint; there is no “continue anyway” path.

The creator approves devices and assigns at most one roster player to each phone. Additional roster players remain local to the host device, allowing hybrid rooms up to 20 players.

## Envelope and authority

Every game command uses `protocolVersion`, `roomId`, `messageId`, `senderId`, `clientSequence`, `expectedRevision`, `type`, and `payload`. The host atomically accepts the first valid command for a revision and rejects incompatible, unauthorized, duplicate, stale-sequence, and stale-revision commands with an authoritative recipient snapshot.

`privateByDevice` is never serialized directly. The host sends `projectionFor(deviceId)`, which contains only that recipient’s role, false target, drawing word, or acting prompt. Shared snapshots contain no private fields.

## Voting and recovery

The affected answerer/performer is excluded. Each eligible device votes once. More than half of cast eligible votes accepts or rejects; fewer than two voters, a completed tie, or timeout goes to the creator. Hybrid local ballots are submitted by the host.

A disconnected participant keeps the assigned slot for 60 seconds and receives a full projection on reconnect. After the grace period, clients end the room. Errors distinguish permissions, different Wi-Fi/guest isolation, fingerprint mismatch, protocol mismatch, full rooms, timeouts, and host backgrounding.

Real-device interoperability is tracked in [REAL_DEVICE_MATRIX.md](REAL_DEVICE_MATRIX.md).
