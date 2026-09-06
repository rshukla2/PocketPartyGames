#!/bin/sh

# Xcode Cloud checks out the repository without Flutter's generated iOS files.
# Generate those files before Xcode resolves package dependencies.
set -eux

REPOSITORY_PATH="${CI_PRIMARY_REPOSITORY_PATH:-$(cd "$(dirname "$0")/../.." && pwd)}"
cd "$REPOSITORY_PATH"

# Install a private stable SDK at a known path. This avoids depending on an
# Xcode Cloud image's Flutter symlink layout.
FLUTTER_HOME="$HOME/flutter-ci"
if [ ! -x "$FLUTTER_HOME/bin/flutter" ]; then
  git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$FLUTTER_HOME"
fi
export FLUTTER_ROOT="$FLUTTER_HOME"
export PATH="$FLUTTER_ROOT/bin:$PATH"
export FLUTTER_BUILD_MODE=Release
export CONFIGURATION=Release
export ACTION=build
export FLUTTER_APPLICATION_PATH="$REPOSITORY_PATH"
export SOURCE_ROOT="$REPOSITORY_PATH/ios"
export SRCROOT="$REPOSITORY_PATH/ios"
export ARCHS=arm64
export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)"
export BUILT_PRODUCTS_DIR="$REPOSITORY_PATH/build/ios/Release-iphoneos"
export TARGET_BUILD_DIR="$BUILT_PRODUCTS_DIR"
export FRAMEWORKS_FOLDER_PATH=Frameworks
mkdir -p "$BUILT_PRODUCTS_DIR"

flutter precache --ios --force
if [ ! -d "$FLUTTER_ROOT/bin/cache/artifacts/engine/ios-release/Flutter.xcframework" ]; then
  echo "Flutter iOS release framework was not downloaded by precache."
  find "$FLUTTER_ROOT/bin/cache/artifacts/engine" -maxdepth 2 -type d -name 'Flutter.xcframework' -print || true
  exit 1
fi
flutter pub get
# This creates ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage.
# This project uses Flutter Swift Package Manager and intentionally has no
# Podfile, so invoke the backend preparation directly instead of `flutter
# build ios`, which attempts to run CocoaPods during configuration.
if [ -f ios/Podfile ]; then
  flutter build ios --config-only --release --no-codesign
else
  "$FLUTTER_ROOT/packages/flutter_tools/bin/xcode_backend.sh" prepare
fi

# Keep CocoaPods dependencies in sync only for projects that use them.
if [ -f ios/Podfile ]; then
  if ! command -v pod >/dev/null 2>&1; then
    HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
  fi
  cd ios
  pod install
else
  echo "No ios/Podfile found; using Flutter Swift Package Manager dependencies."
fi
