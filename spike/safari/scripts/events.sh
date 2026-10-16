#!/bin/zsh
# The app's own lifecycle log (launch, window open/close, sleep/wake, publish, terminate).
for f in "$HOME/Library/Application Support/FocusPilotSpikeS1/app-events.jsonl"; do
  [[ -f "$f" ]] || continue
  echo "== $f"
  jq -r '[.at[11:23], (.pid|tostring), .kind, (.details | tostring | .[0:200])] | join("  ")' "$f"
done
