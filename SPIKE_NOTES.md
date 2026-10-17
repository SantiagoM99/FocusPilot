# Spike S2 notes: Chrome extension and native messaging host

Issue: SantiagoM99/FocusPilot#2. Branch `spike/s2-chrome`. Throwaway code; not for merge.
Status (2026-10-17): extension loaded by the owner; T2 and T5 pass; T1 passes except the second-extension case; T3 passes while awake; T4 is partial. Sleep, browser restart, second profile, incognito and the intruder extension wait for the owner (see Remaining owner steps).

## What is built

All code is in `spike/chrome/`.

| Piece | Path | What it does |
|---|---|---|
| Extension (MV3) | `extension/` | Service worker `sw.js` calls `connectNative("com.focuspilot.spike")`, reconnects in `onDisconnect` (backoff 1 s doubling to 60 s), applies the received policy as `declarativeNetRequest` dynamic rules, and on every wake (worker start, `onStartup`, `onInstalled`, alarm, policy message) reconciles the stored policy against its own clock. It sends `hello` (profile ID, extension ID, incognito access, worker instance), `ack` (revision, checksum, rule IDs) and sequenced `observation`s. Observations wait in `chrome.storage.local` until the host is reachable. The popup (toolbar icon) shows live status. |
| Fixed extension ID | `extension/manifest.json` `key` | `nnebgihjjgaokjddhlkfmijogibdpfjj`. Public key only (`extension-public-key.b64`); the private key was discarded because unpacked loading does not need it. |
| Intruder extension | `intruder-extension/` | No `key`, so it gets a random ID that is not in `allowed_origins`. It tries `connectNative` and shows the error. |
| Native host (Swift) | `host/main.swift` → `build/focuspilot-spike-host` | Length-prefixed stdio protocol (UInt32 native byte order + JSON, ≤1 MB outgoing). Exits with status 1 unless `argv[1]` is the allowed origin. Polls `policy.json` every second and pushes changed policies (with SHA-256 checksum). Appends every inbound message and its own lifecycle (`host-start`, `host-stop`, `rejected-origin`) to `inbox.jsonl`. Exits when stdin closes. |
| Scripts | `scripts/` | `build.sh`, `install.sh [HOST_PATH]`, `set-policy.sh`, `inbox.sh [-f]`, `drive-host.py` (tests the host without Chrome), `probe.sh LABEL` (opens `extension/probe.html`, see Results), `uninstall.sh [--keep-data]`. |

Policy shape (written by `set-policy.sh`, standing in for the app): `schemaVersion`, `revision` (epoch ms), `alwaysOn[]`, `session` {`sessionId`, `mode` normal|strict, `startsAt`, `endsAt`, `ended`, `domains`, `exceptions[]` {`urlFilter`, `expiresAt`}}. Test domains: `example.com` (session), `example.org` (always-on). The extension rejects lower revisions. Reconcile observations carry `sessionEndOverrunMs` and `exceptionExpiryOverrunMs`, which measure how late a rule came off.

The periodic safety alarm is 15 min. A shorter alarm would wake the worker and hide whether the open port alone keeps it alive.

### Verified without Chrome (2026-10-13)

- The host builds with `swiftc` (Swift 6.3.2, arm64, macOS 26).
- `drive-host.py` round trip with the allowed origin: hello → policy (with checksum) → ack → stdin close → `host-stop`, exit 0.
- A foreign origin (`chrome-extension://aaaa…/`) is refused: inbox `rejected-origin`, exit 1, no policy sent.
- Host manifest installed (see Uninstall). `sw.js` passes `node --check`. It has not run in Chrome yet.

## Results (2026-10-17, Chrome 155.0.8059.40, macOS 26, one profile)

The owner loaded the extension at 04:32 UTC. Claude ran the tests below from the terminal with no clicks. It used `set-policy.sh`, `open -a "Google Chrome"` on the probe page, `pkill`, and edits to the host manifest only. Chrome was never quit, and its settings were not touched. Raw evidence is in `~/Library/Application Support/FocusPilotSpike/inbox.jsonl`.

