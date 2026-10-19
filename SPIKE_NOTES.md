# Spike S1 notes: Safari keeps blocking without the app (plus S3, Safari half)

Issue: SantiagoM99/FocusPilot#1. Branch `spike/s1-safari`. Throwaway code; not for merge.
Status: T1–T5 run inside Safari on 2026-10-15/16 without owner clicks (see **Results**). The repeated permission prompts are explained and gone (see **Permission prompts**). Open: T6 sleep/wake (needs a human), T7–T9. S3 (issue #3, Safari half) was run on 2026-10-19 (see **S3**).

Environment: macOS 26.6.2 (25G83), Safari 26.6.2, Xcode 27.0 (27A266a). No signing identities on the Mac, so everything is signed ad hoc (`codesign -s -`, "Sign to Run Locally").

## What is built

All code is in `spike/safari/`. The generated Xcode project and build output live in `spike/safari/build/` (gitignored).

| Piece | Path | What it does |
|---|---|---|
| Web extension (MV3) | `extension/` | Background `background.js` (with `policy.js`; classic non-persistent background scripts) reconciles on every wake: worker load, `onStartup`, `onInstalled`, a 1-minute `sync` alarm, a `transition` alarm set to the next session end or exception expiry (kept, not recreated, while its target is unchanged: Safari fires an alarm no sooner than ~30 s after it is created), an app push, a content-script event and popup "Sync now". On each reconcile it also reloads every known tab on a newly blocked domain, so DNR blocks a page that was already open; tabs are learned from `tabs.onUpdated` because Safari hides their url from `tabs.query`. It records `tab-updated` (url, title, status) for the test domain only, which is how a DNR block is observed without looking at the screen: the tab title becomes Safari's "Failed to open page". Each reconcile does one `sendNativeMessage` round trip: it hands over unsent observations and gets the current snapshot. It keeps the higher revision and evaluates the policy against its own clock. It then writes `declarativeNetRequest` dynamic `block` rules (`||instagram.com/`, main and sub frames) and queues an `ack` (first time it applies a revision) or a `reconcile` observation. A second round trip delivers that observation. Observations stay in `browser.storage.local` until the handler confirms the append. |
| Content script | `extension/content.js` | Runs on `*.instagram.com` at `document_start`. It evaluates the stored policy with its own timer and blanks an already-loaded page, pausing media first, when the exception expires or a block starts. DNR cannot do that. It builds the blank page with DOM calls (no `innerHTML`). It reports `content-load` (with `blocked` and page visibility), `timer-armed`, `timer-fired`, `content-blanked` with the timer's overrun, `visibility` changes and any `content-blank-failed`/`content-error`. |
| Popup | toolbar icon | Shows stored policy, last evaluation, dynamic rules, last native result and unsent observation count. "Sync now" forces a reconcile. |
| Native handler (appex) | `src/Extension/SafariWebExtensionHandler.swift` | Sandboxed. Safari starts it for each native message, with or without the app. It probes both shared stores, uses the first writable one, appends each observation plus a `handler-request` line to `inbox.jsonl` under an exclusive `flock`, and returns `policy.json`. Each response and each `handler-request` line records the store probes. |
| Menu-bar app | `src/App/App.swift` | `LSUIElement` SwiftUI `MenuBarExtra` (shield icon) plus a window that does not open at launch. Menu: start normal session (2/5/15 min) or strict (2 min), grant a 1- or 2-minute exception, end session, clear, open window, open Safari extension settings, import inbox, quit. The window adds custom durations, store probes, the inbox tail, extension state (`SFSafariExtensionManager`) and login item register/unregister/status (`SMAppService.mainApp`). Publishing writes the snapshot atomically to every writable store. If Safari is already running it also pushes `policy-changed` with `SFSafariApplication.dispatchMessage`; it skips this otherwise, because that call launches Safari. The CLI publishing commands push the same way, so tests need no menu clicks. `kill -TERM` quits it cleanly (logs `sigterm`, `app-terminate`), so scripts never need an Apple Event. The app logs its own lifecycle (launch, window open/close, sleep, wake, publish, push, login item, terminate) to `app-events.jsonl`. On launch and wake it imports the inbox, deduplicated by `(installId, seq)`. |
| Shared store code | `src/Shared/SharedStore.swift` | Compiled into app, appex and probe. Default and only store: `~/Library/Application Support/FocusPilotSpikeS1/`, reached by the appex through a home-relative temporary exception. The App Group `group.com.focuspilot.spike.s1` is tried first only when the binary claims it (`build.sh --app-group`), because that claim causes the consent prompts below. Only a real write counts as access. |
| Probe | `src/Probe/` | A command-line stand-in for the appex with the same sandbox entitlements (used by `check.sh`). |
| Scripts | `scripts/` | `generate.sh` (project via `safari-web-extension-converter`, then sources/entitlements laid over it by `patch-pbxproj.py`), `build.sh [--app-group]`, `install.sh`, `check.sh`, `policy.sh` (app CLI: `--normal MIN`, `--strict MIN`, `--exception MIN`, `--end`, `--clear`, `--probe`, `--extension-state`, `--login-status`; publishing also pushes), `inbox.sh [-f]`, `events.sh`, `overruns.sh`, `roundtrip.sh`, `uninstall.sh [--keep-data]`. |

Policy snapshot (`policy.json`): `schemaVersion`, `revision` (epoch ms; the extension rejects lower ones), `writtenAt`, `writer`, `alwaysOn[]`, `session` {`sessionId`, `mode` normal|strict, `startsAt`, `endsAt`, `ended`, `domains` ["instagram.com"], `exceptions[]` {`id`, `domain`, `expiresAt`}}. All times are absolute UTC instants. Without the app, a normal session stops at `endsAt` and a strict one keeps blocking until the app writes `ended: true`. Exceptions expire in both modes.

Overrun is how late the extension applied a transition: `appliedAt − scheduledAt`, recorded in `overruns[]` on `reconcile`/`ack` observations (background, DNR rules) and in `overrunMs` on `content-blanked` (content script). `scripts/overruns.sh` lists them all.

All log timestamps are **UTC** (Bogotá is UTC−5).

### Findings from the build (no Safari needed)

1. **Xcode refuses to sign ad hoc with the App Group claim.** With `com.apple.security.application-groups = group.com.focuspilot.spike.s1`, `xcodebuild` fails on both targets with "requires a provisioning profile. Enable development signing and select a provisioning profile". With the entitlements files removed, the same build signs and compiles. Workaround: `build.sh` builds with `CODE_SIGNING_ALLOWED=NO` and signs with `codesign --sign - --options runtime --entitlements …`, appex first, then app. codesign accepts the claim. Whether the system honours it is the runtime question below.
2. **The ad-hoc App Group claim works for sandboxed code started outside Safari.** `check.sh` gives these results:
   - The unsandboxed app (`--probe`) creates and writes `~/Library/Group Containers/group.com.focuspilot.spike.s1/`. containermanagerd records the app as creator.
   - The sandboxed stand-in, signed ad hoc with the appex's exact entitlements and run under launchd (so it does not inherit the terminal's privacy permissions), writes it.
   - A control signed without the group claim is denied with `NSCocoaErrorDomain Code=513`.
   - The home-relative temporary exception works in both stand-ins.
   - No call blocked on a consent prompt. I cannot see the screen, so the owner should note any dialog (T2).
   - These stand-in results did not show the consent prompt. Inside Safari it did appear, repeatedly: see **Permission prompts**. The build now leaves the App Group out.
