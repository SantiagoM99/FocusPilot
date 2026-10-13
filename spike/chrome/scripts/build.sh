#!/bin/zsh
# Builds the native host into spike/chrome/build/.
set -euo pipefail
here=${0:A:h:h}
mkdir -p "$here/build"
swiftc -O -o "$here/build/focuspilot-spike-host" "$here/host/main.swift"
echo "built $here/build/focuspilot-spike-host"
