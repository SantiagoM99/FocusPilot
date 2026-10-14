#!/bin/zsh
# Automated S5 scenarios for the unsandboxed (U) and sandboxed (S) probes. Fixtures live only
# under ~/FocusPilotSpikeS5 (recreated on each run). Every probe call runs in a fresh process, so
# each "resolve" is a resolution after relaunch. Results: build/results.jsonl, one JSON per line
# with a "test" label; scripts/summary.sh prints the table used in SPIKE_NOTES.md.
#
# The sandboxed probe gets its first grant through LaunchServices (`open -a App folder`, the same
# path as dropping a folder on the app or "Open With" in Finder), which delivers the folder to
# application(_:open:) with a sandbox extension. The NSOpenPanel grant needs a human: see
# SPIKE_NOTES.md, manual steps M1-M3.
set -uo pipefail
here=${0:A:h:h}
B="$here/build"
U="$B/S5Unsandboxed.app/Contents/MacOS/probe"
S="$B/S5Sandboxed.app/Contents/MacOS/probe"
N="$B/S5SandboxedNoBM.app/Contents/MacOS/probe"
R=~/FocusPilotSpikeS5
OUT="$B/results.jsonl"
[[ -x $U && -x $S && -x $N ]] || { echo "run scripts/build.sh first" >&2; exit 1; }

rm -rf "$R"; mkdir -p "$R"; : > "$OUT"
log() { local t=$1; shift; "$@" | jq -c --arg t "$t" '. + {test: $t}' | tee -a "$OUT"; }
note() { jq -nc --arg t "$1" --arg m "$2" '{test: $t, note: $m}' | tee -a "$OUT"; }
app_of() { case $1 in $U) echo "$B/S5Unsandboxed.app";; $S) echo "$B/S5Sandboxed.app";; $N) echo "$B/S5SandboxedNoBM.app";; esac; }
# grant PROBE PATH: entry name is opened-<basename> for every variant.
grant() {
  local p=$1 dir=$2 t=$3
  if [[ $p == $U ]]; then log "$t" $p create "opened-${dir:t}" "$dir"
  else
    open -W -a "$(app_of $p)" "$dir"
    log "$t" $p report >/dev/null
    $p report | jq -c --arg t "$t" --arg n "opened-${dir:t}" '{test: $t, cmd: "grant-via-open", variant, name: $n, granted: (.entries[$n] != null), log: (.openLog | split("\n") | map(select(length>0) | fromjson) | map(select(.name == $n)) | last)}' | tee -a "$OUT"
  fi
}