3. **Sandbox containers cannot be deleted from a terminal without Full Disk Access** ("Operation not permitted"). `uninstall.sh` lists any it leaves behind.
4. `safari-web-extension-converter` (Xcode 27) flags `background.type` and `background.persistent` as unsupported, although Apple's own macOS template uses `"type": "module"`. The spike uses two classic background scripts with neither key, so the converter reports no warning about them.

### Verified without Safari (2026-10-14)

- `scripts/build.sh` succeeds; `codesign --verify --deep --strict` passes. Signatures are ad hoc, `runtime` flag, no Team ID. App entitlements: application-groups only (not sandboxed, matching the Developer ID plan). Appex: app-sandbox, application-groups, home-relative temporary exception.
- `scripts/check.sh` passes: JS syntax, manifest parses, and `test-policy.mjs` covers:
  - normal end, strict past end, strict ended by the app;
  - exception expiry in both modes;
  - overrun detection across a long gap;
  - host matching.

  It also runs the store probes described above.
- `install.sh` registers the appex: `pluginkit -mA -i com.focuspilot.spike.s1.Extension` lists one copy, from `~/Applications`.
- App lifecycle from the command line:
  - Launch logs `app-launch` (`launchedAsLogInItem: false`, `loginItemStatus: notFound` before any registration, `parentPid: 1`) and `inbox-import`.
  - CLI `--normal 5`, `--exception 1`, `--end` and `--clear` write revisions to both stores.
  - An Apple Event quit logs `app-terminate` and the process exits.
- `inbox.sh`, `overruns.sh` and `roundtrip.sh` were checked against synthetic records. These were then deleted, and the stores were reset to empty.

This section describes the first build (App Group claimed by both). Safari results are in **Results** below.

## Permission prompts (finding, 2026-10-15)

Owner complaint: "every time the app activates it asks me for lots of permissions, constantly."

**What it was.** Only one kind of prompt, repeated: TCC service `kTCCServiceSystemPolicyAppData`, the macOS 15+ "“FocusPilotSpikeS1” would like to access data from other apps" dialog. `log show --last 2d` shows **21 prompts** for subject `com.focuspilot.spike.s1` and nothing else on the Mac. They ran from 15:14:33 to 15:24:30 UTC, about two a minute, alternating between two requesting processes:
- the Safari appex `com.focuspilot.spike.s1.Extension`, at :30 each minute (the 1-minute `sync` alarm → native handler → store probe);
- the menu-bar app `com.focuspilot.spike.s1`, at :34 each minute (its 5-second refresh timer probing the stores).

**Allow did not stick.** Every prompt was answered Allow: `AUTHREQ_RESULT authValue=2, authReason=2` (user consent). The next access a minute later prompted again. The prompts stopped when the owner quit the app (15:23:47 UTC). After that the appex's next request was the last one answered.

