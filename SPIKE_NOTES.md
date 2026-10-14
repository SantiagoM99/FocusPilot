# Spike S1 notes: Safari keeps blocking without the app

Issue: SantiagoM99/FocusPilot#1. Branch `spike/s1-safari`. Throwaway code; not for merge.
Status: built, ad-hoc signed and installed in `~/Applications`; **waiting for the owner to enable the extension in Safari**. Nothing has run inside Safari yet.

Environment: macOS 26.6.2 (25G83), Safari 26.6.2, Xcode 27.0 (27A266a). No signing identities on the Mac, so everything is signed ad hoc (`codesign -s -`, "Sign to Run Locally").

## What is built

All code is in `spike/safari/`. The generated Xcode project and build output live in `spike/safari/build/` (gitignored).

| Piece | Path | What it does |
|---|---|---|
| Web extension (MV3) | `extension/` | Background `background.js` (with `policy.js`; classic non-persistent background scripts) reconciles on every wake: worker load, `onStartup`, `onInstalled`, a 1-minute `sync` alarm, a `transition` alarm set to the next session end or exception expiry, an app push and popup "Sync now". Each reconcile does one `sendNativeMessage` round trip: it hands over unsent observations and gets the current snapshot. It keeps the higher revision and evaluates the policy against its own clock. It then writes `declarativeNetRequest` dynamic `block` rules (`||instagram.com/`, main and sub frames) and queues an `ack` (first time it applies a revision) or a `reconcile` observation. A second round trip delivers that observation. Observations stay in `browser.storage.local` until the handler confirms the append. |
| Content script | `extension/content.js` | Runs on `*.instagram.com` at `document_start`. It evaluates the stored policy with its own timer and blanks an already-loaded page, pausing media first, when the exception expires or a block starts. DNR cannot do that. It reports `content-blanked` with the timer's overrun. |
| Popup | toolbar icon | Shows stored policy, last evaluation, dynamic rules, last native result and unsent observation count. "Sync now" forces a reconcile. |
| Native handler (appex) | `src/Extension/SafariWebExtensionHandler.swift` | Sandboxed. Safari starts it for each native message, with or without the app. It probes both shared stores, uses the first writable one, appends each observation plus a `handler-request` line to `inbox.jsonl` under an exclusive `flock`, and returns `policy.json`. Each response and each `handler-request` line records both store probes, so App Group access is measured on every call. |
| Menu-bar app | `src/App/App.swift` | `LSUIElement` SwiftUI `MenuBarExtra` (shield icon) plus a window that does not open at launch. Menu: start normal session (2/5/15 min) or strict (2 min), grant a 1- or 2-minute exception, end session, clear, open window, open Safari extension settings, import inbox, quit. The window adds custom durations, store probes, the inbox tail, extension state (`SFSafariExtensionManager`) and login item register/unregister/status (`SMAppService.mainApp`). Publishing writes the snapshot atomically to every writable store. If Safari is already running it also pushes `policy-changed` with `SFSafariApplication.dispatchMessage`; it skips this otherwise, because that call launches Safari. The app logs its own lifecycle (launch, window open/close, sleep, wake, publish, push, login item, terminate) to `app-events.jsonl`. On launch and wake it imports the inbox, deduplicated by `(installId, seq)`. |
| Shared store code | `src/Shared/SharedStore.swift` | Compiled into app, appex and probe. Candidates in order: App Group `group.com.focuspilot.spike.s1` (`~/Library/Group Containers/…/FocusPilotSpikeS1/`), then `~/Library/Application Support/FocusPilotSpikeS1/` through a home-relative temporary exception. Only a real write counts as access. |
| Probe | `src/Probe/` | A command-line stand-in for the appex with the same sandbox entitlements (used by `check.sh`). |
| Scripts | `scripts/` | `generate.sh` (project via `safari-web-extension-converter`, then sources/entitlements laid over it by `patch-pbxproj.py`), `build.sh [--no-app-group]`, `install.sh`, `check.sh`, `policy.sh` (app CLI: `--normal MIN`, `--strict MIN`, `--exception MIN`, `--end`, `--clear`, `--probe`, `--login-status`), `inbox.sh [-f]`, `events.sh`, `overruns.sh`, `roundtrip.sh`, `uninstall.sh [--keep-data]`. |

