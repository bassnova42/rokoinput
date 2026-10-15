#!/bin/zsh
set -eu
cd "$(dirname "$0")/.."
APP="build/Roko Input.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/keyboard.html "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/zh-Hans.lproj Resources/en.lproj "$APP/Contents/Resources/"
SDK=$(xcrun --show-sdk-path)
for ARCH in arm64 x86_64; do
    xcrun swiftc Sources/*.swift -sdk "$SDK" -target "$ARCH-apple-macosx13.0" -O -o "build/RokoInput-$ARCH" -framework Cocoa -framework AVFoundation -framework Speech -framework Carbon -framework InputMethodKit
done
lipo -create build/RokoInput-arm64 build/RokoInput-x86_64 -output "$APP/Contents/MacOS/RokoInput"
xcrun swift scripts/make-icons.swift "$APP/Contents/Resources"
codesign --force --sign - --identifier im.roko.inputmethod.RokoInput "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
echo "Built $APP"
