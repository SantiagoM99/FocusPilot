#!/bin/zsh
# Removes everything install.sh created. Pass --keep-data to keep the inbox for analysis.
set -euo pipefail
here=${0:A:h:h}
rm -fv "$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.focuspilot.spike.json"
[[ "${1:-}" == "--keep-data" ]] || rm -rfv "$HOME/Library/Application Support/FocusPilotSpike"
rm -rfv "$here/build"
pkill -f focuspilot-spike-host || true