**Cause.** Both binaries claimed the iOS-style App Group `group.com.focuspilot.spike.s1` while signed ad hoc, with no Team ID and no provisioning profile. containermanagerd logs `REJECTED. Requestor's signature does not allow it to access a TCC-protected group container. Group containers identifiers should be prefixed by requestor's team ID`. sandboxd then falls back to asking TCC, which prompts. Apple documents this: on macOS 15+, accessing an app group container you are not authorised for results in a user prompt. A `group.` identifier needs the group in the app's provisioning profile; a `<TeamID>.<name>` identifier needs no profile, only a matching signing team. The first accesses on 2026-10-15 at 05:09–05:15 UTC worked without a prompt; prompting began when the owner returned to the Mac at 15:14 UTC.

**Checked and not involved** (no TCC request from these, no prompt in 2 days of logs):
- `SFSafariApplication.dispatchMessage`;
- `SFSafariExtensionManager.getStateOfSafariExtension`;
- `SMAppService.mainApp.status` (never registered);
- Automation/Apple Events (`kTCCServiceAppleEvents`: none);
- folder access (`~/Library/Application Support` is not TCC-protected);
- `open -a Safari <url>` (LaunchServices, not Apple Events).

**Fix in the spike.** Both binaries are now built without the App Group claim. The app and the appex share `~/Library/Application Support/FocusPilotSpikeS1/` through the appex's home-relative temporary exception. `SharedStore` touches the group container only when the binary claims it (`build.sh --app-group` reproduces the problem). Scripts no longer read the group container: the terminal reading it is also an access to another app's data. `install.sh`/`uninstall.sh` quit the app with SIGTERM instead of an AppleScript `quit`, so no Automation consent is ever needed. Result: **0 prompts** (`AUTHREQ_PROMPTING` count) from 23:48 UTC to 00:20 UTC across 24 policy publishes, 13 reinstalls and every test below.

**For the real product.** Decide the store with signing in mind:
- With a Developer ID team, use a macOS-style `<TeamID>.focuspilot` App Group. It needs no provisioning profile and should not prompt. Keep `group.*` only if FocusPilot ships with a provisioning profile that authorises it (Mac App Store, or Developer ID with a profile).
- Never ship a `group.*` claim without that authorisation. The prompt repeats and "Allow" does not stop it.
- The home-relative temporary exception works with no prompt and no team. It is acceptable outside the Mac App Store, so it is the fallback.

**Remaining unavoidable one-time prompts:** none came from FocusPilot in these tests. The Safari-side setup is a setting rather than a prompt, and was already done by the owner:
- Allow unsigned extensions (resets when Safari quits);
- enabling the extension;
- website access for instagram.com.

## Results (2026-10-15/16, run without owner clicks)

Method: the policy was changed only with `policy.sh` (the app binary in CLI mode, which now also pushes). Pages were loaded with `open -a Safari <url>`. Results were read from the inbox, `app-events.jsonl`, `roundtrip.sh` and `overruns.sh`. No UI was clicked and Safari was never quit, so the unsigned-extension setting stayed on. The extension stayed enabled through 13 rebuild+reinstall cycles with Safari open (`--extension-state` → `enabled`). Each reinstall fired `onInstalled:update`; relaunching the app once fired `onInstalled:install`. Times are UTC.

| Test | Result |
|---|---|
| T1 roundtrip, app running | **Pass.** 22 of 24 publishes were acknowledged through the app push (`app-push:policy-changed`) 0.1–0.2 s after publishing. 2 were dropped (00:05:55 and 00:05:58): `dispatchMessage` called back with no error, but the background page had been unloaded and nothing arrived. The next one was carried by `worker-start` 2.6 s later. One more was published mid-reinstall and carried by `worker-start` after 1.5 s. This matches the owner's 17.6 s `worker-start` ack. **Push is a latency hint, not a delivery guarantee**; the 1-minute alarm and other wakes are the backstop. |
| T2 shared store | **Pass via home-relative exception** (`transport: home-exception` on every call, no prompt). App Group: works but prompts repeatedly when unauthorised (see above). |
| End session | **Pass.** `--end` → ack 0.2 s, `blocked=` empty. |
| DNR on a fresh load | **Pass.** A new tab during a block got Safari's error page: `tab-updated title="Failed to open page"`, and no `content-load` ran (E1 23:58:37, C 23:52:57, Q1 00:19:21). |
| Already-open tab when a block starts | **Content script: not observed** in tab A (23:49:20). **Background reload: pass.** L1, loaded while unblocked, was reloaded by the background 0.14 s after the session ack and showed "Failed to open page" (00:09:21). |
| T4 exception grant and expiry | **Pass.**<br>• Grant → ack 0.2 s, and a tab opened during the exception loads (`content-load blocked=false`).<br>• DNR re-blocked at expiry with overrun 0.27 s (E, J), 0.27 s (M) and 0.22 s (N).<br>• In N2 the content script's timer fired 200 ms late while the page was hidden, blanked it (title "Blocked by FocusPilot spike"), and the background reload then showed "Failed to open page". |
| T5 normal end, app quit | **Pass.** App quit with SIGTERM right after the ack (00:15:54); DNR rules were removed at the end with overrun 0.26 s and no app running. |
| T5 strict past end, app quit | **Pass.**<br>• With the app quit, the 00:19:04 reconcile (59 s past the end) shows `strictPastEnd: true`, still blocking.<br>• A fresh load at 00:19:21 got "Failed to open page".<br>• `policy.sh --end`, the app binary in CLI mode with the menu-bar app still quit, unblocked it: ack after 0.17 s. |
| T3 app quit, extension keeps policy | **Pass** (covered by both T5 runs: `alarm:sync` reconciles and native handler calls continued with no app process). |
| T6 sleep/wake | Not run: needs a human. |

