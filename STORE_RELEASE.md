# Store release checklist

## Identity and signing

- App: Pocket Party Games; version `1.0.0+1`; package/bundle ID `com.rshukla2.pocketpartygames`.
- Android minimum SDK 24; iOS deployment target 15.0.
- Keep keystores, passwords, provisioning profiles, Apple team IDs, API keys, and store credentials outside Git.
- Configure Android release signing through an untracked `key.properties`/CI secret setup before upload.
- Select the publisher’s Apple team in Xcode and archive with the distribution profile.

## Listing copy

Short description: “Eight offline party games for one phone or a private same-Wi-Fi room.”

Long description: “Bring Trivia, Imposter, Stop the Timer, Truth or Dare, Pictionary, Guess My Number, Charades, and 5-4-3-2-1 anywhere. Play locally with one phone or use supported Nearby modes on installed Android and iOS apps. No accounts, ads, analytics, subscriptions, or cloud backend.”

## Privacy/data safety

- Data collected by developer: none.
- Data shared: none.
- Accounts/deletion URL: not applicable; Settings can erase local data.
- Local player names and timer history: device-only app functionality.
- Camera: optional QR scanning; not retained.
- Local network: multiplayer device discovery/connection; not retained by developer.
- Declare user-generated social/physical challenge content and mature Bold prompts in age/content questionnaires. Do not describe the app as child-directed without a separate content review.

## Screenshots

Capture onboarding, library, roster, one local setup/play/result flow, drawing canvas, and Nearby join/lobby. Use deterministic demo names without personal data. Capture 390×844 phone frames plus store-required tablet sizes; include a responsive desktop web capture. Never show live local IPs, room tokens, certificate fingerprints, or signing/team data.

## Validation

- Run analyze, unit/widget/integration tests, web release, Android AAB, and unsigned iOS release.
- Test first-visit then offline reload at `/PocketPartyGames/`.
- Complete `docs/REAL_DEVICE_MATRIX.md` and permission-denial checks.
- Confirm licenses/notices, privacy URLs, support URL, content rating, export encryption answers, and store artwork.