**How blocking was checked.** `scripts/probe.sh LABEL` opens `extension/probe.html` in a new tab. The page asks `declarativeNetRequest.testMatchOutcome` (unpacked extensions only) which rules match `example.com/`, `example.com/allowed`, `example.org/` and `example.net/`. It sends the answer to the host over its own native port and then closes its tab. Chrome served the new page from disk without an extension reload. A separate iframe-load timing check could not tell blocked loads from allowed ones (blocked 29–54 ms, allowed 54–158 ms), so it is not used as evidence. No real navigation to a blocked page was observed. That needs the owner (see Remaining owner steps).

| Criterion | Result | Evidence |
|---|---|---|
| T1 Host registered per user; other senders rejected | **Pass**, except the second-extension case | Loading worked through the user-level manifest alone. When this extension's ID was removed from `allowed_origins`, Chrome refused 3 reconnects with "Access to the specified native messaging host is forbidden." and never launched the host: no `host-start` between 04:55:24 and 04:55:39. After `install.sh` restored the manifest, the next backoff attempt connected; no Chrome restart was needed. The host's own `argv[1]` check refuses a foreign origin (exit 1). A second extension (the intruder) was not loaded. |
| T2 Open port keeps the worker alive; reconnect after host exit | **Pass** | With the port open and no traffic from 04:32:22 to 04:44:59 (12.6 min), the host PID was unchanged and the inbox had no new lines. The `hello` after the kill came from the same worker instance `678874a3` that started at 04:32:21. After `pkill`: `host-stop` at 04:44:59.097, new `host-start` at 04:45:00.256 (1.16 s), `hello reason=reconnect`, and the queued `native-disconnect` ("Native host has exited."). |
| T3 Alarms and startup reconciliation after sleep and restart | **Pass while awake, including with the host absent; sleep and browser restart not run** | Normal 3 min session with a 1 min exception: the exception came off 2 ms after expiry and the session rule 1 ms after its end (`alarm:boundary`, worker awake). Strict 1 min: still blocked past the end (`strictPastEnd: true`) until `set-policy.sh end`. Always-on blocked example.org with no session. **Host absent:** the exception expired while the host binary was missing and came off 1 ms late. Later, with no open port, the worker stopped. The session-end alarm (04:52:41) started a new worker (`aa1d3042`), which removed the session rule 195 ms after the end and then connected and flushed the queued observations. |
| T4 Distinct profile identity; incognito detectable | **Partial** | `hello` carries `profileId` (`4f5ce721…`), `extensionId` and `incognitoAllowed: false`. Not tested: a second profile, and the incognito toggle. **Bug:** on first install, `hello` reported `a179e56e…` but every observation reported `4f5ce721…`, because concurrent first-wake calls each created an ID. The fix is in `sw.js` (memoised promise) but is not loaded until the extension reloads. Later hellos report `4f5ce721…` consistently. |
| T5 Host path when moved or updated | **Pass** | **Moved, manifest stale:** "Specified native messaging host not found." (also the expected text for a missing manifest), retried with backoff up to 60 s. **Manifest repointed** to `~/Library/Application Support/FocusPilotSpike/bin/` without restarting Chrome: picked up on the next connect attempt (04:52:41). **Overwritten in place while running** with a different build (same inode): the running host (PID 55640) kept serving policy changes; after `pkill`, the next launch reported `build: "v2"`. This small binary was probably fully resident in memory. A real app bundle should still be replaced atomically (write elsewhere, then rename), because overwriting a running signed Mach-O in place can crash it with a code-signing error when it loads pages. That is platform behaviour, not measured here. **Correction:** after `mv`, use `pkill -f focuspilot-spike-host`, because the process's argv keeps the old name; the earlier step's `pkill -f moved-host` matched nothing. |

### Other findings

- **Observation lost (protocol bug).** Seq 15 (`native-disconnect` "Native host has exited." at 04:50:49) never reached the inbox. The reconnect attempt created a port to the missing host, `flush()` posted the outbox to that port without an error, and then cleared it. `postMessage` does not throw on a port that is about to fail. The outbox must be kept until the host acknowledges each seq. This supports the Architecture's sequence/acknowledgement design: the app must expect gaps and report them, never assume none.
- Duplicate policy pushes are harmless: on reconnect the host resends, and the extension answers with `duplicate: true` and does not reconcile again.
- Not tested: the stale-revision rejection path (`set-policy.sh` always writes the current time, and policy was driven only through it).
- Every probe used a separate native port, so each probe briefly ran a second host process with the same origin. Chrome allows several host instances for one extension.

