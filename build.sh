#!/bin/bash
# Build WC26.swift into a dock-less menu-bar .app bundle. No Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")"

APP="WC26.app"
BIN="WC26"
CONTENTS="$APP/Contents"

echo "› Compiling ($(swiftc --version | head -1))..."
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# Optimized, single-binary build. Target matches the local SDK's deployment floor.
swiftc -O -whole-module-optimization \
    -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -framework SwiftUI -framework AppKit \
    WC26.swift -o "$CONTENTS/MacOS/$BIN"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>WC26</string>
    <key>CFBundleDisplayName</key>     <string>WC26 Live</string>
    <key>CFBundleIdentifier</key>      <string>local.wc26.menubar</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key> <string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>WC26</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <key>LSUIElement</key>             <true/>
    <key>NSHighResolutionCapable</key> <true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS network entitlements & Gatekeeper are happy locally.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "› Built $APP"
echo "› Run:   open $APP        (or ./$CONTENTS/MacOS/$BIN to see logs)"
