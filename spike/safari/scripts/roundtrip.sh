#!/bin/zsh
# For each policy revision the app published: when the extension first acknowledged it, through
# which transport, how late, and whether an app push or the periodic alarm carried it.
dir_g="$HOME/Library/Group Containers/group.com.focuspilot.spike.s1/FocusPilotSpikeS1"
dir_h="$HOME/Library/Application Support/FocusPilotSpikeS1"
python3 - "$dir_g" "$dir_h" <<'PY'
import json, sys, os
from datetime import datetime
def load(name):
    out = []
    for d in sys.argv[1:]:
        p = os.path.join(d, name)
        if os.path.exists(p):
            out += [json.loads(l) for l in open(p) if l.strip()]
    return out
ts = lambda s: datetime.fromisoformat(s.replace("Z", "+00:00"))
published = {e["details"]["revision"]: e for e in load("app-events.jsonl") if e["kind"] == "policy-published"}
acks = {}
for r in load("inbox.jsonl"):
    p = r.get("payload", {})
    if r["kind"] == "observation" and p.get("kind") == "ack" and p.get("revision") not in acks:
        acks[p["revision"]] = (r, p)
print(f"{'revision':>14}  {'published (UTC)':23}  {'acked by ext (UTC)':23}  {'latency':>9}  transport       carried by")
for rev, e in sorted(published.items()):
    if rev not in acks:
        print(f"{rev:>14}  {e['at'][:23]:23}  {'not acknowledged':23}")
        continue
    r, p = acks[rev]
    lat = (ts(p["observedAt"]) - ts(e["at"])).total_seconds()
    print(f"{rev:>14}  {e['at'][:23]:23}  {p['observedAt'][:23]:23}  {lat:8.1f}s  {r['transport']:14}  {p['reason']}")
PY
