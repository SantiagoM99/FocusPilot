#!/bin/zsh
# T16/T17, run after run-tests.sh (it calls this at the end). Rebuilds the probes and resolves
# the bookmarks stored by the previous build:
#   T16 BUILD_STAMP=2: same bundle IDs, new cdhash (what every ad-hoc rebuild does)
#   T17 --migration: bookmark from the unsandboxed app resolved by a sandboxed app with the same
#       bundle ID, and the reverse
# Leaves build/ at stamp 3 with the two migration apps added.
set -uo pipefail
here=${0:A:h:h}; B="$here/build"; OUT="$B/results.jsonl"
log() { local t=$1; shift; "$@" | jq -c --arg t "$t" '. + {test: $t}' | tee -a "$OUT"; }
BUILD_STAMP=2 "$here/scripts/build.sh" | tee -a "$B/run.log"
for pair in "S5Sandboxed opened-sroot" "S5Sandboxed child-s" "S5SandboxedNoBM opened-nobm" "S5Unsandboxed opened-sroot" "S5Unsandboxed child-u"; do
  set -- ${=pair}
  log "T16-rebuilt-$1-$2" "$B/$1.app/Contents/MacOS/probe" resolve "$2" --access
done
BUILD_STAMP=3 "$here/scripts/build.sh" --migration | tee -a "$B/run.log"
MU="$B/S5UnsandboxedNowSandboxed.app/Contents/MacOS/probe"; MS="$B/S5SandboxedNowUnsandboxed.app/Contents/MacOS/probe"
$MU import mig "$("$B/S5Unsandboxed.app/Contents/MacOS/probe" export opened-sroot | jq -r .b64)" >/dev/null
$MS import mig "$("$B/S5Sandboxed.app/Contents/MacOS/probe" export opened-sroot | jq -r .b64)" >/dev/null
log T17-unsandboxed-bookmark-in-sandboxed-same-id "$MU" resolve mig --access
log T17-sandboxed-bookmark-in-unsandboxed-same-id "$MS" resolve mig --access
