#!/bin/sh
# Build CodexAccounts as a proper .app bundle with LSUIElement=true.
# SPM-only executables don't reliably anchor a SwiftUI MenuBarExtra status item;
# wrapping into a bundle with the right Info.plist fixes that.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

CONFIG="${CONFIG:-release}"
APP_NAME="Codex Accounts"
APP_BUNDLE_ID="${APP_BUNDLE_ID:-dev.codexaccounts.app}"
APP_VERSION="${APP_VERSION:-0.1.0}"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR="$ROOT/.build/$CONFIG"
if [ ! -x "$BIN_DIR/CodexAccounts" ]; then
    # arch-specific dir on Apple Silicon
    ARCH_DIR=$(/bin/ls -1d "$ROOT/.build"/*-apple-macosx/"$CONFIG" 2>/dev/null | head -n1 || true)
    if [ -n "$ARCH_DIR" ] && [ -x "$ARCH_DIR/CodexAccounts" ]; then
        BIN_DIR="$ARCH_DIR"
    else
        echo "Could not find built binary under .build/" >&2
        exit 1
    fi
fi

DIST="$ROOT/dist"
APP="$DIST/$APP_NAME.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN_DIR/CodexAccounts" "$APP/Contents/MacOS/CodexAccounts"
if [ -d "$BIN_DIR/CodexAccounts_CodexAccounts.bundle" ]; then
    cp -R "$BIN_DIR/CodexAccounts_CodexAccounts.bundle" "$APP/Contents/MacOS/"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$APP_BUNDLE_ID</string>
    <key>CFBundleExecutable</key>
    <string>CodexAccounts</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
EOF

# Re-sign with ad-hoc signature so Gatekeeper doesn't kill it on launch
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "==> Built: $APP"
echo
echo "Run with:    open '$APP'"
echo "Or install:  mv '$APP' /Applications/"
