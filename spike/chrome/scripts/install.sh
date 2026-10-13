#!/bin/zsh
# Installs the spike native host for the current user only.
# Writes exactly two things outside the repo (both listed in SPIKE_NOTES.md):
#   ~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.focuspilot.spike.json
#   ~/Library/Application Support/FocusPilotSpike/   (policy.json, inbox.jsonl)
set -euo pipefail
here=${0:A:h:h}
host_path=${1:-$here/build/focuspilot-spike-host}
"$here/scripts/build.sh"
if [[ "$host_path" != "$here/build/focuspilot-spike-host" ]]; then
  mkdir -p "${host_path:h}"
  cp "$here/build/focuspilot-spike-host" "$host_path"
fi
manifest_dir="$HOME/Library/Application Support/Google/Chrome/NativeMessagingHosts"
mkdir -p "$manifest_dir"
cat > "$manifest_dir/com.focuspilot.spike.json" <<JSON
{
  "name": "com.focuspilot.spike",
  "description": "FocusPilot spike S2 native host (throwaway)",
  "path": "$host_path",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://nnebgihjjgaokjddhlkfmijogibdpfjj/"]
}
JSON
data_dir="$HOME/Library/Application Support/FocusPilotSpike"
mkdir -p "$data_dir"
[[ -f "$data_dir/policy.json" ]] || "$here/scripts/set-policy.sh" none
echo "installed manifest: $manifest_dir/com.focuspilot.spike.json -> $host_path"
