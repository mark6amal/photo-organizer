#!/bin/bash
# Build and run PhotoOrganizer (Debug)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
LOG_PATH="$BUILD_DIR/xcodebuild.log"
DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"

if [[ "$DEVELOPER_DIR" == "/Library/Developer/CommandLineTools" ]]; then
    echo "==> Build failed"
    echo "The active developer directory points to Command Line Tools."
    echo "Photo Organizer requires the full Xcode app for xcodebuild."
    echo "Run:"
    echo "  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
    exit 1
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building PhotoOrganizer..."
xcodebuild \
    -project "$SCRIPT_DIR/PhotoOrganizer.xcodeproj" \
    -scheme PhotoOrganizer \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    build 2>&1 | tee "$LOG_PATH" | grep -E "(error:|warning:|Build succeeded|Build FAILED)" || true

BUILD_STATUS=${PIPESTATUS[0]}

APP_PATH="$BUILD_DIR/Build/Products/Debug/PhotoOrganizer.app"
EXECUTABLE_PATH="$APP_PATH/Contents/MacOS/PhotoOrganizer"

if [ "$BUILD_STATUS" -ne 0 ]; then
    echo "==> Build failed — full log: $LOG_PATH"
    exit "$BUILD_STATUS"
fi

if [ -x "$EXECUTABLE_PATH" ]; then
    echo "==> Build succeeded: $APP_PATH"
    echo "==> Launching..."
    open "$APP_PATH"
else
    echo "==> Build failed — app bundle exists but executable is missing"
    echo "==> Check full log: $LOG_PATH"
    exit 1
fi