Findings from these runs:
1. **Safari delays an alarm until ~30 s after it is created.**
   - With the transition alarm recreated on every reconcile, transitions landed up to 30 s late: 29.6 s for an expiry 0.6 s away, and 10.8 s and 12.8 s when a sync reconcile had just recreated the alarm.
   - Keeping the existing alarm when its target is unchanged (within 1 s; Safari's `scheduledTime` is not bit-identical) brought every later transition to 0.22–0.27 s.
   - A transition scheduled less than 30 s ahead can still be up to 30 s late.
2. **The content script is unreliable as the only way to clear an open page.**
   - In five open tabs (A, E2, F1, G1, J1) no blank was observed.
   - In G1 and J1 the instrumented timer was armed (`timer-armed`, 56 s and 35 s) and never fired.
   - In N, `tab-removed` shows tab N1 was closed 2.5 s after it loaded, and some of the other tabs were probably closed the same way while the tests ran. So these misses do not prove that WebKit suspends timers.
   - Where the tab stayed open (N2), the timer fired 200 ms late even while the page was hidden.
   - Either way, the **background reload of known tabs** works whatever the page state, because the browser performs the navigation and DNR blocks it. The product should use it, with the content script as a fast path that can also stop media.
3. **`tabs.query` hides url/title of host-permitted tabs** after the extension reloads. `tabs.onUpdated` reports them. The extension has to track tab IDs itself.
4. **A tab opened in the same instant as a policy change can load under the previous rules.** At 00:06:00 the exception's ack and the tab load were 5 ms apart, and the tab got the old block.
5. The content script now builds the blank page with DOM calls, not `innerHTML`, so a Trusted Types CSP cannot make it throw. No `content-blank-failed` was reported after the change.

## S3: already-open pages and playing video, Safari half (2026-10-19)

Issue: SantiagoM99/FocusPilot#3. Same branch, app and extension (now v0.0.25). Run without owner clicks: the policy changed only through `policy.sh`, and pages loaded only with `open -a Safari <url>`. No AppleScript, no Safari restart, no settings changes. Times are UTC, from the extension's own observations (`observedAt`, `loadedAtMs`) and the app's `policy-published` events.

### What was added for S3

- **Domains and exceptions.** The session blocks `instagram.com` and `youtube.com`. `policy.sh --exception MIN [DOMAIN [URL]]` grants a domain exception or a URL-scoped one, an exact page (Decision 0003). `policy.js` gains `pageKey` (YouTube: video id only) and `isBlocked(result, href)`. A URL exception becomes a priority-2 DNR `allow` rule.
- **Blocked page.** `extension/blocked.html` reports `blocked-page-load` with its own timestamp, so arrival is measured, not assumed.
- **Probe tabs only.** The extension navigates or closes only tabs the spike opened, marked `#fp-probe=NAME` (or `?fp=…` for DNR-only checks). The mark persists in `sessionStorage` across the site's own navigations. Probe options: `autoplay=1` (muted `play()`), `spa=N` (after N s, `click()` an in-page link to another video). Probe media is force-muted on every `play`/`volumechange`.
- **Content script** (both domains). On a timer at the next transition, on a policy change, on visibility and on a URL change, it evaluates the policy against `location.href`. If blocked, it pauses and mutes media, then asks the background to `tabs.update` the tab to the blocked page. Blanking in place is a fallback only. URL changes are detected by `yt-navigate-finish`, `popstate` and a 250 ms `location.href` poll.
- **Background.** On every policy evaluation it redirects known probe tabs whose page is now blocked. It also sweeps `tabs.query({})`, which Safari answers with url for host-permitted tabs. `tabs.onUpdated` with a url change on a probe tab is checked too, as a second SPA path.
- **App CLI commands** for no-click runs: `--close-probe-tabs`, `--inspect-tabs` (url, title, status of spike tabs) and `--dnr-mode redirect|block`. They are carried as `command.json` on the next native round trip, nudged by the push.

### Results

| Acceptance criterion | Case | Result |
|---|---|---|
| Playing video stopped and replaced at exception expiry | YouTube, domain exception, muted video playing in the foreground tab (t2) | **Pass.** Expiry 18:34:03.476. The content timer fired +51 ms. The video was paused at +54 ms (`paused: false → true` at t=38.6 s). The blocked page loaded at **+239 ms**. The DNR alarm's overrun was 365 ms. |
| Same | YouTube and Instagram exceptions expiring while both tabs are **hidden** (another tab in front) (t4) | **Pass via the background only.** Neither page timer fired: WebKit suspended them in hidden tabs. The `transition` alarm ran at +267 ms and redirected both. Blocked page at **+397 ms** (YouTube) and **+278 ms** (Instagram). |
| Open tabs on blocked domains redirected at session start | 3 probe tabs (YouTube playing muted, YouTube hidden, Instagram) open, then `--normal 2` (t1) | **Pass.** Published 18:29:07.735. The ack redirected all three at +115–176 ms, and the blocked page loaded in all three at **+414–416 ms**. |
| Same | Tab opened **before the extension reloaded** (update), then a session starts (t5) | **Fail with tracked tab ids, pass with a `tabs.query` sweep.** After the reload Safari gave every tab a new id. The stored id failed ("Tab not found"), the old content script was orphaned, and the video kept playing under an active block. With the sweep, the blocked page loaded **+235 ms** after publish. |
| YouTube in-app (SPA) navigation caught | URL exception for one video, then the probe clicks a related video (t3b) | **Pass.** Click 18:35:10.723. The URL poll saw `watch?v=aqz…` → `watch?v=aIUI…` at +104 ms, media was paused at +107 ms, and the blocked page loaded at **+228 ms** after the click. Earlier, an in-app navigation that the probe did not start (t3a) was caught the same way: 110 ms from detection to the blocked page. `yt-navigate-finish` never came first. Background `tabs.onUpdated` did not report the YouTube SPA url change before the redirect; it did report Instagram's SPA url changes. |
| Fresh load during a block | New tab on a blocked domain | **DNR `block`: pass** ("Failed to open page" on both domains, no content script ran). **DNR `redirect` to `extensionPath`: fails open.** Safari accepted the rule with no error, but Instagram loaded normally in 2 of 2 runs, and the YouTube tab ended on a page the extension cannot read. Use `block`, and send open tabs to the blocked page with `tabs.update`. |

### Findings

1. **Autoplay works headless when muted, but YouTube can autoplay with sound by itself.**
   - Muted `play()` from the content script started playback without a gesture in a foreground tab (`autoplay-ok`).
   - A hidden tab did not load the video at all (`readyState 0`) until shown.
   - On the first run, YouTube replaced the probe's muted `play()` (`AbortError`) with its own **unmuted** autoplay; Safari's per-site setting allowed it. Two probe tabs played with sound from 18:21:40 to 18:24:57, until the extension could close them.
   - Probe media is now force-muted. The product must not rely on the browser's autoplay policy to keep video silent.
2. **Tab ids are not stable in Safari.**
   - Navigating a tab to the extension's blocked page fires `tabs.onRemoved` for the old id and reappears under a new id (process swap).
   - Reloading the extension renumbers every tab.
   - State keyed by tab id goes stale. The product should find tabs with `tabs.query` at each activation and expiry, not keep an id list. (S1 finding 3 said `tabs.query` hides urls; with "Always Allow" per-site access it now returns them for the granted hosts.)
3. **Page timers cannot be the mechanism.**
   - In a foreground tab the content script was fastest: pause in ~50 ms, blocked page in ~240 ms.
   - In hidden tabs no timer fired. The background `transition` alarm plus `tabs.update` did the job at +0.3–0.4 s.
   - The product needs both. The content script is the fast path and the only thing that stops media instantly. The background redirect is the guarantee.
4. **`storage.local.set` threw "Exceeded storage quota" with only 35 KB stored.**
   - This happened once, after ~2 days with the extension unloaded, and stopped after the `outbox` key was removed. The cause is unknown.
   - Because the error was inside the native-exchange `try`, it also dropped the native response: commands and policy updates were lost until it was patched.
   - Storage failures must never block enforcement.
5. **Extension reloads orphan content scripts.**
   - One open tab got a fresh content script after an update and another did not.
   - Blocked-page tabs (extension URLs) appeared to be closed by the reload.
6. **Why the extension disappeared between 10-17 and 10-19 (stale registration).**
   - On 10-17 the reinstall happened while "Allow unsigned extensions" was evidently off. Safari logged "Computing the code signing dictionary failed … does not have a code signature" and rejected that plug-in registration.
   - After the owner re-enabled the setting (10-19), Safari still did not list or load the extension. Relaunching the app did not change that, because Safari had already evaluated that registration.
   - A stale duplicate LaunchServices registration of the build-folder copy also existed.
   - Fix, no Safari restart: `lsregister -u` the build copy, then `lsregister -f` the installed app, then `pluginkit -a` the appex and `pluginkit -e use`. That gave the plug-in a new registration UUID, and Safari loaded it within the same second (`onInstalled:install`). Signatures were unchanged throughout (ad hoc, hardened runtime, same entitlements as the 10-15 build).
   - For later runs: install only to `~/Applications`, and unregister the build-folder copy.
7. **The owner used one probe tab.** One Instagram probe tab (`s1ig`) was taken over and browsed by the owner. It was released (`releasedProbes`), so the spike stopped tracking, muting or redirecting it, and it was left open. Its navigation is not recorded here.

### Permissions (Safari)

- `host_permissions` for `*://*.youtube.com/*` and `*://*.instagram.com/*`. The owner must grant website access per site ("Always Allow"). This is needed for the content script, for urls in `tabs.query`/`tabs.onUpdated`, and therefore for finding open tabs. A new host in an update is not granted automatically: youtube.com stayed `false` until the owner granted it.
- `declarativeNetRequest` (the `block` and `allow` rules), `alarms`, `storage`, `nativeMessaging`.
- No `tabs` permission was needed.
- `web_accessible_resources` is needed only for a DNR redirect or a page-initiated navigation to the blocked page. Neither is used in the final design.

### Unsupported or not tested (do not claim protection)

- DNR `redirect` to an extension page (fails open, above).
- Private windows, other Safari profiles, and tabs whose host the owner has not granted (no content script, no url, so no open-tab redirect; DNR `block` still applies to new loads).
- Picture-in-picture, background audio after the tab is hidden, and media in cross-origin iframes on other sites (for example YouTube embeds) were not tested.
- What a hidden tab's video does between being hidden and the expiry was not measured: its timers were suspended.
- Sleep/wake (S1 T6) is still pending.
- The owner's own tabs were never touched. Six were open on these domains at the last activation (`ownerTabsSkipped: 6`); the product would redirect them.

## Owner setup (do once, in order)

Run commands from the worktree root `.worktrees/s1-safari`. Keep two terminals open: `spike/safari/scripts/inbox.sh -f` (live inbox) and one for commands.

1. Open `~/Applications/FocusPilotSpikeS1.app` (Finder, or `open ~/Applications/FocusPilotSpikeS1.app`). No window opens: look for the **shield icon in the menu bar**. If Gatekeeper blocks it, right-click → Open, and record that.
2. Safari → Settings → Advanced → turn on **Show features for web developers**.
3. Safari → Settings → Developer → check **Allow unsigned extensions** (enter your password). Note the time.
4. Safari → Settings → Extensions → enable **FocusPilotSpikeS1 Extension** ("FocusPilot Spike S1"). If it is missing, quit and reopen the app once, then reopen Settings. Record what Safari asks for.
5. Pin the toolbar icon if it is not visible. Click it: the popup should show `lastNative.ok: true` and a `transport`. If `ok` is false, copy the popup text and stop.
6. Website access: open `https://www.instagram.com/`. When Safari asks about the extension's access to instagram.com, choose the "always allow on this website" option and record the exact labels. If no prompt appears, use the toolbar icon or Settings → Websites → Extensions. If anything looks wrong, open Develop → Web Extension Background Content → FocusPilot Spike S1 and copy the console errors.
7. With the current build no "… would like to access data from other apps" dialog should appear. If one does, note the time and which process it named; `log show --predicate 'process == "tccd" && eventMessage CONTAINS "AUTHREQ_PROMPTING"'` names it.

Useful at any time:
- `spike/safari/scripts/events.sh`: app lifecycle.
- `spike/safari/scripts/roundtrip.sh`: publish → ack latency per revision.
- `spike/safari/scripts/overruns.sh`: transition lateness.
- `spike/safari/scripts/policy.sh`: current snapshot.
- `pgrep -fl FocusPilotSpikeS1.app`: is the app running.

## Tests by acceptance criterion

Each test says what to do, what should happen, and what to record. Paste the outputs of the scripts named in **Record** into the conversation, or save them with `> /tmp/s1-Tn.txt`.

**T1. Roundtrip with the app running** (criterion: roundtrip works; mechanism documented)
1. With Safari open, use the menu: **Start normal session · 5 min**.
2. Expected: within about 1 s, if the app push works, or 60 s, through the sync alarm, the inbox shows an `ack` with the new `rev` and `blocked=instagram.com`. The menu's "Last ack" line updates within 5 s. Reload instagram.com: it is blocked (Safari's error page, not the blank spike page).
3. Use **Grant exception · 2 min**. Expected: an `ack` with the new revision and `blocked=` empty; instagram.com loads.
4. Use **End session**. Expected: an `ack`, and instagram.com loads.
5. **Record:** `roundtrip.sh` output (latency, transport, and whether `carried by` is `app-push:policy-changed` or `alarm:sync`); `events.sh | grep push` (any `error`); the popup's `lastNative.roundTripMs`.

