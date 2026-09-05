# Architecture

Pocket Party Games is a Flutter 3.47 application with Material 3, Riverpod-owned persistent application state, and `go_router` hash navigation. `lib/core` contains immutable models, storage, prompt loading, and reusable widgets. Each game lives in `lib/features/games`; pure game engines own rules and transitions while screens render immutable match state. Active matches remain intentionally ephemeral.

Prompt banks are validated JSON assets in `assets/data`. `GameDataRepository.load()` rejects count drift, duplicate IDs, blank IDs, and invalid trivia records during startup and tests. `AppStorage` keeps one versioned SharedPreferences snapshot for the 0–20-player roster, settings, onboarding, and bounded Solo Timer history. Truth or Dare allowances and all timer matches are session-only.

Nearby networking is split three ways:

- `lan_protocol.dart` is platform-independent authoritative state, envelope/revision, voting, projection, and reconnect logic.
- `lan_transport_io.dart` is Android/iOS Dart I/O, WSS, fingerprint pinning, mDNS, QR/manual joins, and rate limiting.
- `lan_transport_stub.dart` is selected during web compilation and contains no server/discovery imports.
- `nearby_imposter_session.dart` and `nearby_stop_timer_session.dart` apply host-authoritative game rules and produce recipient-specific projections without exposing complete private state.

Drawing strokes are normalized to the canvas (0–1 coordinates), so local replay and LAN streaming are independent of device resolution. Local time-sensitive games use a fresh monotonic `Stopwatch` per attempt. Nearby timer games calibrate client offsets, schedule starts in each recipient’s local clock domain, and calculate authoritative durations on the host.
