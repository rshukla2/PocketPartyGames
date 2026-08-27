# Contributing

Open an issue before a large behavior or data change. Use Flutter 3.47+, branch from `main`, keep unrelated edits out of the change, and never commit room captures, personal information, signing material, or store credentials.

Run `dart format --output=none --set-exit-if-changed .`, `flutter analyze`, and `flutter test --coverage`. Changes to prompt JSON must preserve stable IDs, disclose count changes, pass data validation, and never silently alter Bold content. LAN changes need codec, authorization, redaction, race, reconnect, and simulated-client coverage plus relevant real-device matrix runs.

Pull requests should explain user-visible behavior, tests, privacy/permission impact, platform impact, and screenshots for UI changes. By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
