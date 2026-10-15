#!/bin/sh
# Builds FocusPilot.app into ./build, signed ad hoc for this Mac only.
#
# SwiftPM produces a bare executable; SMAppService and LSUIElement need a real
# app bundle with an Info.plist, so this script assembles one around it.
# Ad hoc signing ("-") needs no Apple Developer membership, but the app will
# only run on the Mac that built it.
set -eu

cd "$(dirname "$0")/.."

swift build --configuration release --product FocusPilot

app=build/FocusPilot.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp "$(swift build --configuration release --show-bin-path)/FocusPilot" "$app/Contents/MacOS/FocusPilot"
cp Packaging/Info.plist "$app/Contents/Info.plist"
codesign --force --sign - "$app"

echo "Built $app"
