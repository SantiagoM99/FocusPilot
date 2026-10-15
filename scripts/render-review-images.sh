#!/bin/sh
# Renders PNGs of the menu bar glyphs and the app icon for visual review,
# without launching the app. Usage: scripts/render-review-images.sh <directory>
#
# The app icon images come from Icon Composer's ictool, which renders the same
# AppIcon.icon that build-app.sh compiles, with the system squircle and glass,
# in light and dark appearance.
set -eu

out=${1:?usage: $0 <directory>}
cd "$(dirname "$0")/.."

swift build --configuration release --product RenderArtwork
bin=$(swift build --configuration release --show-bin-path)
ictool="$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool"

mkdir -p "$out"
icon=$(mktemp -d)/AppIcon.icon
"$bin/RenderArtwork" icon "$icon"
"$bin/RenderArtwork" glyphs "$out"

for rendition in Default Dark; do
    name=$([ "$rendition" = Default ] && echo light || echo dark)
    for size in 1024 128 32 16; do
        "$ictool" "$icon" --export-image --output-file "$out/app-icon-$size-$name.png" \
            --platform macOS --rendition "$rendition" --width "$size" --height "$size" --scale 1 >/dev/null
    done
done

echo "Rendered review images into $out"
