#!/bin/zsh
# Copies the ad-hoc signed app to ~/Applications and launches it once, which registers the
# Safari extension with the system. Quits any running copy first.
set -euo pipefail
here=${0:A:h:h}
src="$here/build/DerivedData/Build/Products/Release/FocusPilotSpikeS1.app"
dst="$HOME/Applications/FocusPilotSpikeS1.app"
[[ -d "$src" ]] || { echo "build first: spike/safari/scripts/build.sh" >&2; exit 1; }
osascript -e 'tell application id "com.focuspilot.spike.s1" to quit' 2>/dev/null || true
mkdir -p "$HOME/Applications"
rm -rf "$dst"
ditto "$src" "$dst"
codesign --verify --deep --strict "$dst"
open "$dst"
echo "installed and launched $dst"