for V in U S; do
  P=${(P)V}; v=${V:l}
  base="$R/$v"; mkdir -p "$base/root/a" "$base/root/b" "$base/elsewhere" "$base/outside"
  echo secret > "$base/outside/secret.txt"

  # T1 relaunch + negative control
  mkdir -p "$base/root/a/t1-$v"
  grant $P "$base/root/a/t1-$v" "T1-grant-$V"
  log "T1-relaunch-access-$V" $P resolve "opened-t1-$v" --access
  log "T1-relaunch-noaccess-$V" $P resolve "opened-t1-$v"

  # T2 rename, stale refresh, second resolve
  mkdir -p "$base/root/a/t2-$v"
  grant $P "$base/root/a/t2-$v" "T2-grant-$V"
  mv "$base/root/a/t2-$v" "$base/root/a/t2-$v-renamed"
  log "T2-renamed-$V" $P resolve "opened-t2-$v" --access --refresh --root "$base/root"
  log "T2-after-refresh-$V" $P resolve "opened-t2-$v" --access

  # T3 move within root, then outside root
  mkdir -p "$base/root/a/t3-$v"
  grant $P "$base/root/a/t3-$v" "T3-grant-$V"
  mv "$base/root/a/t3-$v" "$base/root/b/t3-$v"
  log "T3-moved-in-root-$V" $P resolve "opened-t3-$v" --access --root "$base/root"
  mv "$base/root/b/t3-$v" "$base/elsewhere/t3-$v"
  log "T3-moved-out-of-root-$V" $P resolve "opened-t3-$v" --access --root "$base/root"

  # T4 deleted
  mkdir -p "$base/root/a/t4-$v"
  grant $P "$base/root/a/t4-$v" "T4-grant-$V"
  rm -rf "$base/root/a/t4-$v"
  log "T4-deleted-$V" $P resolve "opened-t4-$v" --access

  # T5 deleted and recreated at the same path (substitution risk)
  mkdir -p "$base/root/a/t5-$v"
  grant $P "$base/root/a/t5-$v" "T5-grant-$V"
  rm -rf "$base/root/a/t5-$v"; mkdir "$base/root/a/t5-$v"
  log "T5-recreated-$V" $P resolve "opened-t5-$v" --access

  # T6 moved to the Trash (FileManager.trashItem in the unsandboxed probe)
  mkdir -p "$base/root/a/t6-$v"
  grant $P "$base/root/a/t6-$v" "T6-grant-$V"
  log "T6-trash-op-$V" $U trash "$base/root/a/t6-$v"
  log "T6-trashed-$V" $P resolve "opened-t6-$v" --access --root "$base/root"

  # T7 original moved away and a symlink to outside put at the old path
  mkdir -p "$base/root/a/t7-$v"
  grant $P "$base/root/a/t7-$v" "T7-grant-$V"
  mv "$base/root/a/t7-$v" "$base/elsewhere/t7-$v"; ln -s "$base/outside" "$base/root/a/t7-$v"
  log "T7-replaced-by-symlink-$V" $P resolve "opened-t7-$v" --access --root "$base/root"

  # T8 symlinks inside a granted root
  mkdir -p "$base/sroot/proj"; ln -s "$base/outside" "$base/sroot/link-out"; ln -s proj "$base/sroot/link-in"
  ln -s ../../outside "$base/sroot/proj/rel-out"; ln -s ../nowhere "$base/sroot/proj/dangling"
  grant $P "$base/sroot" "T8-grant-$V"
  log "T8-sub-link-out-$V" $P resolve "opened-sroot" --access --sub link-out
  log "T8-sub-link-in-$V" $P resolve "opened-sroot" --access --sub link-in
  log "T8-sub-rel-out-$V" $P resolve "opened-sroot" --access --sub proj/rel-out
  log "T8-sub-dangling-$V" $P resolve "opened-sroot" --access --sub proj/dangling/new
  log "T8-sub-dotdot-$V" $P resolve "opened-sroot" --access --sub ../outside
  log "T8-direct-outside-$V" $P read "$base/outside"

  # T9 child folders created under a granted root, bookmarked, resolved alone after relaunch
  log "T9-mkchild-$V" $P mkchild "opened-sroot" "child" --bookmark-as "child-$v"
  log "T9-child-relaunch-$V" $P resolve "child-$v" --access
  log "T9-mkchild-onto-symlink-$V" $P mkchild "opened-sroot" "link-out"
  log "T9-mkchild-traversal-$V" $P mkchild "opened-sroot" "../escape"
  log "T9-mkchild-collision-$V" $P mkchild "opened-sroot" "proj"
  # a child created by the shell (not by the app) after the grant
  mkdir -p "$base/sroot/later"
  log "T9-later-child-bookmark-$V" $P mkchild "opened-sroot" "later2" --bookmark-as "later2-$v"
done

