#!/bin/zsh
# One line per probe result in build/results.jsonl (paths shortened to ~S5).
here=${0:A:h:h}
jq -r 'select(.cmd != "report" and .cmd != "import" and .cmd != "trash" and .cmd != null) |
  [ .test,
    (if .ok == false then "FAIL \(.error | if type == "object" then "\(.code) \(.message)" else . end)" elif .granted == true then "granted" else "ok" end),
    (.path // .log.path // .candidate // "" ),
    (if .isStale != null then "stale=\(.isStale) sameId=\(.sameIdentity) trash=\(.inTrash)" else "" end),
    (if .startAccessing != null then "start=\(.startAccessing)" else "" end),
    (if .readable != null then "read=\(.readable)" else "" end),
    (if .containment then "inRoot=\(.containment.inside)" elif .inside != null then "inside=\(.inside) \(.reason)" else "" end),
    (if .sub then "sub[\(.sub.subpath)] read=\(.sub.readable) inRoot=\(.sub.containment.inside)" else "" end),
    (if .cmd == "mkchild" and .ok == false then .error else "" end)
  ] | map(select(. != "")) | join(" | ")' "$here/build/results.jsonl" | sed "s#$HOME/FocusPilotSpikeS5#~S5#g"
