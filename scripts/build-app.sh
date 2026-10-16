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
swift build --configuration release --product RenderArtwork
bin=$(swift build --configuration release --show-bin-path)

# Absolute: actool runs through a long-lived helper that may resolve relative
# paths against another directory.
app="$PWD/build/FocusPilot.app"
artwork="$PWD/build/artwork"
rm -rf "$app" "$artwork"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$artwork"
cp "$bin/FocusPilot" "$app/Contents/MacOS/FocusPilot"
cp Packaging/Info.plist "$app/Contents/Info.plist"

# The app icon is generated from the logo geometry (FocusPilotCore/AppIcon),
# then compiled by actool into Assets.car plus an .icns fallback. actool
# reports the Info.plist keys that name the icon; merge them in.
"$bin/RenderArtwork" icon "$artwork/AppIcon.icon"
xcrun actool "$artwork/AppIcon.icon" \
    --compile "$app/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$artwork/icon-info.plist" \
    --errors --warnings --output-format human-readable-text
/usr/libexec/PlistBuddy -c "Merge \"$artwork/icon-info.plist\"" "$app/Contents/Info.plist"
codesign --force --sign - "$app"

echo "Built $app"