# T10 containment rules (pure path logic; the unsandboxed probe can stat everything)
c="$R/contain"; mkdir -p "$c/Root" "$c/RootB" "$c/outside" "$c/Root/Café"
ln -s "$c/Root" "$c/root-link"; ln -s "$c/outside" "$c/Root/out"
nfd=$(python3 -c 'import unicodedata;print(unicodedata.normalize("NFD","Café"))')
log T10-plain $U contain "$c/Root" "$c/Root/new"
log T10-dotdot $U contain "$c/Root" "$c/Root/../outside"
log T10-dotdot-missing-tail $U contain "$c/Root" "$c/Root/missing/../../outside"
log T10-prefix-trick $U contain "$c/Root" "$c/RootB"
log T10-case-variant $U contain "$c/Root" "$c/root/new"
log T10-nfd-vs-nfc $U contain "$c/Root/Café" "$c/Root/$nfd/x"
log T10-symlink-escape $U contain "$c/Root" "$c/Root/out/new"
log T10-root-via-symlink $U contain "$c/root-link" "$c/Root/new"
log T10-private-tmp $U contain /tmp /private/tmp/x

# T11 cross-app bookmark use
mkdir -p "$R/cross"
log T11-u-create $U create cross-u "$R/cross"
b64=$($U export cross-u | jq -r .b64)
log T11-s-import $S import from-u "$b64"
log T11-s-resolve-u-bookmark $S resolve from-u --access
open -W -a "$B/S5Sandboxed.app" "$R/cross"
b64s=$($S export opened-cross | jq -r .b64)
log T11-u-import $U import from-s "$b64s"
log T11-u-resolve-s-bookmark $U resolve from-s --access
log T11-nobm-import $N import from-s "$b64s"
log T11-nobm-resolve-s-bookmark $N resolve from-s --access

# T12 sandboxed without com.apple.security.files.bookmarks.app-scope
mkdir -p "$R/nobm"
grant $N "$R/nobm" T12-grant-NoBM
log T12-relaunch-NoBM $N resolve opened-nobm --access

# T13 sandboxed app storing a plain (non-security-scoped) bookmark
mkdir -p "$R/plain"
S5_PLAIN=1 open -W --env S5_PLAIN=1 -a "$B/S5Sandboxed.app" "$R/plain"
log T13-plain-relaunch-S $S resolve opened-plain --access

# T14 timings
log T14-bench-U $U bench "$R/u/root" 500
log T14-bench-S $S bench-entry opened-sroot 500
for V in U S; do
  P=${(P)V}; entry=$([[ $V == U ]] && echo opened-sroot || echo opened-sroot)
  for i in {1..10}; do
    t0=$(python3 -c 'import time;print(time.perf_counter_ns())')
    $P resolve "$entry" --access >/dev/null
    t1=$(python3 -c 'import time;print(time.perf_counter_ns())')
    jq -nc --arg t "T14-cold-process-$V" --argjson ms "$(( (t1 - t0) / 1000000.0 ))" '{test: $t, wallMsIncludingPythonTimer: $ms}' >> "$OUT"
  done
  $P resolve "$entry" --access | jq -c --arg t "T14-cold-inprocess-$V" '{test: $t, resolveMs, startMs}' | tee -a "$OUT"
done

# T15 disk image volume: unmounted at resolve time, then remounted
img="$R/vol.dmg"; mnt="$R/mnt"
hdiutil create -quiet -size 20m -fs APFS -volname S5Vol "$img" && hdiutil attach -quiet -nobrowse -mountpoint "$mnt" "$img"
mkdir -p "$mnt/volfolder"
log T15-u-create $U create vol-u "$mnt/volfolder"
open -W -a "$B/S5Sandboxed.app" "$mnt/volfolder"
hdiutil detach -quiet "$mnt"
log T15-unmounted-U $U resolve vol-u --access
log T15-unmounted-S $S resolve opened-volfolder --access
hdiutil attach -quiet -nobrowse -mountpoint "$mnt" "$img"
log T15-remounted-U $U resolve vol-u --access
log T15-remounted-S $S resolve opened-volfolder --access
hdiutil detach -quiet "$mnt"

# Empty the trashed T6 fixtures by their exact recorded paths (listing ~/.Trash needs Full Disk Access).
jq -r 'select(.cmd == "trash" and .ok) | .trashedTo' "$OUT" | while IFS= read -r p; do rm -rf -- "$p"; done
"$here/scripts/run-resign-tests.sh"
echo "results: $OUT"