Policy snapshot (`policy.json`): `schemaVersion`, `revision` (epoch ms; the extension rejects lower ones), `writtenAt`, `writer`, `alwaysOn[]`, `session` {`sessionId`, `mode` normal|strict, `startsAt`, `endsAt`, `ended`, `domains` ["instagram.com"], `exceptions[]` {`id`, `domain`, `expiresAt`}}. All times are absolute UTC instants. Without the app, a normal session stops at `endsAt` and a strict one keeps blocking until the app writes `ended: true`. Exceptions expire in both modes.

Overrun is how late the extension applied a transition: `appliedAt − scheduledAt`, recorded in `overruns[]` on `reconcile`/`ack` observations (background, DNR rules) and in `overrunMs` on `content-blanked` (content script). `scripts/overruns.sh` lists them all.

All log timestamps are **UTC** (Bogotá is UTC−5).

### Findings so far (no Safari needed)

1. **Xcode refuses to sign ad hoc with the App Group claim.** With `com.apple.security.application-groups = group.com.focuspilot.spike.s1`, `xcodebuild` fails on both targets with "requires a provisioning profile. Enable development signing and select a provisioning profile". With the entitlements files removed, the same build signs and compiles. Workaround: `build.sh` builds with `CODE_SIGNING_ALLOWED=NO` and signs with `codesign --sign - --options runtime --entitlements …`, appex first, then app. codesign accepts the claim. Whether the system honours it is the runtime question below.
2. **The ad-hoc App Group claim works for sandboxed code started outside Safari.** `check.sh` gives these results:
   - The unsandboxed app (`--probe`) creates and writes `~/Library/Group Containers/group.com.focuspilot.spike.s1/`. containermanagerd records the app as creator.
   - The sandboxed stand-in, signed ad hoc with the appex's exact entitlements and run under launchd (so it does not inherit the terminal's privacy permissions), writes it.
   - A control signed without the group claim is denied with `NSCocoaErrorDomain Code=513`.
   - The home-relative temporary exception works in both stand-ins.
   - No call blocked on a consent prompt. I cannot see the screen, so the owner should note any dialog (T2).
   - Apple documents that without a Team ID prefix, a provisioning profile or App Store/TestFlight distribution "the system prompts the user to approve its access" on macOS 15+. These results do not show that prompt. **The real appex launched by Safari is still unverified**; T2 settles it.
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

Not verified: everything inside Safari (handler launch, App Group access by the real appex, DNR, alarms, content script, push), the login item and sleep/wake.

## Owner setup (do once, in order)

Run commands from the worktree root `.worktrees/s1-safari`. Keep two terminals open: `spike/safari/scripts/inbox.sh -f` (live inbox) and one for commands.