**T2. Shared container access by the real appex** (criterion: App Group or alternative works, or the failure is documented)
Done; see **Permission prompts** and **Results**. The App Group worked but prompted; the home-relative store works with no prompt. Do not read `~/Library/Group Containers/group.com.focuspilot.spike.s1` from a terminal: that is itself an access to another app's group container and can prompt for the terminal app.

**T3. App quit; the extension keeps the last policy** (criterion: with the app quit, the extension still reads the last policy and blocks)
1. **Start normal session · 15 min**. Wait for the `ack`.
2. Menu → **Quit FocusPilot Spike S1**. Check `pgrep -fl FocusPilotSpikeS1.app` prints nothing and the shield icon is gone.
3. Open instagram.com in a new tab: blocked. Wait 3 min. Expected: new `reconcile` lines (`alarm:sync`) and `handler-request` lines keep arriving with no app running. This shows Safari starts the handler on its own.
4. While the app is still quit, run `spike/safari/scripts/policy.sh --end`. This is the same binary in CLI mode and opens no UI. Within 60 s instagram.com loads, which shows the handler reads a snapshot written with the UI quit.
5. **Record:** `inbox.sh` lines after the `app-terminate` time in `events.sh`.

**T4. Exception expiry applied by the extension alone** (criterion: exception expiry applied alone; overrun recorded)
1. Open the app. **Start normal session · 15 min**, then **Grant exception · 2 min**. Wait for the `ack` with `blocked=` empty.
2. Quit the app. Open instagram.com and play a reel or video with sound.
3. Expected at expiry: the playing page goes blank with "Blocked by FocusPilot spike S1 … Blanked in-page by the content script", and the sound stops. A new navigation to instagram.com is blocked by Safari.
4. **Record:** `overruns.sh` (`exception-expiry` from the background and `content-blanked` from the content script); whether audio continued.

