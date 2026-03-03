#!/bin/bash
# Build and run PhotoOrganizer (Debug)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"

echo "==> Building PhotoOrganizer..."
xcodebuild \
    -project "$SCRIPT_DIR/PhotoOrganizer.xcodeproj" \
    -scheme PhotoOrganizer \
    -configuration Debug \
    -derivedDataPath "$BUILD_DIR" \
    build 2>&1 | grep -E "(error:|warning:|Build succeeded|Build FAILED)" || true

APP_PATH="$BUILD_DIR/Build/Products/Debug/PhotoOrganizer.app"

if [ -d "$APP_PATH" ]; then
    echo "==> Build succeeded: $APP_PATH"
    echo "==> Launching..."
    open "$APP_PATH"
else
    echo "==> Build failed — check output above"
    exit 1
fi
