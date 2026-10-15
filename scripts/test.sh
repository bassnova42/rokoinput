#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
mkdir -p build
xcrun swiftc Sources/HistoryStore.swift Sources/HoldKey.swift Sources/StatisticsStore.swift Sources/Shortcut.swift Sources/RecognitionFailure.swift Sources/TranscriptBuffer.swift Tests/CoreTests.swift -o build/core-tests
build/core-tests
xcrun swiftc Sources/RecordingHUD.swift Tests/AudioLevelTests.swift -framework Cocoa -framework AVFoundation -o build/audio-level-tests
build/audio-level-tests
zsh -n scripts/build.sh scripts/install-local.sh
plutil -lint Resources/Info.plist