**T5. Session end applied by the extension alone** (criterion: session end applied alone)
1. Open the app, **Start normal session · 2 min**, wait for the `ack`, then quit the app.
2. Confirm instagram.com is blocked. After the 2 minutes, reload: it loads.
3. Strict variant: open the app, **Start strict session · 2 min**, quit the app, and wait 4 min. instagram.com stays blocked and the popup shows `strictPastEnd: true`. Then reopen the app and choose **End session**: it loads.
4. **Record:** `overruns.sh` (`session-end`), and the strict result.

**T6. Sleep/wake overrun** (criterion: overrun after sleep/wake recorded)
1. Run `spike/safari/scripts/policy.sh --normal 6 && spike/safari/scripts/policy.sh --exception 3 && open -a Safari https://www.instagram.com/` (the menu-bar app need not run). Leave that tab in front.
2. Immediately put the Mac to sleep (Apple menu → Sleep) and leave it asleep **at least 10 min**, so both transitions pass during sleep.
3. Wake and unlock. Do not touch Safari for 2 min, then look at the tab.
4. Expected: the open tab blanks shortly after wake (content script), the rules come off at the session end, and instagram.com loads afterwards.
5. **Record:**
   - `pmset -g log | grep -E " (Sleep|Wake|DarkWake) " | tail -6` (actual sleep and wake times);
   - `overruns.sh`;
   - `inbox.sh` lines around the wake;
   - for both the exception expiry and the session end, the overrun minus the time asleep after the scheduled instant (how long after wake each was applied);
   - whether any `DarkWake` in the pmset log let an alarm run during sleep.
