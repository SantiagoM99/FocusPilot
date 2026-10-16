#!/bin/zsh
# Checks that need no human and no Safari. Run after build.sh.
#  1. JS syntax and policy evaluation rules (node).
#  2. Signatures and entitlements of the built app and appex.
#  3. Shared-store access from the unsandboxed app (--probe).
#  4. Shared-store access from a sandboxed command-line stand-in for the appex, signed ad hoc
#     with the appex's exact entitlements, run under launchd so the terminal's privacy
#     permissions are not inherited. Nothing here touches the App Group container, which would
#     raise a consent prompt (SPIKE_NOTES.md, Permission prompts).
set -euo pipefail
here=${0:A:h:h}
app="$here/build/DerivedData/Build/Products/Release/FocusPilotSpikeS1.app"
appex="$app/Contents/PlugIns/FocusPilotSpikeS1 Extension.appex"
out="$here/build/probe"
mkdir -p "$out"

echo "== 1. extension JS"
for f in policy.js content.js popup.js; do node --check "$here/extension/$f"; done
node --check "$here/extension/background.js"
jq empty "$here/extension/manifest.json"; echo "manifest.json parses"
node "$here/scripts/test-policy.mjs"

echo "== 2. signatures"
codesign --verify --deep --strict "$app" && echo "codesign verify ok"
for b in "$app" "$appex"; do
  codesign -dv "$b" 2>&1 | grep -E "^(Identifier|Signature|TeamIdentifier)"
  codesign -d --entitlements - --xml "$b" 2>/dev/null | plutil -p -
done

echo "== 3. unsandboxed app probe"
"$app/Contents/MacOS/FocusPilotSpikeS1" --probe | jq -c '.[] | {transport, writable, error}'

echo "== 4. sandboxed stand-in probes (launchd)"
swiftc -O -o "$out/focuspilot-s1-probe" "$here/src/Shared/SharedStore.swift" "$here/src/Probe/main.swift" \
  -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$here/src/Probe/Info.plist"
codesign --force --sign - --options runtime --identifier com.focuspilot.spike.s1.probe \
  --entitlements "$here/entitlements/Extension.entitlements" "$out/focuspilot-s1-probe" 2>/dev/null
for n in focuspilot-s1-probe; do
  rm -f "$out/$n.launchd.out"
  launchctl submit -l "com.focuspilot.s1.$n" -o "$out/$n.launchd.out" -e "$out/$n.launchd.err" -- "$out/$n"
  for i in {1..60}; do [[ -s "$out/$n.launchd.out" ]] && break; perl -e 'select(undef,undef,undef,0.25)'; done
  launchctl remove "com.focuspilot.s1.$n" 2>/dev/null || true
  echo "-- $n"
  python3 -c "import json,sys; d=json.JSONDecoder().raw_decode(open(sys.argv[1]).read().lstrip())[0]; print(' sandboxed', d['sandboxed']); [print(' ', s['transport'], 'writable' if s['writable'] else 'DENIED', s.get('error','')[:90]) for s in d['stores']]" "$out/$n.launchd.out"
done
