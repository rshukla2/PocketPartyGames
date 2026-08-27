# Pocket Party Games

Eight offline-first party games in one Flutter app for Android, iOS, and the web. Local play needs one device. Suitable competitive modes can also use a temporary, encrypted same-Wi-Fi room hosted by a phone—without accounts, analytics, API keys, or a cloud backend.

The interface uses a saturated, full-bleed color identity for each game, bundled offline Fredoka typography, responsive prompt sizing, and original Flutter-rendered sticker and burst graphics.

## Games

| Game | Local modes | Nearby mobile modes |
| --- | --- | --- |
| Trivia Vault | Solo, pass-and-play versus, browser, tiebreaker | Synchronized versus and correctness voting |
| Imposter | Private roles, discussion timer, reveal | Private roles, readiness, suspect vote/runoff |
| Stop the Timer | Solo, Buzzer Battle, Timer Imposter | Calibrated starts and authoritative buzz scoring |
| Truth or Dare | Categories, rotation, swaps, skips, summary | — |
| Pictionary | Quick Draw, Drawing Imposter, canvas/replay | Private words, streamed strokes, proposals/voting |
| Guess My Number | Ranges, rotation, timer, podium | — |
| Act It Out | Classic Charades, Acting Imposter | Private prompts, synchronized timer and voting |
| 5-4-3-2-1 | Five timed levels, scores and tiebreaker | — |

The migrated source contains 1,300 trivia questions, 200 Truth or Dare cards, 194 drawing prompts, 420 acting prompts, 316 countdown prompts, and 231 Imposter words. These are the measured source counts; no filler entries were invented to match older AI-generated claims.

## Run it

Prerequisites: Flutter 3.47 or newer, Android Studio for Android, and Xcode for iOS.

```sh
flutter pub get
flutter run
```

Useful checks:

```sh
dart format --output=none --set-exit-if-changed .
flutter analyze
flutter test --coverage
flutter build web --release --no-web-resources-cdn --base-href /PocketPartyGames/
flutter build appbundle --release
flutter build ios --release --no-codesign
```

The public web build uses hash routes and a custom service worker. Nearby controls intentionally explain that the installed Android/iOS app is required.

## Privacy and safety

Players and Solo Timer statistics stay on the device. Active matches and LAN rooms are ephemeral. Bold cards and some user-directed social or physical challenges are preserved verbatim from the source data; groups should skip anything unsafe or unwanted. See [PRIVACY.md](PRIVACY.md), [SECURITY.md](SECURITY.md), and [STORE_RELEASE.md](STORE_RELEASE.md).

## Project notes

- [Architecture](docs/ARCHITECTURE.md)
- [Feature parity](docs/PARITY.md)
- [LAN protocol](docs/LAN_PROTOCOL.md)
- [Contributing](CONTRIBUTING.md)

Licensed under the [MIT License](LICENSE).