6. Repeat once with the app **running** during sleep: `events.sh` should show `will-sleep`, `did-wake` and `inbox-import(wake)`.

**T7. Safari restart** (criteria: overrun after Safari restart recorded; the unsigned setting)
1. Restart within a session: open the app, **Start normal session · 15 min**, wait for the `ack`, quit the app. Quit Safari (⌘Q). Reopen Safari and **do not re-enable anything yet**. Open instagram.com. **Record whether it is blocked** and whether the extension appears in Settings → Extensions. This shows whether a Safari relaunch leaves a gap until the owner re-enables unsigned extensions.
2. Re-enable **Allow unsigned extensions** and check whether the extension comes back enabled on its own. Reload instagram.com: blocked. Record the `onStartup` or `worker-start` reconcile in `inbox.sh`.
3. Restart after the end: open the app, **Start normal session · 2 min**, ack, quit the app, quit Safari. Wait 4 min, reopen Safari, and re-enable unsigned extensions. Record the `session-end` overrun from `overruns.sh` (expected ≈ time Safari was closed past the end, plus the time to re-enable) and whether instagram.com loads.

**T8. Login item, window close and quit are distinct states** (criterion: login item, window close and quit behave as distinct states)
1. Window close: menu → **Open window…**, then close it (⌘W or the red button). Expected: `pgrep -fl FocusPilotSpikeS1.app` still shows the PID and the shield icon remains. `events.sh` shows `window-open-request`, `window-open` and `window-close`, with no `app-terminate`. Publishing from the menu still works.
2. Login item: in the window, **Register**. Record the status shown (`enabled` or `requiresApproval`), any notification, and the entry in System Settings → General → Login Items & Extensions. If it is `requiresApproval`, approve it there.
3. Log out and log back in (or restart). Expected: the shield icon appears with no window. `events.sh` shows a new `app-launch`. Record its `launchedAsLogInItem`, `loginItemStatus` and `parentPid`, plus the time from login to launch.
4. Quit: menu → **Quit**. Expected: `app-terminate`, no PID, icon gone. The extension keeps enforcing (T3). The login item does not relaunch the app until the next login. Record whether it does.
5. Optional crash case: `pkill -9 -f FocusPilotSpikeS1.app/Contents/MacOS`. Expected: no `app-terminate` line, which is how a crash differs from a quit in the log.
6. In the window, **Unregister**, and record the status.

**T9. How often "Allow unsigned extensions" must be re-enabled** (criterion: note on how often during development)

Apple documents that the setting "resets when you quit Safari". Keep a log over the two days, one row per event:

| When (local) | Event | Setting still on? | Extension still enabled? | instagram.com blocked before re-enabling? |
|---|---|---|---|---|
| | Safari ⌘Q + relaunch | | | |
| | Mac sleep/wake (Safari left open) | | | |
| | Log out / log in | | | |
| | Mac restart | | | |
| | `build.sh && install.sh` with Safari open (new ad-hoc signature) | | | |
| | Safari update (if one happens) | | | |

Also note the count of re-enables per working day.

## Results to report back

For each test: pass/fail, the recorded numbers (T1 latency and transport, T4–T7 overruns, T6 sleep length), and pasted script output. Also include any dialogs and their exact text. Expected remaining unknowns: Safari's actual background unload timing, and whether alarms fire during DarkWake.

## Known limits of this spike

- Only `instagram.com` main and sub frames are blocked. Subresources from other hosts, private windows and other Safari profiles are not tested; `safariProfile` in the inbox records the profile UUID if Safari supplies one.
- The content script needs website access for instagram.com. Without it, only DNR and the background tab reload act.
- The background reload only knows tabs it saw load since the extension last started (its `tabHosts` list). A tab Safari restored without firing `tabs.onUpdated` is missed until it navigates.
- Blanked pages reload when they become allowed again. The original page state is lost.
- Policy revisions are wall-clock milliseconds, so changing the system clock backwards can make the extension reject new policies until it catches up. Clock changes are a known bypass anyway (Architecture).
- The app dedupe set lives in UserDefaults and grows without bound; fine for a spike.
- Debug builds are not used: the Debug-only `.debug.dylib` would need its own ad-hoc signature.

