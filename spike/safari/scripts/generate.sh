#!/bin/zsh
# Generates the Xcode project into spike/safari/build/project with Apple's
# safari-web-extension-converter, then lays the spike's Swift sources and entitlements over it.
# The project references extension/ in place (no --copy-resources), so JS edits need no regenerate.
set -euo pipefail
here=${0:A:h:h}
out="$here/build/project"
name=FocusPilotSpikeS1
rm -rf "$out"
mkdir -p "$out"
xcrun safari-web-extension-converter --project-location "$out" --app-name $name \
  --bundle-identifier com.focuspilot.spike.s1 --swift --macos-only --no-open --no-prompt --force \
  "$here/extension"
proj="$out/$name"
# Each target has exactly one Swift file in the generated project; the shared store code is
# concatenated into both so no file has to be added to the pbxproj.
cat "$here/src/Shared/SharedStore.swift" "$here/src/App/App.swift" > "$proj/$name/AppDelegate.swift"
print -r -- "// Unused: the spike app is SwiftUI (see AppDelegate.swift)." > "$proj/$name/ViewController.swift"
cat "$here/src/Shared/SharedStore.swift" "$here/src/Extension/SafariWebExtensionHandler.swift" \
  > "$proj/$name Extension/SafariWebExtensionHandler.swift"
cp "$here/entitlements/App.entitlements" "$proj/$name/$name.entitlements"
cp "$here/entitlements/Extension.entitlements" "$proj/$name Extension/$name Extension.entitlements"
python3 "$here/scripts/patch-pbxproj.py" "$proj/$name.xcodeproj/project.pbxproj"
echo "generated $proj/$name.xcodeproj"
