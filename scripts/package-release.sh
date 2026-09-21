#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' dist/DayNest.app/Contents/Info.plist)
ARCH=$(uname -m)
ARCHIVE="DayNest-${VERSION}-macOS-${ARCH}.zip"
mkdir -p dist/release
# Include only the application bundle, never local records or build intermediates.
ditto -c -k --sequesterRsrc --keepParent dist/DayNest.app "dist/release/$ARCHIVE"
(cd dist/release && shasum -a 256 "$ARCHIVE" > SHA256SUMS.txt)
printf 'Release archive: dist/release/%s\n' "$ARCHIVE"
