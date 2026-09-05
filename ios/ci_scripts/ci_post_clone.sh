#!/bin/sh

# Xcode Cloud checks out the repository without Flutter's generated iOS files.
# Generate those files before Xcode resolves package dependencies.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Install Flutter in the temporary Xcode Cloud environment.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"

flutter precache --ios
flutter pub get
flutter build ios --config-only --release --no-codesign

# Keep CocoaPods dependencies in sync for plugins that use them.
cd ios
HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
pod install
