#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
RELEASE_VERSION="${1:-0.1.0}"

if [[ ! "$RELEASE_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9][A-Za-z0-9.-]*)?$ ]]; then
    printf 'Invalid release version: %s\n' "$RELEASE_VERSION" >&2
    exit 1
fi

cd "$PROJECT_DIR"
"$SCRIPT_DIR/build-app.sh"

APP_PATH="$PROJECT_DIR/build/Punto.app"
APP_BINARY="$APP_PATH/Contents/MacOS/Punto"
ARCHITECTURES="$(lipo -archs "$APP_BINARY")"
if [[ "$ARCHITECTURES" != "arm64" ]]; then
    printf 'Expected an arm64-only app; found: %s\n' "$ARCHITECTURES" >&2
    exit 1
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
if [[ "$APP_VERSION" != "$RELEASE_VERSION" ]]; then
    printf 'App version %s does not match requested release %s. Update Resources/Info.plist before packaging.\n' "$APP_VERSION" "$RELEASE_VERSION" >&2
    exit 1
fi

codesign --verify --strict --verbose=2 "$APP_PATH"

ARCHIVE_NAME="Punto-$RELEASE_VERSION-macOS-arm64.zip"
ARCHIVE_PATH="$PROJECT_DIR/build/$ARCHIVE_NAME"
ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ARCHIVE_PATH"

# Basename makes `shasum -a 256 -c` work in the user's download folder.
cd "$PROJECT_DIR/build"
shasum -a 256 "$ARCHIVE_NAME" > "$ARCHIVE_NAME.sha256"
shasum -a 256 -c "$ARCHIVE_NAME.sha256"
printf '\nPreview: %s\nChecksum: %s.sha256\n' "$ARCHIVE_PATH" "$ARCHIVE_PATH"
