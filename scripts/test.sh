#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/build"
xcrun swiftc -swift-version 5 "$PROJECT_DIR/Sources/TextPolicy.swift" \
  "$PROJECT_DIR/Sources/TripleSpaceTrigger.swift" "$PROJECT_DIR/Tests/main.swift" \
  -framework AppKit -framework ApplicationServices -o "$PROJECT_DIR/build/VoiceCursorTests"
"$PROJECT_DIR/build/VoiceCursorTests"
plutil -lint "$PROJECT_DIR/Info.plist" "$PROJECT_DIR/entitlements.plist"
"$PROJECT_DIR/build/Voxa.app/Contents/MacOS/VoiceCursor" --smoke-test
