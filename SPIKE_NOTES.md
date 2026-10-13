# Spike S2 notes: Chrome extension and native messaging host

Issue: SantiagoM99/FocusPilot#2. Branch `spike/s2-chrome`. Throwaway code; not for merge.
Status: built and installed; **waiting for the owner to load the unpacked extension**. No result in Chrome has been observed yet.

## What is built

All code is in `spike/chrome/`.

| Piece | Path | What it does |
|---|---|---|
| Extension (MV3) | `extension/` | Service worker `sw.js` calls `connectNative("com.focuspilot.spike")`, reconnects in `onDisconnect` (backoff 1 s doubling to 60 s), applies the received policy as `declarativeNetRequest` dynamic rules, and on every wake (worker start, `onStartup`, `onInstalled`, alarm, policy message) reconciles the stored policy against its own clock. It sends `hello` (profile ID, extension ID, incognito access, worker instance), `ack` (revision, checksum, rule IDs) and sequenced `observation`s. Observations wait in `chrome.storage.local` until the host is reachable. The popup (toolbar icon) shows live status. |
| Fixed extension ID | `extension/manifest.json` `key` | `nnebgihjjgaokjddhlkfmijogibdpfjj`. Public key only (`extension-public-key.b64`); the private key was discarded because unpacked loading does not need it. |
| Intruder extension | `intruder-extension/` | No `key`, so it gets a random ID that is not in `allowed_origins`. It tries `connectNative` and shows the error. |
| Native host (Swift) | `host/main.swift` → `build/focuspilot-spike-host` | Length-prefixed stdio protocol (UInt32 native byte order + JSON, ≤1 MB outgoing). Exits with status 1 unless `argv[1]` is the allowed origin. Polls `policy.json` every second and pushes changed policies (with SHA-256 checksum). Appends every inbound message and its own lifecycle (`host-start`, `host-stop`, `rejected-origin`) to `inbox.jsonl`. Exits when stdin closes. |
| Scripts | `scripts/` | `build.sh`, `install.sh [HOST_PATH]`, `set-policy.sh`, `inbox.sh [-f]`, `drive-host.py` (tests the host without Chrome), `uninstall.sh [--keep-data]`. |

Policy shape (written by `set-policy.sh`, standing in for the app): `schemaVersion`, `revision` (epoch ms), `alwaysOn[]`, `session` {`sessionId`, `mode` normal|strict, `startsAt`, `endsAt`, `ended`, `domains`, `exceptions[]` {`urlFilter`, `expiresAt`}}. Test domains: `example.com` (session), `example.org` (always-on). The extension rejects lower revisions. Reconcile observations carry `sessionEndOverrunMs` and `exceptionExpiryOverrunMs`, which measure how late a rule came off.

The periodic safety alarm is 15 min. A shorter alarm would wake the worker and hide whether the open port alone keeps it alive.

### Verified without Chrome (2026-10-13)

- The host builds with `swiftc` (Swift 6.3.2, arm64, macOS 26).
- `drive-host.py` round trip with the allowed origin: hello → policy (with checksum) → ack → stdin close → `host-stop`, exit 0.
- A foreign origin (`chrome-extension://aaaa…/`) is refused: inbox `rejected-origin`, exit 1, no policy sent.
- Host manifest installed (see Uninstall). `sw.js` passes `node --check`. It has not run in Chrome yet.

## Owner steps

Run from the worktree root. Chrome 155 is installed.

1. In a terminal, run `spike/chrome/scripts/inbox.sh -f` and leave it running.
2. Chrome → `chrome://extensions` → turn on **Developer mode** → **Load unpacked** → choose `spike/chrome/extension`.
3. Check that the card shows ID `nnebgihjjgaokjddhlkfmijogibdpfjj`. If it does not, stop and report it, because the allowed origin would be wrong.
4. Click the extension's toolbar icon (pin it from the puzzle menu). The popup should show `"connected": true`, and the inbox should show `host-start` and `hello`.
5. Run tests T1–T5 below in any order. Copy the inbox output (`spike/chrome/scripts/inbox.sh > /tmp/s2-inbox.txt`) and any popup errors into the conversation.

## Tests by acceptance criterion

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
- Moved, manifest stale: `mv spike/chrome/build/focuspilot-spike-host spike/chrome/build/moved-host && pkill -f moved-host`. Open the popup and record `connection.error`.
- Manifest repointed with no Chrome restart: `spike/chrome/scripts/install.sh "$HOME/Library/Application Support/FocusPilotSpike/bin/focuspilot-spike-host"`. Within 60 s or less (the backoff cap), the inbox should show `host-start` with the new `executable`.
- Update in place while connected: `spike/chrome/scripts/build.sh` overwrites the binary at the manifest path. Does the running PID survive? Then `pkill -f focuspilot-spike-host`; the next `host-start` should come from the new build.
- Restore: `spike/chrome/scripts/install.sh`.

## Known limits of this spike

- `profileId` is a random UUID created when the extension is installed in a profile. Removing and reinstalling the extension makes a new one. Chrome exposes no stable profile ID to extensions without the `identity` permission and a signed-in profile.
- DNR rules do not close or redirect already-open tabs or stop buffered media. The content-script expiry candidate from the Architecture is not built here.
- `example.com` subresources and other resource types are not blocked (main_frame and sub_frame only).
- The host polls the policy file. The app/helper shared-location question (App Group etc.) belongs to the Safari spike.

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
