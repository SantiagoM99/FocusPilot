#!/bin/zsh
# Builds the probe with swiftc into three ad-hoc signed app bundles in build/:
#   S5Unsandboxed.app   com.focuspilot.spike.s5.unsandboxed   no sandbox
#   S5Sandboxed.app     com.focuspilot.spike.s5.sandboxed     sandbox + user-selected.read-write + bookmarks.app-scope
#   S5SandboxedNoBM.app com.focuspilot.spike.s5.sandboxed-nobm sandbox + user-selected.read-write only
# BUILD_STAMP (default: "1") goes into Info.plist, so a rebuild with a new stamp gets a new cdhash
# under the same bundle ID: this is how the ad-hoc re-sign test changes code identity.
set -euo pipefail
here=${0:A:h:h}
out="$here/build"; mkdir -p "$out"
stamp=${BUILD_STAMP:-1}
swiftc -O -swift-version 5 -target arm64-apple-macos26.0 -o "$out/probe" "$here/src/Probe.swift"
make_app() {
  local name=$1 id=$2 ent=${3:-}
  local app="$out/$name.app"
  rm -rf "$app"; mkdir -p "$app/Contents/MacOS"
  cp "$out/probe" "$app/Contents/MacOS/probe"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>$id</string>
  <key>CFBundleName</key><string>$name</string>
  <key>CFBundleExecutable</key><string>probe</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>$stamp</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>S5BuildStamp</key><string>$stamp</string>
  <key>CFBundleDocumentTypes</key><array><dict>
    <key>CFBundleTypeName</key><string>Folder</string>
    <key>CFBundleTypeRole</key><string>Viewer</string>
    <key>LSHandlerRank</key><string>None</string>
    <key>LSItemContentTypes</key><array><string>public.folder</string></array>
  </dict></array>
</dict></plist>
PLIST
  if [[ -n "$ent" ]]; then
    codesign --force --sign - --options runtime --timestamp=none --entitlements "$here/entitlements/$ent" "$app"
  else
    codesign --force --sign - --options runtime --timestamp=none "$app"
  fi
  codesign --verify --strict "$app"
  echo "$name $(codesign -dvvv "$app" 2>&1 | awk -F= '/^CDHash=/{print $2}')"
}
make_app S5Unsandboxed com.focuspilot.spike.s5.unsandboxed
make_app S5Sandboxed com.focuspilot.spike.s5.sandboxed Sandboxed.entitlements
make_app S5SandboxedNoBM com.focuspilot.spike.s5.sandboxed-nobm SandboxedNoBookmarkEntitlement.entitlements
# --migration: same bundle IDs with the sandbox setting swapped, to test whether a bookmark made
# by the unsandboxed app resolves after the app becomes sandboxed (and the reverse).
if [[ "${1:-}" == "--migration" ]]; then
  make_app S5UnsandboxedNowSandboxed com.focuspilot.spike.s5.unsandboxed Sandboxed.entitlements
  make_app S5SandboxedNowUnsandboxed com.focuspilot.spike.s5.sandboxed
fi
