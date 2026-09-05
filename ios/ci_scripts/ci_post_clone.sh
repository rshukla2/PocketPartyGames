#!/bin/sh

# Xcode Cloud checks out the repository without Flutter's generated iOS files.
# Generate those files before Xcode resolves package dependencies.
set -eux

REPOSITORY_PATH="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPOSITORY_PATH"

# Xcode Cloud images may already provide Flutter. Reuse it; otherwise install a
# stable SDK into the temporary build environment.
if command -v flutter >/dev/null 2>&1; then
  FLUTTER_BIN="$(command -v flutter)"
else
  FLUTTER_HOME="$HOME/flutter"
  if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
    git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$FLUTTER_HOME"
  fi
  FLUTTER_BIN="$FLUTTER_HOME/bin/flutter"
fi

FLUTTER_DIR="$(cd "$(dirname "$FLUTTER_BIN")/.." && pwd)"
export PATH="$FLUTTER_DIR/bin:$PATH"

flutter precache --ios
flutter pub get
# This creates ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage.
flutter build ios --config-only --release --no-codesign

# Keep CocoaPods dependencies in sync for plugins that use them. Xcode Cloud
# normally has CocoaPods installed; install it only when it is unavailable.
if ! command -v pod >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
fi
cd ios
pod install
