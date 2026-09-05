# Nearby LAN protocol v2

Nearby is available only in installed Android/iOS builds. A room creator hosts an ephemeral WSS server on a random local port and advertises `_pocketparty._tcp` using Bonjour/Android NSD. TXT records contain the room ID, protocol version, and certificate fingerprint—never the room token, secret roles, or prompts.

## Join and trust

The host generates a room-lifetime RSA key and self-signed TLS certificate. QR payloads contain `protocolVersion`, `roomId`, local `endpoint`, SHA-256 certificate `fingerprint`, and a high-entropy one-time `token`. Discovered/manual joins use a six-character code and are rate-limited to five failed attempts per IP per minute. Clients pin the presented certificate fingerprint; there is no “continue anyway” path.

The creator approves devices and assigns at most one roster player to each phone. Additional roster players remain local to the host device, allowing hybrid rooms up to 20 players.

## Envelope and authority

Every game command uses `protocolVersion`, `roomId`, `messageId`, `senderId`, `clientSequence`, `expectedRevision`, `type`, and `payload`. The host binds every accepted command to the authenticated socket identity, atomically accepts the first valid command for a revision, and rejects sender spoofing, incompatible, unauthorized, duplicate, stale-sequence, and stale-revision commands with an authoritative recipient snapshot.

Raw client game commands are never rebroadcast. The host uses addressed messages and sends `projectionFor(deviceId)`, which contains only that recipient’s role, false target, drawing word, or acting prompt. The complete private-state map is never serialized, and shared snapshots contain no private fields.

## Imposter state machine

Imposter uses a host-authoritative `lobby → private reveal/readiness → discussion → voting → optional runoff → next round/result` flow. Classic projections expose only the recipient’s role, word, and optional hint. Odd Word projections expose only the recipient’s assigned word and intentionally omit role identity. Discussion uses a host deadline; reaching zero alerts devices but does not advance the phase.

Each living player has one secret ballot and cannot vote for themselves. The highest total eliminates a player. A first tie creates a runoff limited to the tied candidates; a second tie requires the room creator to choose. Hybrid players vote sequentially on the host phone. Intermediate totals and ballots never appear in snapshots.

## Stop the Timer state machines

Buzzer Battle uses a host-authoritative `target reveal → randomized handoffs → scheduled private attempts → ranked round result → next round/final result` flow. The goal is configurable from 3–15 points. A recipient sees only the currently shared phase and its own active-turn controls until the host releases the round result; intermediate attempts are never broadcast.

Timer Imposter uses `private reveal/readiness → randomized handoffs → scheduled private attempts → voting → optional runoff → result`. In False Target rooms, each recipient receives only its assigned neutral target; the projection does not identify the role. In No Target rooms, only an imposter recipient receives the `IMPOSTER` marker. The full assignment map is disclosed only in the final result.

Before a remote timer attempt, the host takes repeated four-timestamp samples and uses the median of the five lowest-round-trip samples to estimate that device’s clock offset. At least three samples are required. The host supplies a recipient-local scheduled start, accepts a stop only from the authenticated active device, converts the timestamp back to host time, and calculates the authoritative duration. An interrupted attempt returns to that player’s handoff and restarts after reconnection.

Timer Imposter ballots are private, prohibit self-votes and duplicates, and reveal no intermediate totals. A first-place tie creates one runoff; a second tie is resolved by the creator. Hybrid local players cast sequentially on the host.

## Voting and recovery

The affected answerer/performer is excluded. Each eligible device votes once. More than half of cast eligible votes accepts or rejects; fewer than two voters, a completed tie, or timeout goes to the creator. Hybrid local ballots are submitted by the host.

A disconnected participant keeps the assigned slot for 60 seconds and receives a fresh recipient projection on reconnect. After the grace period, the host removes that player before tallying; any surviving valid ballots remain, and team win conditions are reevaluated. If the host disappears, clients pause immediately, retry during the same 60-second window, and then close the room. Errors distinguish permissions, different Wi-Fi/guest isolation, fingerprint mismatch, protocol mismatch, full rooms, timeouts, and host backgrounding.

Real-device interoperability is tracked in [REAL_DEVICE_MATRIX.md](REAL_DEVICE_MATRIX.md).
