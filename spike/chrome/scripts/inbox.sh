#!/bin/zsh
# One line per inbox record. Pass -f to follow.
inbox="$HOME/Library/Application Support/FocusPilotSpike/inbox.jsonl"
filter='[.receivedAt[11:23], .kind, (.hostPid|tostring), (.payload.type // .payload.reason // ""), (.payload.kind // ""), (.payload | del(.type, .kind, .userAgent) | tostring | .[0:220])] | join("  ")'
if [[ "${1:-}" == "-f" ]]; then tail -n 20 -f "$inbox" | jq -r --unbuffered "$filter"; else jq -r "$filter" "$inbox"; fi