## Remaining owner steps (one sitting, about 10 minutes, mostly waiting)

Run the commands from the worktree root in a terminal. Chrome stays open except in step 4.

1. **Incognito (T4).** `chrome://extensions` → **FocusPilot Spike S2** → **Details** → turn on **Allow in Incognito**. In the terminal: `spike/chrome/scripts/set-policy.sh normal 5`. Press ⇧⌘N, go to `example.com`, and note whether it is blocked ("ERR_BLOCKED_BY_CLIENT"). Close the incognito window and turn the toggle back off.
2. **Second profile (T4).** Profile icon (top right) → **Add** → **Continue without an account** → **Done**. In the new window: `chrome://extensions` → **Developer mode** on → **Load unpacked** → `spike/chrome/extension`. Then close that window.
3. **Other extension rejected (T1, optional; the mechanism is already shown).** In your main profile: `chrome://extensions` → **Load unpacked** → `spike/chrome/intruder-extension`. Click the puzzle icon → **FocusPilot Spike S2 Intruder**. The popup should show "Access to the specified native messaging host is forbidden." Then **Remove** it.
4. **Browser restart (T3).** `spike/chrome/scripts/set-policy.sh normal 1`, then quit Chrome with ⌘Q, wait 2 minutes, and reopen Chrome.
5. **Sleep (T3).** `spike/chrome/scripts/set-policy.sh normal 1`, then Apple menu → **Sleep**, wait 2 minutes, and wake the Mac.
6. Tell Claude "done". Claude reads the inbox: the incognito flag, the second `profileId`, the overruns after restart and after sleep.

## Original test plan

These were the planned tests; the Results table above records what happened.

### Setup (done 2026-10-17)


Run from the worktree root. Chrome 155 is installed.

1. In a terminal, run `spike/chrome/scripts/inbox.sh -f` and leave it running.
2. Chrome → `chrome://extensions` → turn on **Developer mode** → **Load unpacked** → choose `spike/chrome/extension`.
3. Check that the card shows ID `nnebgihjjgaokjddhlkfmijogibdpfjj`. If it does not, stop and report it, because the allowed origin would be wrong.
4. Click the extension's toolbar icon (pin it from the puzzle menu). The popup should show `"connected": true`, and the inbox should show `host-start` and `hello`.
5. Run tests T1–T5 below in any order. Copy the inbox output (`spike/chrome/scripts/inbox.sh > /tmp/s2-inbox.txt`) and any popup errors into the conversation.

### Tests by acceptance criterion

**T1. Host registered for the current user; other senders rejected**
- Registration: step 4 succeeds through the user-level manifest only.
- Other sender: **Load unpacked** `spike/chrome/intruder-extension` and click its icon. Expected `error`: "Access to the specified native messaging host is forbidden." The inbox gets no `host-start`, because Chrome refuses the connection before launching the host. Then remove the intruder.
- Host-side check, already passed: `python3 spike/chrome/scripts/drive-host.py spike/chrome/build/focuspilot-spike-host chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/` → exit 1.

**T2. Open port keeps the worker alive; reconnect after host exit**
- Keepalive: `spike/chrome/scripts/set-policy.sh none`, then leave Chrome untouched for 10 min or more. Pass: `pgrep -fl focuspilot-spike-host` shows the same PID as the last `host-start`, the inbox has no `host-stop`, and the popup's `swInstance` matches the one in the last `hello`. The port closes when the worker dies, so a host that lives on with no traffic means the worker stayed alive.
- Reconnect: `pkill -f focuspilot-spike-host`. Expected within about 1 s: `host-stop` (SIGTERM), a new `host-start`, then `hello` with `reason: "reconnect"`, followed by the queued `native-disconnect` observation.

