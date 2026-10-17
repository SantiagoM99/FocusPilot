# Spike S4: Use Herdr from a normal Mac app (issue #4)

Dates: 2026-10-13 (read-only), 2026-10-16 (focus test). macOS 26 (Darwin 25.6.0), Swift 6.3 CLT (no Xcode), Herdr client/server 0.9.0, protocol 22.
This is throwaway code and is not meant to be merged. Probe app: `spike/HerdrProbe/` (`main.swift`, `Info.plist`, `build.sh`). The raw logs are `run1-inherited-env.log` (invalid launch, see below) `run2-clean-env.log` (the read-only run these notes rely on) and `run3-focus.log` (focus test).

## Method

- The probe is a minimal AppKit app (`NSApplication`, `.accessory` activation policy, `orderFrontRegardless`, so it never takes keyboard focus). It is compiled with `swiftc`, uses a hand-written Info.plist, is ad-hoc signed (`codesign -s -`), has no App Sandbox and no hardened runtime.
- It runs the work on a background thread, writes `~/Library/Logs/FocusPilotHerdrProbe/probe.log`, then quits.
- Every `herdr` child process gets an **explicit, minimal environment**: `HOME`, `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, `LANG`. It never gets any `HERDR_*` variable.
- **Launch caveat (important):** `open App.app` run from a terminal **passes that terminal's environment to the app**. Run 1 started with `HERDR_ENV`, `HERDR_PANE_ID`, `HERDR_SOCKET_PATH` and the shell PATH. Run 2 used `env -i /usr/bin/open -W -n HerdrProbe.app`, and the app got the launchd default environment: `PATH=/usr/bin:/bin:/usr/sbin:/sbin`, no `HERDR_*`, parent pid 1. A real Finder or Dock launch is expected to look like run 2, but that was not tested directly. Any later test of "not launched from a terminal" must use `env -i open` or Finder; plain `open` from inside a Herdr pane is not enough.
- Commands used: only `--version`, `status --json`, `session list --json`, `--session default status --json`, `agent list`, `agent get`, `agent read --source visible`, plus raw-socket `ping` and `agent.list`. No mutating command was run, by the app or by the shell.

## What works (run 2, clean environment)

| Check | Result |
| --- | --- |
| Bare `herdr` through the app's PATH (`/usr/bin/env herdr`) | **Fails:** `env: herdr: No such file or directory` (exit 127) |
| Login-shell lookup `zsh -lc 'command -v herdr'` | **Fails** (exit 1, 193 ms): `~/.local/bin` is added by the interactive rc, not the login profile. This method is fragile anyway. |
| Fixed candidate path `~/.local/bin/herdr` | Found. `--version` returns `herdr 0.9.0` in 6.6 ms |
| `herdr status --json` | Exit 0. Client 0.9.0/22, server running 0.9.0/22, `compatible:true`, socket `~/.config/herdr/herdr.sock` |
| `herdr session list --json` | Exit 0. One session: `default`, `running:true`, `socket_path` matches status |
| `herdr --session default status --json` | Same socket. It did **not** create `~/.config/herdr/sessions/` |
| Raw socket `ping` to the explicit socket path | `pong`, with version 0.9.0, protocol 22 and capabilities, in 0.5 ms |
| `herdr agent list` | Exit 0, 15 agents, about 9 KB of JSON, 8.9 ms |
| `herdr --session default agent list` | Exit 0, same 15 agents |
| `herdr agent get w3:pJ` | Exit 0, JSON with `pane_id` and `agent_status` |
| `herdr agent read w3:pJ --source visible` | Exit 0, **plain text** (not JSON), 4265 bytes, 36 lines. The content was not logged. |
| `herdr agent get w999:p999` | Exit 1. Stderr: `{"error":{"code":"agent_not_found","message":"agent target w999:p999 not found"},"id":"cli:agent:get"}` |

Each ID was logged together with its endpoint identity, for example `[local/default@~/.config/herdr/herdr.sock#pid51529] pane=wH:p3 name=s4-herdr`.

## Endpoint resolution recipe (no managed-pane variables)

Documented resolution order (Herdr v0.9.0 docs, `socket-api.mdx`, section "Socket paths": <https://raw.githubusercontent.com/herdrdev/herdr/v0.9.0/docs/next/website/src/content/docs/socket-api.mdx>):
1. explicit CLI `--session <name>`;
2. `HERDR_SOCKET_PATH`;
3. `HERDR_SESSION=<name>`;
4. the default session socket (`~/.config/herdr/herdr.sock`; named sessions use `~/.config/herdr/sessions/<name>/herdr.sock`).

Herdr injects `HERDR_SOCKET_PATH`, `HERDR_ENV`, `HERDR_WORKSPACE_ID`, `HERDR_TAB_ID` and `HERDR_PANE_ID` into managed panes. The app must not set any of these.

Recipe:
1. **Binary.** Use a user-configured path first. If there is none, check fixed candidates: `~/.local/bin/herdr`, `/opt/homebrew/bin/herdr`, `/usr/local/bin/herdr`, `~/.cargo/bin/herdr`. Check `isExecutableFile`, run `--version`, store the absolute path. Do not use PATH or a login shell.
2. **Run children with a scrubbed environment** that contains `HOME` and a minimal `PATH` and no `HERDR_*`. This matters even for GUI apps, because a terminal-started `open` leaks managed-pane variables (see run 1). If those leak, `HERDR_SOCKET_PATH` silently takes precedence over the default socket.
3. **Version gate.** Run `herdr status --json` and require `server.running`, `server.compatible`, and a `server.protocol` the app supports (22 today). Otherwise show "Herdr incompatible" and do nothing.
4. **Session.** Run `herdr session list --json` and let the user pick from `{name, default, running, socket_path}`. For the default session, pass no flag (step 4 of the order) or `--session default`; both give the same socket. For a named session, pass `--session <name>` on **every** command.
5. **Identity stored with every ID:** `(machine=local, session name, socket_path, server pid + process start time)`. Get the pid from `lsof -t <socket>`, keeping the process whose command is `herdr server`, and the start time from `ps -o lstart=`. The snapshot has no server instance ID; it only has `version`/`protocol`. If the pid or start time changes, treat cached pane IDs as stale.
6. **Optional raw socket.** Connect to the `socket_path` from step 4 and send newline-delimited JSON (`{"id":..,"method":"agent.list","params":{}}`). This works and is about 10× cheaper (see below). It ties FocusPilot to the socket protocol rather than the CLI, so pin and check `protocol` from `ping`.

All CLI output is treated as untrusted: parsed with `JSONSerialization` under a size cap, fields type-checked, nothing interpolated into commands, and `agent read` content kept out of logs.

## Polling cost (12 polls, one every 5 s, 60 s window each)

| Mode | Wall per call | Child CPU per call | App CPU over 60 s | Herdr server CPU over 60 s* |
| --- | --- | --- | --- | --- |
| Baseline, no polling | — | — | 3.1 ms | 830 ms |
| CLI `herdr agent list` | mean 11.5 ms, median 10.2, max 16.2 | mean 7.4 ms (89 ms per minute) | 16.6 ms | 860 ms |
| Raw socket `agent.list` | mean 1.1 ms, max 1.8 | — | 9.0 ms | 1100 ms |

*Server CPU covers all clients. Fifteen agents, some working, were active during the test, so the run-to-run noise is about ±300 ms per minute. Polling made no measurable difference to the server. Run 1 gave the same picture: CLI 11.7 ms per call, raw socket 1.1 ms. Conclusion: polling `agent list` every 5 s through the CLI costs about 0.15% of one core, which is negligible. The payload is about 9 KB per poll for 15 agents.

## Focus test (2026-10-16, owner-approved; log `spike/HerdrProbe/run3-focus.log`)

Setup:
- I created a scratch tab `wH:tC` (`tab create --no-focus`) and started a scratch agent `s4-scratch` there (`claude --model haiku`, pane `wH:pC`).
- I gave it one trivial prompt so it finished a turn unseen. Status was `done`, and `agent get`/`agent read` did not change that.
- The probe app was launched like a Login Item: `env -i /usr/bin/open -W -n HerdrProbe.app --args focus tab|agent`. The app environment had no `HERDR_*`, PATH was `/usr/bin:/bin:/usr/sbin:/sbin`, parent pid was 1, and children got a scrubbed environment.
- The app reads the owner's focus from `api snapshot` first. It may only target the tab or name of `s4-scratch`, which it gets from `agent get`. It holds focus for 3 s, then restores with `tab focus <owner tab>`.
- Two focus actions were used, out of the 3 allowed. Afterwards the scratch tab was closed with `tab close wH:tC` (it was the only thing created) and the owner's focus was confirmed unchanged.

| # | Command (from app) | Exit | Focus after | Scratch status before → after | Restore |
| --- | --- | --- | --- | --- | --- |
| 1 | `herdr tab focus wH:tC` | 0, 6.0 ms | ws=wH tab=wH:tC pane=wH:pC | `done` → `idle` | `tab focus w5:t1` → ws=w5 tab=w5:t1 pane=w5:p1, exact match |
| 2 | `herdr agent focus s4-scratch` | 0, 6.4 ms | ws=wH tab=wH:tC pane=wH:pC | `done` → `idle` | same, exact match |

Answers:
1. **Works from a non-pane GUI process: yes.** Both `tab focus <tab_id>` and `agent focus <name|pane_id>` succeed from a launchd-launched app with no managed-pane variables. Note that `pane focus` in 0.9.0 is **direction-only** (`--direction left|right|up|down`); it cannot target an explicit pane. So explicit navigation means `agent focus <target>` for agent panes, and `tab focus` / `workspace focus` otherwise. There is no "focus this exact non-agent pane" command.
2. **Which TUI client it affects:** focus is **server-level state**, not per-client. The server log records `method="tab.focus"`/`"agent.focus"` with `changes_ui=true`, followed by `workspace.focus` and then `tab.focus` events. `api snapshot` exposes one `focused_workspace_id/tab_id/pane_id`. Exactly one TUI client was attached (pid 6590, connected through `herdr-client.sock`), so that client is the one that moved. The response does not name a client. With **several** attached clients the docs say "each can view its own workspace and tab" (concepts.mdx). Which client follows an API focus in that case is **untested**. Visual confirmation from the owner of the two 3-second switches (2026-10-17 04:36:28Z and 04:36:42Z) is still pending.
3. **Marks `done` as seen: yes, for both commands.** `agent focus` turns `done` into `idle`, as the docs say ("explicit `pane focus` / `agent focus` commands mark the target seen"). The docs do not say that **`tab focus` also marks the agent in that tab as seen**, but it does. Reads (`agent get`, `agent read`) do not. Restoring focus to the owner's tab can therefore also clear a `done` state on the owner's agent. Here `w5:p1` was `working`/`idle`, so it was unaffected.

Implications for FocusPilot:
- Focus is a navigation action with side effects. It moves the single shared server focus and consumes `done` (the "unseen completion" signal).
- FocusPilot must read status **before** any focus. It must never focus as part of polling, and it must not offer "restore previous focus" casually, because the restore also consumes `done` on the restored target.
- Every focus must follow an explicit user action, with a revalidated target (session/socket/server pid + pane ID + agent name) right before acting.

## Not tested yet

- Focus with **several TUI clients attached**, and focus of a session or `--machine` target other than the local default.
- A real Login Item (`SMAppService.mainApp`) or Finder launch. Run 3 used `env -i open` as a stand-in, as in run 2.
- Finder or Dock double-click launch, and launch as a Login Item or `SMAppService`. Run 2 only approximates these with `env -i open`.
- **App Sandbox / hardened runtime / notarization.** The probe is unsandboxed. A sandboxed app very likely cannot run `~/.local/bin/herdr` or connect to `~/.config/herdr/herdr.sock` without entitlements or user-granted access. This is a distribution risk.
- Named sessions other than `default` (none exist), `--machine` remote targets, and the behavior when the server is stopped or restarted. Can `--session <missing>` with `agent list` spawn a server? Not tested, to avoid creating sessions.
- `agent read` with `--lines` or `recent`. Docs say history collection can scroll the viewport and then restore it. Only `visible` was used.
- `events.subscribe` as a replacement for polling.

## Risks

- `open` from a terminal leaks managed-pane variables. Defend by always scrubbing the child environment, as in step 2.
- Binary location is installation-specific (`~/.local/bin` here). Needs a user setting plus a validation UI.
- Pane IDs and names are per server and change on move or restart. Revalidate with the stored identity before acting.
- `agent read` returns raw terminal text that may contain secrets or prompt-injection content. Keep it local, size-capped, and never treat it as instructions.
- The raw socket protocol is cheaper but couples FocusPilot to protocol 22. The CLI is the documented stable layer. Recommendation: use the CLI first with a protocol gate, and keep the socket as an optimization.
- Client/server version skew: the docs index already shows 0.9.4 stable while 0.9.0 is installed, so the check in step 3 is required.
