#!/bin/zsh
# Writes the policy snapshot the host pushes to the extension (stands in for the app).
#   set-policy.sh none                      no rules
#   set-policy.sh normal MIN [EXC_MIN]      block example.com for MIN minutes; optional exception
#                                           for example.com/allowed that expires after EXC_MIN
#   set-policy.sh strict MIN                same, but keeps blocking past the end until "end"
#   set-policy.sh end                       app confirms the current session ended
#   set-policy.sh always                    always-on block of example.org, no session
# Durations are minutes, or seconds with an "s" suffix (e.g. 90s).
# S3 overrides: FP_DOMAINS="youtube.com instagram.com" sets the session domains, and
# FP_EXCEPTIONS="||youtube.com |https://www.youtube.com/watch?v=ID" sets the exception URL filters
# (all expire after EXC). Defaults keep the S2 behaviour.
set -euo pipefail
data_dir="$HOME/Library/Application Support/FocusPilotSpike"
policy="$data_dir/policy.json"
mkdir -p "$data_dir"
in_min() { if [[ $1 == *s ]]; then date -u -v+"${1%s}"S +%Y-%m-%dT%H:%M:%SZ; else date -u -v+"$1"M +%Y-%m-%dT%H:%M:%SZ; fi; }
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
      exceptions=$(jq -n --arg e "$(in_min $3)" --arg f "${FP_EXCEPTIONS:-||example.com/allowed}" \
        '[$f | split(" ") | to_entries[] | {id: "exc-\(.key)", urlFilter: .value, expiresAt: $e}]')
    fi
    session=$(jq -n --arg id "session-$revision" --arg mode $cmd --arg start "$now" --arg end "$(in_min $2)" \
      --argjson exc "$exceptions" --arg domains "${FP_DOMAINS:-example.com}" \
      '{sessionId:$id, mode:$mode, startsAt:$start, endsAt:$end, ended:false, domains:($domains | split(" ")), exceptions:$exc}')
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
