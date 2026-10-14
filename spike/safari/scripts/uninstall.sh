#!/bin/zsh
# Removes everything the spike created outside the repo. Pass --keep-data to keep the inbox,
# app events and policy for analysis. Disable the extension in Safari first (SPIKE_NOTES.md).
set -euo pipefail
here=${0:A:h:h}
app="$HOME/Applications/FocusPilotSpikeS1.app"
osascript -e 'tell application id "com.focuspilot.spike.s1" to quit' 2>/dev/null || true
pkill -f "FocusPilotSpikeS1.app/Contents/MacOS/FocusPilotSpikeS1" 2>/dev/null || true
# Unregister the login item through the app itself while its binary still exists.
lsregister=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
if [[ -d "$app" ]]; then
  "$app/Contents/MacOS/FocusPilotSpikeS1" --unregister-login-item || true
  pluginkit -r "$app/Contents/PlugIns/FocusPilotSpikeS1 Extension.appex" 2>/dev/null || true
  "$lsregister" -u "$app" 2>/dev/null || true
  rm -rf "$app"
fi
built="$here/build/DerivedData/Build/Products/Release/FocusPilotSpikeS1.app"
[[ -d "$built" ]] && { "$lsregister" -u "$built" 2>/dev/null || true; }
containers=(
  "$HOME/Library/Group Containers/group.com.focuspilot.spike.s1"
  "$HOME/Library/Containers/com.focuspilot.spike.s1.Extension"
  "$HOME/Library/Containers/com.focuspilot.spike.s1.probe"
  "$HOME/Library/Containers/com.focuspilot.spike.s1.probe-nogroup"
)
if [[ "${1:-}" != "--keep-data" ]]; then
  rm -rf "$HOME/Library/Application Support/FocusPilotSpikeS1"
  # macOS protects sandbox containers: a terminal without Full Disk Access gets "Operation not
  # permitted" on the container's metadata. Remove what it can and list the rest.
  for c in $containers; do rm -rf "$c" 2>/dev/null || true; done
  defaults delete com.focuspilot.spike.s1 2>/dev/null || true
fi
rm -rf "$here/build"
echo "removed app, build/ and spike data."
if [[ "${1:-}" != "--keep-data" ]]; then
  for c in $containers; do [[ -e "$c" ]] && echo "left behind (protected container; drag to Trash in Finder or rm from a terminal with Full Disk Access): $c"; done
fi
echo "Check System Settings > General > Login Items & Extensions for a leftover FocusPilotSpikeS1 entry."