## Uninstall

Created outside the repo:
- `~/Applications/FocusPilotSpikeS1.app` (with its registered appex).
- `~/Library/Group Containers/group.com.focuspilot.spike.s1/`, created by the first build (App Group claimed). Delete it in Finder; touching it from a terminal can prompt.
- `~/Library/Application Support/FocusPilotSpikeS1/` (fallback store: policy, inbox, app events).
- Sandbox containers: `~/Library/Containers/com.focuspilot.spike.s1.Extension` (after Safari runs the handler), `…/com.focuspilot.spike.s1.probe` and `…/com.focuspilot.spike.s1.probe-nogroup` (from `check.sh`).
- `defaults` domain `com.focuspilot.spike.s1` (inbox dedupe set).
- The login item, if T8 registered it.
- In repo, gitignored: `spike/safari/build/`.

Steps:
1. Safari → Settings → Extensions → turn off "FocusPilotSpikeS1 Extension". Removing the app then removes the extension and its storage and rules.
2. `spike/safari/scripts/uninstall.sh` (or `--keep-data` to keep the logs). It quits the app, unregisters the login item through the app, unregisters the appex and app from pluginkit and LaunchServices, deletes the app, the data directories, the defaults domain and `build/`, and lists any protected container it could not delete. Drag those to the Trash in Finder.
3. Check: `pluginkit -mA -i com.focuspilot.spike.s1.Extension` prints nothing, and System Settings → General → Login Items & Extensions has no FocusPilotSpikeS1 entry.
4. Optionally turn off Settings → Developer → Allow unsigned extensions. It also resets on its own when Safari quits.

No Safari preferences or other apps' files were modified directly.

## Sources

- Running your Safari web extension (unsigned setting, resets when Safari quits): https://developer.apple.com/documentation/safariservices/running-your-safari-web-extension
- Messaging between the app and JavaScript in a Safari web extension (`sendNativeMessage`, `SFExtensionMessageKey`, `connectNative` + `dispatchMessage`; Safari ignores the application ID): https://developer.apple.com/documentation/safariservices/messaging-between-the-app-and-javascript-in-a-safari-web-extension
- `SFSafariApplication.dispatchMessage` (launches Safari if needed): https://developer.apple.com/documentation/safariservices/sfsafariapplication/dispatchmessage(withname:toextensionwithidentifier:userinfo:completionhandler:)
- App Groups entitlement (ID formats: `group.<name>`, and on macOS `<team identifier>.<name>` without registration): https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups
- `containerURL(forSecurityApplicationGroupIdentifier:)` (on macOS a URL is always returned, even for an invalid group): https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)
- App Groups: macOS vs iOS (Apple DTS, iOS-style IDs on macOS, when a profile is needed): https://developer.apple.com/forums/thread/721701
- Accessing app group containers (macOS 15 SIP for group containers; unauthorised access prompts; `group.` needs a provisioning profile; `<TeamID>.<name>` needs none): https://developer.apple.com/documentation/xcode/accessing-app-group-containers
- Persistent file-access prompt for ad-hoc signed apps using `group.` App Groups (Apple Developer Forums, matches what was observed): https://developer.apple.com/forums/thread/767604
- Accessing files from the macOS App Sandbox: https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- App Sandbox temporary exception entitlements (home-relative path format): https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html
- Temporary exceptions are fine outside the Mac App Store (Apple DTS): https://developer.apple.com/forums/thread/776609
- Communicating between an appex and its app (Apple DTS; app group container required for sockets/XPC names): https://developer.apple.com/forums/thread/778297
- Blocking content with your Safari web extension (`block` needs only `declarativeNetRequest`; redirect needs host access): https://developer.apple.com/documentation/safariservices/blocking-content-with-your-safari-web-extension
- Optimizing your web extension for Safari (non-persistent background, unloading, alarms): https://developer.apple.com/documentation/safariservices/optimizing-your-web-extension-for-safari
- Assessing browser compatibility: https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility
- `tabs.query` / `tabs.update` / `tabs.onUpdated` (MDN, WebExtensions API used by Safari): https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/tabs
- `declarativeNetRequest` rule actions (`block`, `allow`, `redirect.extensionPath`): https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/declarativeNetRequest/RuleAction
- WebKit autoplay policy (muted autoplay allowed without a gesture): https://webkit.org/blog/7734/auto-play-policy-changes-for-macos/
- Managing Safari web extension permissions (website access): https://developer.apple.com/documentation/safariservices/managing-safari-web-extension-permissions
- `SMAppService.mainApp`, `register()`, `.requiresApproval`: https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp, https://developer.apple.com/documentation/servicemanagement/smappservice/register(), https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval
- `SFSafariExtensionManager.getStateOfSafariExtension`: https://developer.apple.com/documentation/safariservices/sfsafariextensionmanager/getstateofsafariextension(withidentifier:completionhandler:)
- `SFSafariApplication.showPreferencesForExtension`: https://developer.apple.com/documentation/safariservices/sfsafariapplication/showpreferencesforextension(withidentifier:completionhandler:)
- Xcode 27 macOS Safari Extension template manifest (`background.scripts`, `type: module`): `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Xcode/Templates/Project Templates/macOS/Application Extension/Safari Extension.xctemplate/manifest.json`
