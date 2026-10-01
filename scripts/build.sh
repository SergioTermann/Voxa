#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="$PROJECT_DIR/build/Voxa.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macos13.0 \
  "$PROJECT_DIR/Sources/TextPolicy.swift" "$PROJECT_DIR/Sources/TripleSpaceTrigger.swift" "$PROJECT_DIR/Sources/ModifierTapTrigger.swift" "$PROJECT_DIR/Sources/main.swift" \
  -framework AppKit -framework SwiftUI -framework Speech -framework AVFoundation \
  -framework Carbon -framework ApplicationServices \
  -o "$APP_DIR/Contents/MacOS/VoiceCursor"
cp "$PROJECT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
if [ ! -f "$PROJECT_DIR/Assets/AppIcon.icns" ]; then
  xcrun swift "$PROJECT_DIR/scripts/draw-icon.swift" "$PROJECT_DIR/Assets"
  iconutil -c icns "$PROJECT_DIR/Assets/AppIcon.iconset" -o "$PROJECT_DIR/Assets/AppIcon.icns"
fi
cp "$PROJECT_DIR/Assets/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Assets/MenuIcon.png" "$APP_DIR/Contents/Resources/MenuIcon.png"
# Prefer an existing local development identity for stable macOS permissions.
SIGN_IDENTITY="${VOICECURSOR_SIGN_IDENTITY:-}"
if [ -z "$SIGN_IDENTITY" ]; then
  FOUND_IDENTITY="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' | head -n 1)"
  SIGN_IDENTITY="${FOUND_IDENTITY:--}"
fi
codesign --force --options runtime --entitlements "$PROJECT_DIR/entitlements.plist" --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --strict "$APP_DIR"
printf '%s\n' "Built: $APP_DIR"
