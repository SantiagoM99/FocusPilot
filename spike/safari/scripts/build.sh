#!/bin/zsh
# Generates the project, builds it with Xcode signing off, then signs ad hoc with codesign.
# Xcode will not sign ad hoc ("Sign to Run Locally") while a target claims an iOS-style
# "group." App Group: it demands a provisioning profile, which needs a team. codesign does not
# check that, so the claim reaches the binary and the runtime decides (see SPIKE_NOTES.md).
#
#   build.sh              normal build: no App Group; app and appex share the home-relative store
#   build.sh --app-group  adds the "group." App Group claim to both, to reproduce the consent
#                         prompts recorded in SPIKE_NOTES.md (Permission prompts)
set -euo pipefail
here=${0:A:h:h}
ext_entitlements="$here/entitlements/Extension.entitlements"
app_entitlements="$here/entitlements/App.entitlements"
if [[ "${1:-}" == "--app-group" ]]; then
  mkdir -p "$here/build"
  for name in Extension App; do
    python3 -c "import plistlib,sys; d=plistlib.load(open(sys.argv[1],'rb')); d['com.apple.security.application-groups']=['group.com.focuspilot.spike.s1']; plistlib.dump(d, open(sys.argv[2],'wb'))" \
      "$here/entitlements/$name.entitlements" "$here/build/$name-app-group.entitlements"
  done
  ext_entitlements="$here/build/Extension-app-group.entitlements"
  app_entitlements="$here/build/App-app-group.entitlements"
fi
"$here/scripts/generate.sh"
log="$here/build/xcodebuild.log"
# Release avoids the Debug-only *.debug.dylib, which would need its own signature.
xcodebuild -project "$here/build/project/FocusPilotSpikeS1/FocusPilotSpikeS1.xcodeproj" \
  -scheme FocusPilotSpikeS1 -configuration Release -derivedDataPath "$here/build/DerivedData" \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build > "$log" 2>&1 \
  || { grep -E "error:|BUILD FAILED" "$log" >&2; echo "full log: $log" >&2; exit 1; }
app="$here/build/DerivedData/Build/Products/Release/FocusPilotSpikeS1.app"
appex="$app/Contents/PlugIns/FocusPilotSpikeS1 Extension.appex"
codesign --force --sign - --options runtime --timestamp=none \
  --entitlements "$ext_entitlements" "$appex"
codesign --force --sign - --options runtime --timestamp=none \
  --entitlements "$app_entitlements" "$app"
codesign --verify --deep --strict "$app"
echo "built and signed ad hoc: $app (entitlements: ${ext_entitlements:t}, ${app_entitlements:t})"
