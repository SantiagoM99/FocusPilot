#!/bin/zsh
# Writes the policy snapshot the host pushes to the extension (stands in for the app).
#   set-policy.sh none                      no rules
#   set-policy.sh normal MIN [EXC_MIN]      block example.com for MIN minutes; optional exception
#                                           for example.com/allowed that expires after EXC_MIN
#   set-policy.sh strict MIN                same, but keeps blocking past the end until "end"
#   set-policy.sh end                       app confirms the current session ended
#   set-policy.sh always                    always-on block of example.org, no session
set -euo pipefail
data_dir="$HOME/Library/Application Support/FocusPilotSpike"
policy="$data_dir/policy.json"
mkdir -p "$data_dir"
in_min() { date -u -v+"$1"M +%Y-%m-%dT%H:%M:%SZ; }
now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
revision=$(python3 -c 'import time; print(int(time.time()*1000))')
cmd=${1:-none}
always='[]'
session='null'
case $cmd in
  none) ;;
  always) always='[{"id":"always-example-org","domain":"example.org"}]' ;;
  normal|strict)
    exceptions='[]'
    if [[ -n "${3:-}" ]]; then
      exceptions=$(jq -n --arg e "$(in_min $3)" '[{"id":"exc-allowed","urlFilter":"||example.com/allowed","expiresAt":$e}]')
    fi
    session=$(jq -n --arg id "session-$revision" --arg mode $cmd --arg start "$now" --arg end "$(in_min $2)" \
      --argjson exc "$exceptions" \
      '{sessionId:$id, mode:$mode, startsAt:$start, endsAt:$end, ended:false, domains:["example.com"], exceptions:$exc}')
    ;;
  end)
    session=$(jq '.session | if . == null then null else .ended = true end' "$policy")
    always=$(jq '.alwaysOn' "$policy")
    ;;
  *) echo "unknown command $cmd" >&2; exit 2 ;;
esac
jq -n --argjson rev $revision --arg at "$now" --argjson always "$always" --argjson session "$session" \
  '{schemaVersion:1, revision:$rev, writtenAt:$at, alwaysOn:$always, session:$session}' > "$policy.tmp"
mv "$policy.tmp" "$policy"
cat "$policy"
