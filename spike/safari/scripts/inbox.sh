#!/bin/zsh
# One line per inbox record. Pass -f to follow it. Reads only the home-relative store: a
# terminal that touches the App Group container gets a consent prompt of its own.
filter='[.receivedAt[11:23], .transport, (.handlerPid|tostring), .kind, (.payload.kind // .payload.reason // ""), "rev=" + (.payload.revision|tostring), "blocked=" + ((.payload.blockedDomains // [])|join(",")), ((.payload.overruns // []) | map(.kind + ":" + (.overrunMs|tostring) + "ms") | join(" ")), (.payload.reason // "")] | join("  ")'
home="$HOME/Library/Application Support/FocusPilotSpikeS1/inbox.jsonl"
files=(); for f in "$home"; do [[ -f "$f" ]] && files+="$f"; done
(( ${#files} )) || { echo "no inbox yet in either store"; exit 0; }
if [[ "${1:-}" == "-f" ]]; then tail -n 20 -f "${files[1]}" | jq -r --unbuffered "$filter"
else for f in $files; do echo "== $f"; jq -r "$filter" "$f"; done; fi
