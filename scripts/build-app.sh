#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

swift build -c release --arch arm64
SWIFT_BIN_DIR="$(swift build -c release --arch arm64 --show-bin-path)"
OUTPUT_DIR="$PROJECT_DIR/build"
APP_PATH="$OUTPUT_DIR/Punto.app"
ICONSET_PATH="$OUTPUT_DIR/Punto.iconset"

mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources" "$ICONSET_PATH"
swift "$SCRIPT_DIR/make-icon.swift" "$ICONSET_PATH"
iconutil -c icns "$ICONSET_PATH" -o "$APP_PATH/Contents/Resources/Punto.icns"
cp "$SWIFT_BIN_DIR/Punto" "$APP_PATH/Contents/MacOS/Punto"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"
for LANGUAGE_RESOURCES in "$PROJECT_DIR/Sources/Punto/Resources/"*.lproj; do
    ditto "$LANGUAGE_RESOURCES" "$APP_PATH/Contents/Resources/$(basename "$LANGUAGE_RESOURCES")"
done
chmod +x "$APP_PATH/Contents/MacOS/Punto"
plutil -lint "$APP_PATH/Contents/Info.plist"
codesign --force --sign - "$APP_PATH"
codesign --verify --strict --verbose=2 "$APP_PATH"
printf '\nApp pronta: %s\n' "$APP_PATH"