1. Open `~/Applications/FocusPilotSpikeS1.app` (Finder, or `open ~/Applications/FocusPilotSpikeS1.app`). No window opens: look for the **shield icon in the menu bar**. If Gatekeeper blocks it, right-click → Open, and record that.
2. Safari → Settings → Advanced → turn on **Show features for web developers**.
3. Safari → Settings → Developer → check **Allow unsigned extensions** (enter your password). Note the time.
4. Safari → Settings → Extensions → enable **FocusPilotSpikeS1 Extension** ("FocusPilot Spike S1"). If it is missing, quit and reopen the app once, then reopen Settings. Record what Safari asks for.
5. Pin the toolbar icon if it is not visible. Click it: the popup should show `lastNative.ok: true` and a `transport`. If `ok` is false, copy the popup text and stop.
6. Website access: open `https://www.instagram.com/`. When Safari asks about the extension's access to instagram.com, choose the "always allow on this website" option and record the exact labels. If no prompt appears, use the toolbar icon or Settings → Websites → Extensions. If anything looks wrong, open Develop → Web Extension Background Content → FocusPilot Spike S1 and copy the console errors.
7. Note any dialog of the form "… would like to access data from other apps" during steps 1–6, and which process it named.

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
1. After T1, run: `jq -c 'select(.kind=="handler-request") | {receivedAt, transport, stores: .payload.stores}' ~/Library/Group\ Containers/group.com.focuspilot.spike.s1/FocusPilotSpikeS1/inbox.jsonl "$HOME/Library/Application Support/FocusPilotSpikeS1/inbox.jsonl" 2>/dev/null | tail -3`
2. Expected: `transport: "app-group"` and both stores `writable: true`. If `app-group` shows `writable: false`, the `error` field is the documented failure and traffic will have used `home-exception`.
3. Fallback end to end: `spike/safari/scripts/build.sh --no-app-group && spike/safari/scripts/install.sh`. Re-check the extension is enabled in Safari Settings and record whether the rebuild disabled it. Repeat T1 steps 1–2. Expected: `inbox.sh` shows `home-exception` as the transport. Then restore with `spike/safari/scripts/build.sh && spike/safari/scripts/install.sh`.
4. **Record:** the jq output, any consent dialog (Owner setup step 7), and the fallback result.

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
1. Open the app, set the window's session minutes to 6, **Start normal**, then set exception minutes to 3 and **Grant exception**. Quit the app. Open instagram.com (allowed by the exception) and leave the tab in front.
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
- The content script needs website access for instagram.com. Without it, only DNR acts, and an already-open page is not blanked when an exception expires.
- Blanked pages reload when they become allowed again. The original page state is lost.
- Policy revisions are wall-clock milliseconds, so changing the system clock backwards can make the extension reject new policies until it catches up. Clock changes are a known bypass anyway (Architecture).
- The app dedupe set lives in UserDefaults and grows without bound; fine for a spike.
- Debug builds are not used: the Debug-only `.debug.dylib` would need its own ad-hoc signature.

## Uninstall

Created outside the repo:
- `~/Applications/FocusPilotSpikeS1.app` (with its registered appex).
- `~/Library/Group Containers/group.com.focuspilot.spike.s1/` (policy, inbox, app events).
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
- App Groups entitlement (ID formats; macOS 15 container protection and prompt): https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.application-groups
- `containerURL(forSecurityApplicationGroupIdentifier:)` (on macOS a URL is always returned, even for an invalid group): https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)
- App Groups: macOS vs iOS (Apple DTS, iOS-style IDs on macOS, when a profile is needed): https://developer.apple.com/forums/thread/721701
- Accessing files from the macOS App Sandbox: https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- App Sandbox temporary exception entitlements (home-relative path format): https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/AppSandboxTemporaryExceptionEntitlements.html
- Temporary exceptions are fine outside the Mac App Store (Apple DTS): https://developer.apple.com/forums/thread/776609
- Communicating between an appex and its app (Apple DTS; app group container required for sockets/XPC names): https://developer.apple.com/forums/thread/778297
- Blocking content with your Safari web extension (`block` needs only `declarativeNetRequest`; redirect needs host access): https://developer.apple.com/documentation/safariservices/blocking-content-with-your-safari-web-extension
- Optimizing your web extension for Safari (non-persistent background, unloading, alarms): https://developer.apple.com/documentation/safariservices/optimizing-your-web-extension-for-safari
- Assessing browser compatibility: https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility
- Managing Safari web extension permissions (website access): https://developer.apple.com/documentation/safariservices/managing-safari-web-extension-permissions
- `SMAppService.mainApp`, `register()`, `.requiresApproval`: https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp, https://developer.apple.com/documentation/servicemanagement/smappservice/register(), https://developer.apple.com/documentation/servicemanagement/smappservice/status-swift.enum/requiresapproval
- `SFSafariExtensionManager.getStateOfSafariExtension`: https://developer.apple.com/documentation/safariservices/sfsafariextensionmanager/getstateofsafariextension(withidentifier:completionhandler:)
- `SFSafariApplication.showPreferencesForExtension`: https://developer.apple.com/documentation/safariservices/sfsafariapplication/showpreferencesforextension(withidentifier:completionhandler:)
- Xcode 27 macOS Safari Extension template manifest (`background.scripts`, `type: module`): `/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Xcode/Templates/Project Templates/macOS/Application Extension/Safari Extension.xctemplate/manifest.json`
