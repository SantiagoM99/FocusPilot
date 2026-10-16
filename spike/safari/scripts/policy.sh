#!/bin/zsh
# Writes the policy snapshot from the command line through the app binary (same code as the
# menu), e.g. while the app's UI is quit:  policy.sh --normal 5 | --strict 2 | --exception 1 |
# --end | --clear | --probe.  Without arguments prints the current snapshot.
app="$HOME/Applications/FocusPilotSpikeS1.app/Contents/MacOS/FocusPilotSpikeS1"
if (( $# )); then exec "$app" "$@"; fi
for f in "$HOME/Library/Application Support/FocusPilotSpikeS1/policy.json"; do
  [[ -f "$f" ]] && { echo "== $f"; cat "$f"; echo; }
done
