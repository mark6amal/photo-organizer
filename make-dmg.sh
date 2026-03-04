#!/bin/bash
# Build a Release app bundle and package it into a shareable DMG.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
DIST_DIR="$SCRIPT_DIR/dist"
APP_NAME="PhotoOrganizer"
SCHEME="PhotoOrganizer"
VERSION_SUFFIX="${1:-}"

if [ -n "$VERSION_SUFFIX" ]; then
    DMG_NAME="$APP_NAME-macOS-$VERSION_SUFFIX.dmg"
else
    DMG_NAME="$APP_NAME.dmg"
fi

APP_PATH="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$DMG_NAME"

mkdir -p "$DIST_DIR"

STAGING_DIR="$(mktemp -d "$DIST_DIR/.dmg-staging.XXXXXX")"
DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"

cleanup() {
    rm -rf "$STAGING_DIR"
}

trap cleanup EXIT

if [[ "$DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]]; then
    echo "==> Full Xcode is required. Run:"
    echo "    sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

echo "==> Building $APP_NAME (Release)..."
xcodebuild \
    -project "$SCRIPT_DIR/$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    build 2>&1 | grep -E "(error:|warning:|Build succeeded|Build FAILED)" || true

if [ ! -d "$APP_PATH" ]; then
    echo "==> Build failed — expected app bundle not found at $APP_PATH"
    exit 1
fi

echo "==> Preparing DMG contents..."
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

echo "==> Creating DMG..."
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "==> DMG ready: $DMG_PATH"
echo "==> Share this file via GitHub Releases or direct download."
