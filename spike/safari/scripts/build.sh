#!/bin/zsh
# Generates the project, builds it with Xcode signing off, then signs ad hoc with codesign.
# Xcode will not sign ad hoc ("Sign to Run Locally") while a target claims an iOS-style
# "group." App Group: it demands a provisioning profile, which needs a team. codesign does not
# check that, so the claim reaches the binary and the runtime decides (see SPIKE_NOTES.md).
#
#   build.sh                  normal build
#   build.sh --no-app-group   appex signed without the App Group claim, so the handler must use
#                             the home-relative temporary exception (fallback transport test)
set -euo pipefail
here=${0:A:h:h}
ext_entitlements="$here/entitlements/Extension.entitlements"
if [[ "${1:-}" == "--no-app-group" ]]; then
  mkdir -p "$here/build"
  python3 -c "import plistlib,sys; d=plistlib.load(open(sys.argv[1],'rb')); d.pop('com.apple.security.application-groups'); plistlib.dump(d, open(sys.argv[2],'wb'))" \
    "$ext_entitlements" "$here/build/Extension-no-app-group.entitlements"
  ext_entitlements="$here/build/Extension-no-app-group.entitlements"
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
  --entitlements "$here/entitlements/App.entitlements" "$app"
codesign --verify --deep --strict "$app"
echo "built and signed ad hoc: $app (appex entitlements: ${ext_entitlements:t})"