**T3. Alarms and startup reconciliation after sleep and browser restart**
- Exception and expiry: `set-policy.sh normal 3 1`. `https://example.com/` is blocked and `https://example.com/allowed` loads. After 1 min, `/allowed` is blocked (`reconcile` with `exceptionExpiryOverrunMs`).
- Sleep: `set-policy.sh normal 3`, then Apple menu → Sleep for 5 min or more, then wake. Pass: example.com loads, and the inbox has a `reconcile` with `sessionEndOverrunMs`. Record the value.
- Browser restart after end: `set-policy.sh normal 2`, confirm the block, quit Chrome (⌘Q), wait 3 min, reopen. Pass: an `onStartup` or `worker-start` reconcile with `sessionEndOverrunMs`, and example.com loads.
- Browser restart within session: `set-policy.sh normal 10`, quit and reopen Chrome at once. Pass: example.com is still blocked.
- Strict: `set-policy.sh strict 1`, wait 2 min. Still blocked, and the popup shows `strictPastEnd: true`. Then `set-policy.sh end` → unblocked.
- Always-on: `set-policy.sh always` → example.org blocked, with no session and no end.

**T4. Distinct profile identity; incognito access detectable**
- Open a second Chrome profile, load the same unpacked extension there, and open its popup. Pass: a second concurrent host PID, and a `hello` with a different `profileId` and the same `extensionId`.
- Incognito: the popup shows `incognitoAllowed: false`. Enable **Allow in Incognito** in the extension's Details. Chrome reloads it, and the next `hello` shows `true`. Then, with `set-policy.sh normal 5`, open example.com in an incognito window and note whether it is blocked.

**T5. Host path when the app is moved or updated** (record the error strings)
- Moved, manifest stale: `mv spike/chrome/build/focuspilot-spike-host spike/chrome/build/moved-host && pkill -f focuspilot-spike-host`. Open the popup and record `connection.error`.
- Manifest repointed with no Chrome restart: `spike/chrome/scripts/install.sh "$HOME/Library/Application Support/FocusPilotSpike/bin/focuspilot-spike-host"`. Within 60 s or less (the backoff cap), the inbox should show `host-start` with the new `executable`.
- Update in place while connected: `spike/chrome/scripts/build.sh` overwrites the binary at the manifest path. Does the running PID survive? Then `pkill -f focuspilot-spike-host`; the next `host-start` should come from the new build.
- Restore: `spike/chrome/scripts/install.sh`.

## Known limits of this spike

- `profileId` is a random UUID created when the extension is installed in a profile. Removing and reinstalling the extension makes a new one. Chrome exposes no stable profile ID to extensions without the `identity` permission and a signed-in profile.
- DNR rules do not close or redirect already-open tabs or stop buffered media. The content-script candidate was built and measured for S3 (see the S3 section).
- `example.com` subresources and other resource types are not blocked (main_frame and sub_frame only).
- The host polls the policy file. The app/helper shared-location question (App Group etc.) belongs to the Safari spike.

## S3: Already-open pages and playing video (Chrome half of issue #3)

Run 2026-10-17 13:30–13:46 UTC on the same branch, extension, host and profile (Chrome 155.0.8059.40, macOS 26). Another agent covers Safari. No owner clicks were needed. Every blocking policy lasted 1–2 min or less and was reset with `set-policy.sh none` straight after each test; the final state is policy `none` with no DNR rules.

### What was added

