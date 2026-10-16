#!/bin/zsh
# Copies the ad-hoc signed app to ~/Applications and launches it once, which registers the
# Safari extension with the system. Quits any running copy first.
set -euo pipefail
here=${0:A:h:h}
src="$here/build/DerivedData/Build/Products/Release/FocusPilotSpikeS1.app"
dst="$HOME/Applications/FocusPilotSpikeS1.app"
[[ -d "$src" ]] || { echo "build first: spike/safari/scripts/build.sh" >&2; exit 1; }
# SIGTERM, not an AppleScript quit: Apple Events to another app need Automation consent.
pkill -TERM -f "FocusPilotSpikeS1.app/Contents/MacOS/FocusPilotSpikeS1$" 2>/dev/null && perl -e "select(undef,undef,undef,1.5)" || true
mkdir -p "$HOME/Applications"
rm -rf "$dst"
ditto "$src" "$dst"
codesign --verify --deep --strict "$dst"
open "$dst"
echo "installed and launched $dst"
