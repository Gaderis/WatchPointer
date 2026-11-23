#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_BUNDLE="$REPO_ROOT/WatchPointer.app"

echo "==> Building WatchPointer (Release)..."
swift build --package-path "$SCRIPT_DIR" -c release

echo "==> Packaging WatchPointer.app..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources/Game"

cp "$SCRIPT_DIR/.build/release/WatchPointer" "$APP_BUNDLE/Contents/MacOS/WatchPointer"
cp "$SCRIPT_DIR/Sources/WatchPointer/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
cp "$REPO_ROOT/Game/index.html" "$APP_BUNDLE/Contents/Resources/Game/index.html"

if [ -f "$REPO_ROOT/docs/icon.png" ]; then
    /usr/bin/sips -s format icns -z 512 512 "$REPO_ROOT/docs/icon.png" \
        --out "$APP_BUNDLE/Contents/Resources/AppIcon.icns" >/dev/null
fi

echo "==> Code signing WatchPointer.app (ad-hoc)..."
/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"

if [ "${1:-}" = "--install" ]; then
    echo "==> Installing to /Applications/WatchPointer.app..."
    rm -rf /Applications/WatchPointer.app
    cp -R "$APP_BUNDLE" /Applications/WatchPointer.app
    echo "Done! Installed at /Applications/WatchPointer.app"
else
    echo "Done! Built at $APP_BUNDLE"
    echo "Tip: run './Mac/build-app.sh --install' to copy it to /Applications."
fi