| Piece | Path | What it does |
|---|---|---|
| Content script | `extension/cs.js` (+ shared `match.js`) | Injected at `document_start` on `*.youtube.com` and `*.instagram.com`. It holds the exception expiry in a page `setTimeout`, so it does not depend on the service worker. It detects same-document URL changes three ways (Navigation API `currententrychange`, YouTube's `yt-navigate-finish`, a 250 ms poll). On a block it pauses every `video`/`audio` element, then replaces the page with `blocked.html`. |
| Shared decision | `extension/match.js` | The same allow/block decision as the DNR rules (always-on, session, URL-scoped exceptions), evaluated for one URL. Used by both the worker and the content script. |
| Blocked page | `extension/blocked.html`, `blocked.js` | Web-accessible extension page. It reports when it was shown and why. |
| Worker changes | `extension/sw.js` | DNR now redirects top-level loads to `blocked.html` and blocks frames. On every reconcile it checks open tabs. Tabs with a live content script get the policy pushed and the content script acts first; the worker redirects any tab still on a blocked URL 1.5 s later. Tabs without a content script, or marked `passive`, are redirected at once. `tabs.onUpdated` catches SPA URL changes as a second path. |
| Control page | `extension/control.html?cmd=reload\|status\|spike-tabs\|close-spike-tabs` | Opened from the terminal with `open -a`. Extension pages are served from disk without a reload, and an extension page may call `chrome.runtime.reload()`. That loaded the new manifest and content script with **no click**. The unpacked reload granted the new host permissions with no prompt (checked with `chrome.permissions.getAll()`). |
| Policy script | `scripts/set-policy.sh` | `FP_DOMAINS`, `FP_EXCEPTIONS` (DNR-style `\|\|domain` or `\|prefix`), and durations in seconds (`25s`). |

**Owner safety.** The spike acts only on tabs it opened itself. A tab is marked by `?fpspike=flags` in the URL it was opened with, and the content script registers it at `document_start`, because YouTube strips the unknown parameter 1–1.6 s after load. Matching owner tabs are only counted, never touched; none were counted during the run. The test flags: `mute` mutes media on its first `play` event, `play` starts muted playback if the page did not autoplay, `spa` clicks an in-app link after 8 s, and `passive` turns off the content script's own blocking so the worker path can be measured.

### Results

Delays are from the triggering instant (exception expiry, host `policy-sent`, or the Navigation API `navigate` event) to `blocked.html` reporting itself shown. All runs had the worker awake, with its native port open.

| Criterion | Result | Measured |
|---|---|---|
| Playing YouTube video stopped and replaced when its exception expires | **Pass** | Content-script path (A): the timer fired 1 ms late; the video, playing at 21.6 s and muted, was paused at +3 ms; the blocked page showed at **+67 ms**. Worker-only path (A3, content script passive): `alarm:boundary` redirect, blocked page at **+68 ms**. The DNR exception rule came off at +0 to +1 ms. |
| Instagram (playing reel) | **Pass** | (E) A reel playing muted and looping: the timer fired 7 ms late; blocked page at **+51 ms**. |
| Blocked-domain tabs open at session start are redirected | **Pass** | (B, second run) YouTube in the foreground, playing at 11.0 s: the pushed policy made the content script pause at +31 ms and the blocked page showed at **+94 ms**. A background Instagram tab (passive, so the worker redirected it): **+64 ms**. In the first run the YouTube video was already paused by Chrome or YouTube once Instagram opened in front of it, so the playing case relies on the second run. |
| YouTube in-app (SPA) navigation caught | **Pass** | (C) A URL-scoped exception for one video; a click on another video changed the URL in the same document 12 ms later. Navigation API `currententrychange` caught it in ≤1 ms: video paused, blocked page at **+63 ms**. The worker's `tabs.onUpdated` saw it at +28 ms. (C2, worker only): blocked page at **+68 ms**. `yt-navigate-finish` and the poll never saw it first. |
| Instagram SPA navigation caught | **Pass** | (D) An exception for `/instagram/`; an in-app move to `/` was caught in 0 ms, blocked page at **+47 ms**. |
| Content script orphaned by an extension update or reload | **Degraded** | (F) After a reload, the old content script on the open tab could no longer reach the extension, and the video kept playing. The worker backup redirected at the 1.5 s grace: blocked page at **+1.57 s**. |

The SPA clicks were synthetic (`a.click()` from the content script), so YouTube's and Instagram's own routers did the navigation. Detection reads URL changes, not how they started, so a real click should behave the same. That is not separately verified.

### Required Chrome permissions

- `host_permissions` for each blocked domain (`*://*.youtube.com/*`, `*://*.instagram.com/*`). They are needed for: DNR `redirect` to the blocked page (plain `block` does not need them), reading `tab.url` and `changeInfo.url` for those sites, and injecting the content script. Install warning: "Read and change your data on …".
- `declarativeNetRequest`, `storage`, `alarms`, `nativeMessaging` (already present from S2).
- `web_accessible_resources`: `blocked.html` for the blocked domains, so pages and redirects can navigate to it.
- Not needed: `tabs` (host permissions expose the URLs that matter), `webNavigation`. Recommended: `scripting`, to re-inject the content script into open tabs from `onInstalled` (see the orphaned-script case).

### Unsupported, degraded or untested cases

- **After an extension update or reload:** open pages keep an orphaned content script that cannot act. Enforcement falls back to the worker; delay ≈ grace period (1.57 s measured), and media plays until then. Fix: re-inject with `scripting.executeScript` on `onInstalled`, or ping the content script before trusting it.
- **Chrome closes tabs showing the extension's own pages when the extension reloads or updates.** Observed: 11 blocked-page tabs closed at two reloads. An extension update therefore drops every blocked-page tab and its "from" context.
- **Exception expiry across sleep:** untested. Chrome timers on macOS may not count time spent asleep, so the content-script timer could fire late by the sleep duration. The worker alarm (wall clock) and the S2 reconcile-on-wake are the backstop. Recommended: re-evaluate in the content script on `visibilitychange`/`resume`/`focus`. Unverified platform assumption; test it with the S2 sleep owner step.
- **Hidden tabs:** Chrome throttles timers in background tabs. One-shot timers are expected to be at most about 1 s late, more after 5 min hidden. Only the worker path was measured on a background tab.
- **Embeds on other sites** (YouTube iframes, `youtube-nocookie.com`): not handled. The content script runs only on top frames of the listed hosts, and DNR blocks only new frame loads, so an already-playing embed continues.
- **The user withdraws site access** for the extension (Chrome's per-site access setting): the content script and redirect stop. The plain DNR block rule would still apply. Untested; the app should check `chrome.permissions.contains` and report degraded.
- **Incognito and other profiles:** as in S2. Incognito needs "Allow in Incognito", and each profile runs its own instance. Not tested for S3.
- **Picture-in-Picture, Media Session, casting:** not tested. Navigating the page should end PiP, but casting to another device continues outside Chrome.
- **Autoplay:** no gesture was needed. The YouTube watch page autoplayed **with sound** on this profile when opened in the foreground; muted playback through `play()` also worked; Instagram reels autoplayed muted.
- **Test interference:** two early YouTube test tabs that played with sound were closed by something outside the spike, most likely the owner, 5 s and 37 s after opening. With `mute`, later tabs were left alone.

### Remaining unknowns

The sleep and hidden-tab timer cases above; orphaned-script recovery through re-injection; real (trusted) user clicks for SPA navigation; incognito; and the case where the worker is asleep without a native port at expiry (the S2 measurement of 195 ms applies only to removing the DNR rule).

## Uninstall

Installed outside the repo (by `spike/chrome/scripts/install.sh`):
- `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.focuspilot.spike.json`. This is the only file added in that directory; the existing `com.anthropic.claude_code_browser_extension.json` was not touched.
- `~/Library/Application Support/FocusPilotSpike/` (`policy.json`, `inbox.jsonl`, and `bin/` if T5 ran).
- In repo, gitignored: `spike/chrome/build/`.

Steps:
1. `chrome://extensions` → **Remove** "FocusPilot Spike S2" (and "Intruder" if present) in every profile where it was loaded. Removing it deletes its dynamic rules and storage.
2. `spike/chrome/scripts/uninstall.sh`. Use `--keep-data` to keep the inbox. This removes both paths above, removes `build/`, and kills any running host.
3. Check: `ls ~/Library/Application\ Support/Google/Chrome/NativeMessagingHosts/` shows only the Claude Code manifest.

No Chrome profile files or preferences were modified directly.

## Sources

- Native messaging (manifest location, `allowed_origins`, origin argument, framing, size limits): https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
- Service worker lifecycle (30 s idle, native port keepalive): https://developer.chrome.com/docs/extensions/develop/concepts/service-workers/lifecycle
- `chrome.alarms`: https://developer.chrome.com/docs/extensions/reference/api/alarms
- `chrome.declarativeNetRequest` (dynamic rules persist across sessions): https://developer.chrome.com/docs/extensions/reference/api/declarativeNetRequest
- Manifest `key` and extension ID: https://developer.chrome.com/docs/extensions/reference/manifest/key
- Content scripts (`run_at`, isolated world, not injected into already-open tabs): https://developer.chrome.com/docs/extensions/develop/concepts/content-scripts
- `web_accessible_resources`: https://developer.chrome.com/docs/extensions/reference/manifest/web-accessible-resources
- `chrome.tabs` (URL visible with matching host permission): https://developer.chrome.com/docs/extensions/reference/api/tabs
- `chrome.runtime.reload`: https://developer.chrome.com/docs/extensions/reference/api/runtime#method-reload
- Navigation API: https://developer.mozilla.org/en-US/docs/Web/API/Navigation_API
- Autoplay policy: https://developer.chrome.com/blog/autoplay
- Timer throttling in hidden pages: https://developer.chrome.com/blog/timer-throttling-in-chrome-88
