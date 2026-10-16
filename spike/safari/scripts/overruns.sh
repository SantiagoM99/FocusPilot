#!/bin/zsh
# Every measured overrun: how late a session end or exception expiry was applied by the
# background (DNR rules) or the content script (in-page blank).
for f in "$HOME/Library/Application Support/FocusPilotSpikeS1/inbox.jsonl"; do
  [[ -f "$f" ]] || continue
  jq -r 'select(.kind=="observation") | .payload as $p
    | ( ($p.overruns // [])[] | [$p.observedAt, "background", .kind, .scheduledAt, (.overrunMs|tostring) + " ms", $p.reason] ),
      ( select($p.kind=="page-event" and $p.overrunMs != null) | [$p.observedAt, "content-script", $p.event, "-", ($p.overrunMs|tostring) + " ms", $p.reason] )
    | join("  ")' "$f"
done
