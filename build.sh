#!/bin/bash
# Build Touchline.swift into a dock-less menu-bar .app bundle. No Xcode project needed.
set -euo pipefail
cd "$(dirname "$0")"

APP="Touchline.app"
BIN="Touchline"
SRC="Touchline.swift"
CONTENTS="$APP/Contents"

echo "› Compiling ($(swiftc --version | head -1))..."
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

# Optimized, single-binary build. Target matches the local SDK's deployment floor.
swiftc -O -whole-module-optimization \
    -parse-as-library \
    -target arm64-apple-macosx13.0 \
    -framework SwiftUI -framework AppKit \
    "$SRC" -o "$CONTENTS/MacOS/$BIN"

# App icon: regenerate from source if the compiled .icns is missing.
if [ ! -f Touchline.icns ]; then
    echo "› Generating icon..."
    swiftc make_icon.swift -o make_icon && ./make_icon && iconutil -c icns Touchline.iconset -o Touchline.icns
fi
cp Touchline.icns "$CONTENTS/Resources/Touchline.icns"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Touchline</string>
    <key>CFBundleDisplayName</key>     <string>Touchline</string>
    <key>CFBundleIdentifier</key>      <string>com.angryrou.touchline</string>
    <key>CFBundleVersion</key>         <string>1</string>
    <key>CFBundleShortVersionString</key> <string>1.0.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>Touchline</string>
    <key>CFBundleIconFile</key>        <string>Touchline</string>
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
