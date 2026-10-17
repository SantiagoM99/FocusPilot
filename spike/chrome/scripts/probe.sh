#!/bin/zsh
# Opens extension/probe.html in the running Chrome and prints its report from the inbox.
set -euo pipefail
label=${1:-probe}
inbox="$HOME/Library/Application Support/FocusPilotSpike/inbox.jsonl"
before=$(wc -l < "$inbox")
open -a "Google Chrome" "chrome-extension://nnebgihjjgaokjddhlkfmijogibdpfjj/probe.html?label=$label"
for _ in {1..30}; do
  sleep 1
  report=$(tail -n +$((before + 1)) "$inbox" | jq -c 'select(.payload.type == "probe")' | tail -1)
  [[ -n "$report" ]] && break
done
[[ -n "${report:-}" ]] || { echo "no probe report within 30 s" >&2; exit 1; }
echo "$report" | jq '.payload | {label, at, dynamicRuleIds, outcomes, frames: [.frames[] | {url, event, ms, timingEntry}], lastReconcile: (.lastReconcile | {trigger, at, revision, ruleIds, sessionActive, strictPastEnd, activeExceptions})}'
