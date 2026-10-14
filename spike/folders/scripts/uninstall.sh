#!/bin/zsh
# Removes everything the S5 spike created on this Mac. Touches only S5 names.
#   ~/FocusPilotSpikeS5 (fixtures and the disk image; detached first if mounted)
#   ~/Library/Application Support/FocusPilotSpikeS5 (unsandboxed probe stores)
#   ~/Library/Containers/com.focuspilot.spike.s5.* (sandboxed probe stores; may need Finder)
#   LaunchServices registrations of the probe apps, and spike/folders/build/
here=${0:A:h:h}
pkill -f 'FocusPilotSpikeS5|/S5[A-Za-z]*\.app/Contents/MacOS/probe' 2>/dev/null
[[ -d ~/FocusPilotSpikeS5/mnt/volfolder ]] && hdiutil detach -quiet ~/FocusPilotSpikeS5/mnt
[[ -f "$here/build/results.jsonl" ]] && jq -r 'select(.cmd == "trash" and .ok) | .trashedTo' "$here/build/results.jsonl" | while IFS= read -r p; do rm -rf -- "$p"; done
rm -rf ~/FocusPilotSpikeS5 ~/Library/Application\ Support/FocusPilotSpikeS5
lsreg=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
for app in "$here"/build/*.app(N); do "$lsreg" -u "$app" 2>/dev/null; done
rm -rf "$here/build"
left=()
for c in ~/Library/Containers/com.focuspilot.spike.s5.*(N); do
  rm -rf "$c" 2>/dev/null
  [[ -e $c ]] && left+=("$c")
done
if (( ${#left} )); then
  echo "Could not delete (protected; drag to the Trash in Finder, then empty it):"
  printf '  %s\n' "${left[@]}"
fi
echo "S5 spike removed."
