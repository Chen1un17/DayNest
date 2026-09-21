#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PWD/dist/DayNest.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
if [ ! -f "$PWD/dist/AppIcon.icns" ]; then
  swift scripts/make-icon.swift dist/AppIcon.iconset
  iconutil -c icns dist/AppIcon.iconset -o dist/AppIcon.icns
fi
cp "$BIN_DIR/DayNest" "$APP_DIR/Contents/MacOS/DayNest"
cat > "$APP_DIR/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DayNest</string>
<key>CFBundleIdentifier</key><string>local.daynest.app</string>
<key>CFBundleName</key><string>DayNest</string>
<key>CFBundleDisplayName</key><string>DayNest · 日有安排</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>NSHumanReadableCopyright</key><string>DayNest — Your day, thoughtfully arranged.</string>
</dict></plist>
PLIST
# Use an ad-hoc local signature; no paid developer account is required.
if [ -f "$PWD/dist/AppIcon.icns" ]; then
  cp "$PWD/dist/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
fi
codesign --force --deep --sign - "$APP_DIR"
printf 'Built: %s\n' "$APP_DIR"
