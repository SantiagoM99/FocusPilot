# Spike S5 notes: folder access and saved folder links

Issue: SantiagoM99/FocusPilot#5. Branch `spike/s5-folders`. Throwaway code; not for merge.
Status: **all automated scenarios pass in both the unsandboxed and the sandboxed app** (three full runs, 2026-10-14). Still needs a human: the NSOpenPanel grant (M1) and survival across a reboot (M2).

Environment: macOS 26.6.2 (25G83), Xcode 27.0 (27A266a), Apple silicon, APFS (case-insensitive). No signing identities, so every app is signed ad hoc (`codesign -s - --options runtime`).

## Answer

Yes, with the design below. A security-scoped bookmark of a user-chosen folder keeps working after relaunch, in the sandboxed and unsandboxed app alike. Rename and move resolve to the new location and return `isStale = true`; refreshing the bookmark clears that. Deletion is detected (resolution fails). The cases that need FocusPilot's own checks are a folder deleted and recreated at the same path, a folder moved to the Trash, a folder moved out of its root, and symlinks or `..` escaping a root. The bookmark resolves in all four without an error, so it cannot catch them alone. The checks below catch every one, and each costs well under 1 ms.

Proposed rules for the design documents (proposals, not decisions):

1. Always create bookmarks with `.withSecurityScope`, even while the app is unsandboxed. The same bookmark then keeps working if the app is later sandboxed under the same bundle ID (T17).
2. Store, next to each bookmark: the path at creation, the inode (`st_ino`) and the volume UUID. After resolving, mark the link **needs repair** when any of these hold: resolution failed (deleted: T4; unmounted volume: T15); the inode or volume differs (recreated at the same path: T5); the folder is now in the Trash (T6); or the folder is no longer inside its root (T3, T7). Apple says not to persist `fileIdentifierKey`, so treat the inode as a heuristic only, and let a mismatch ask the owner rather than act alone.
3. When `isStale` is true and none of the repair conditions hold, re-create the bookmark while access is held and save it (T2). Show the new path to the owner, because a move is a fact about their files.
4. Repair = show the old path and what was found, then offer: accept the new location, choose again (open panel), or unlink. Never pick a similarly named folder automatically.
5. Root containment: `realpath` the root, then `realpath` the deepest existing ancestor of the candidate path. Reject `.`/`..` in the part that does not exist yet, and reject a dangling symlink there. Compare path components case-folded on case-insensitive volumes and after Unicode normalization (T10). Do not use `URL.resolvingSymlinksInPath` or `standardizedFileURL`: neither resolves symlinks in a path that does not exist yet (T10 `symlink-escape`).
6. Create folders with `mkdirat` on a directory fd of the root, with a one-component name; `mkdirat` does not follow a final symlink. Confirm with `openat(O_NOFOLLOW)`. An existing name, symlinks included, is a collision, never an overwrite (T9).
7. Start access only around the work; balance every `start` with `stop` (Apple: leaked kernel resources cut off new sandbox extensions until relaunch).

## What is built

All code is in `spike/folders/`. Build output in `spike/folders/build/` (gitignored).

| Piece | What it does |
|---|---|
| `src/Probe.swift` | One Swift file (AppKit + Foundation), no Xcode project. Commands print one JSON line each: `create`, `resolve [--access] [--refresh] [--sub PATH] [--root ROOT]`, `read`, `mkchild ROOT_ENTRY NAME [--bookmark-as NAME]`, `contain ROOT PATH`, `bench`, `bench-entry`, `export`/`import` (bookmark data as base64), `trash`, `report`, `forget`, `pick NAME [--start DIR]` (NSOpenPanel). Launched with no command (by `open -a`), it bookmarks each folder it receives in `application(_:open:)` and logs to `open-log.jsonl`. Stores bookmark, options, path, inode and volume UUID in `Application Support/FocusPilotSpikeS5/<bundle id>/store.json` (inside the container when sandboxed). |
| `scripts/build.sh` | `swiftc`, then three ad hoc–signed bundles, each declaring `public.folder` as a viewer document type. `S5Unsandboxed.app` (`com.focuspilot.spike.s5.unsandboxed`): no sandbox. `S5Sandboxed.app` (`…s5.sandboxed`): `app-sandbox` + `files.user-selected.read-write` + `files.bookmarks.app-scope`. `S5SandboxedNoBM.app` (`…s5.sandboxed-nobm`): the same without `files.bookmarks.app-scope`. `BUILD_STAMP` changes `Info.plist`, so the cdhash changes and the bundle ID stays. `--migration` adds the two bundle IDs with the sandbox setting swapped. |
| `scripts/run-tests.sh` | Recreates fixtures in `~/FocusPilotSpikeS5`, runs T1–T15 for both apps (each probe call is a new process, so every resolve is a resolve after relaunch), then calls `run-resign-tests.sh` (T16–T17). Writes `build/results.jsonl`. About 1 minute. |
| `scripts/summary.sh` | One line per result. |
| `scripts/uninstall.sh` | Removes all of it (see Cleanup). |

The sandboxed app's first grant is automated with `open -a S5Sandboxed.app <folder>`. LaunchServices hands the folder to `application(_:open:)` with sandbox access, the same path as dropping a folder on the app's Dock icon. That makes everything after the grant testable without a human. The NSOpenPanel grant itself is M1.

## Results (automated)

U = unsandboxed, S = sandboxed. "Read" means `contentsOfDirectory` succeeded; every passing row also wrote and deleted a file. All runs after relaunch.

| Test | Scenario | U | S |
|---|---|---|---|
| T1 | Grant, relaunch, resolve, `startAccessing`, read/write | ✅ | ✅ (grant via `open -a`) |
| T1 | Same without `startAccessing` | reads (no sandbox) | **denied** (257): access comes from the bookmark |
| T2 | Folder renamed | resolves to new name, `isStale=true`; refreshed bookmark resolves with `isStale=false` | same |
| T3 | Moved within root / out of root | resolves, `isStale=true`; containment inside / **outside** | same |
| T4 | Deleted | resolution fails: Cocoa error 259 ("isn't in the correct format"), not 4 | same |
| T5 | Deleted and recreated at same path | **resolves to the new folder**, `isStale=true`, inode differs | same, and the sandbox **grants access to the new folder** |
| T6 | Moved to Trash (`FileManager.trashItem`) | resolves to `~/.Trash/…`, `isStale=true`, readable | same |
| T7 | Moved away, symlink to outside put at the old path | follows the real folder to its new place, not the symlink; containment outside | same |
| T8 | Inside a granted root: absolute symlink out, relative symlink out (`../../outside`), `root/../outside` | readable (no sandbox); containment check flags all as outside | **denied** by the sandbox; containment flags all |
| T8 | Symlink inside → inside; dangling symlink | readable, inside; dangling rejected | same |
| T8 | Folder outside, no bookmark | readable | denied (257) |
| T9 | `mkdirat` child under held root, bookmark it, relaunch, resolve child alone | ✅ | ✅: child bookmark works without starting the root's access |
| T9 | `mkdirat` onto existing symlink / existing dir / `../escape` | `exists-as-symlink` / `exists` / `invalid-name` | same |
| T10 | Containment: `..`, `missing/../../outside`, prefix `Root` vs `RootB`, `root` vs `Root`, NFC vs NFD `Café`, symlink in path, root given via symlink, `/tmp` vs `/private/tmp` | all correct; Foundation `resolvingSymlinksInPath` left `Root/out/new` unresolved | n/a (path logic) |
| T11 | Bookmark data moved between apps with different bundle IDs (U→S, S→U, S→S-NoBM) | fails, error 259 | fails, error 259 |
| T12 | Sandboxed **without** `files.bookmarks.app-scope` | n/a | ✅ creates and resolves security-scoped bookmarks after relaunch |
| T13 | Sandboxed app stores a **plain** bookmark (no `.withSecurityScope`) | n/a | resolves and reads after relaunch (Apple: implicit ephemeral scope, valid until reboot at the latest). **Reboot check is M2.** |
| T15 | Folder on a disk image, image detached, resolve with `.withoutMounting` | fails, error 4 | same; reattached: both resolve, not stale |
| T16 | Ad hoc rebuild: same bundle ID, new cdhash | ✅ old bookmarks resolve and grant access | ✅ (no container prompt seen) |
| T17 | Bookmark made unsandboxed, resolved by a sandboxed build with the same bundle ID (and reverse) | ✅ | ✅ |

`startAccessingSecurityScopedResource()` returned `true` in the unsandboxed app as well.

### Timings (this Mac, 500 iterations in one process, median / p95 ms)

| Operation | U | S |
|---|---|---|
| Create bookmark | 0.37 / 0.51 | 0.39 / 0.46 |
| Resolve bookmark (warm) | 0.29 / 0.33 | 0.29 / 0.32 |
| First resolve in a fresh process | 1.3 | 2.7 |
| `startAccessing` | 0.002 | 0.001 |
| Containment check (two `realpath`s) | 0.025 / 0.029 | 0.027 / 0.030 |
| Whole probe process, launch → resolve → exit (10 runs) | 63 median, 76 max | 71 median, 73 max |

The first two runs gave the same picture (cold process 68–106 ms, resolve 0.29–0.32 ms). Resolving every link before a launch costs nothing noticeable; the "two interactions" resume target in WORKSPACE_RULES is not at risk from this.

## Interpretation and limits

- **App-scoped bookmarks seem bound to the bundle ID, not to the cdhash** (T11, T16, T17), at least for ad hoc signatures. Apple documents only that an app-scoped bookmark is valid within the app that created it. The exact identity check is not documented, so this is an observation, not a guarantee.
- **The `files.bookmarks.app-scope` entitlement was not needed on macOS 26** (T12). Apple's current App Sandbox page no longer lists it; the archived reference still says it is required. Keep it in the sandboxed entitlements anyway: it is harmless, and the spike cannot prove that every system ignores it.
- **The sandbox already enforces root boundaries for symlinks and `..`** (T8), but only inside the sandbox. The unsandboxed app follows them, so the containment check is required either way.
- **Path-based sandbox grants follow the path:** after T5 the sandbox let the app into a different folder at the same path. Only the inode check noticed.
- Not measured: the limit on simultaneously held scoped resources, network volumes, iCloud Drive, and TCC-protected folders (Desktop, Documents, Downloads). FocusPilot's roots are under `~/Projects`, which TCC does not protect.

## Manual steps (owner)

Run from the worktree root. Build first if `spike/folders/build/` is missing: `spike/folders/scripts/build.sh && spike/folders/scripts/run-tests.sh`. `P_S=spike/folders/build/S5Sandboxed.app/Contents/MacOS/probe`.

**M1. NSOpenPanel grant in the sandboxed app** (criterion: a folder chosen in an open panel is still accessible after relaunch)
1. `mkdir -p ~/FocusPilotSpikeS5/manual/panel-folder`
2. `$P_S pick panel --start ~/FocusPilotSpikeS5/manual`. An open panel appears. Select `panel-folder` and click Open.
3. Record the printed line: `ok`, `readable`, `panelMs`. Expected: `"ok":true`, `"readable":true`.
4. `$P_S resolve panel --access`. Expected: `"readable":true`, `"writable":true`, `"isStale":false`.
5. `$P_S resolve panel`. Expected: `"readable":false` (proves the access comes from the bookmark).
6. Optional: `mv ~/FocusPilotSpikeS5/manual/panel-folder ~/FocusPilotSpikeS5/manual/panel-renamed`, then `$P_S resolve panel --access --refresh`. Expected: new path, `"isStale":true`, `"refreshed":true`.
7. Optional, unsandboxed panel: repeat steps 2–4 with `spike/folders/build/S5Unsandboxed.app/Contents/MacOS/probe`. If you choose a folder inside `~/Documents` there, record whether macOS shows a "would like to access files in your Documents folder" prompt.

**M2. Reboot** (do after M1, without re-running `run-tests.sh`)
1. Restart the Mac.
2. `$P_S resolve panel --access`, `$P_S resolve opened-sroot --access` and `$P_S resolve opened-plain --access`.
3. Record `readable` for each. Expected: the first two `true` (security-scoped). For `opened-plain`, Apple's docs predict `false`, because a plain bookmark's ephemeral scope ends at reboot. That would confirm rule 1.
4. Also record: `spike/folders/build/S5Unsandboxed.app/Contents/MacOS/probe resolve opened-sroot --access` (`readable` should be `true`).

Paste the lines from both steps into the issue comment.

## Developer ID distribution: what changes

- **The app does not have to be sandboxed.** Apple requires the App Sandbox only for the Mac App Store. Notarization requires the Hardened Runtime, which these probes already use. The current provisional plan (Developer ID, unsandboxed main app) works with plain bookmarks. Rule 1 (always security-scoped) keeps the sandbox an option.
- **Bookmarks across the switch from ad hoc to Developer ID: unknown.** T16/T17 suggest the binding is the bundle ID. A Developer ID build has a different designated requirement (team ID instead of cdhash). Bookmarks from spike builds do not matter, but if the owner uses an ad hoc FocusPilot build with real data before joining the program, the first Developer ID build must test resolution and fall back to the repair path. The repair path already covers this: resolve fails → "choose again".
- **Sandbox container ownership (macOS 14 and later)** is checked against the code signature, and Apple says a changed designated requirement can trigger a permission prompt. No prompt appeared for ad hoc rebuilds here (T16). A move to Developer ID is a requirement change, so a one-time prompt for the container is possible if the app is sandboxed by then.
- **TCC (Files and Folders) applies to every process**, sandboxed or not. It matters if the owner picks roots under Desktop, Documents, Downloads, iCloud Drive, or removable or network volumes. Whether an open-panel choice counts as consent for an unsandboxed app is not documented by Apple (M1 step 7 collects one observation).
- Nothing in this spike needs a provisioning profile or App Group, unlike S1.

## Proposed changes to the design documents (owner to apply on main)

- VALIDATION_PLAN, Folder access row: evidence obtained for bookmarks, relaunch, rename, move, delete, recreate, Trash, symlink and `..` escapes, unmounted volume, ad hoc rebuild and sandbox switch. Pending: open panel (M1) and reboot (M2). The fallback (explicit re-selection and repair) is still the repair path for every failure in rule 2.
- WORKSPACE_RULES, Provisioning requirements: add rules 1, 2, 5 and 6 above. Under "Existing environment", note that "revalidate before launch" means resolving and checking identity, Trash and containment, and that a folder recreated at the same path is a "needs repair" case.
- ARCHITECTURE: no change. Folder access does not constrain the distribution choice.

## Cleanup

Created on this Mac:
- `~/FocusPilotSpikeS5/` (fixtures, `vol.dmg`; `mnt` is detached after each run).
- `~/Library/Application Support/FocusPilotSpikeS5/` (unsandboxed stores).
- `~/Library/Containers/com.focuspilot.spike.s5.sandboxed`, `…s5.sandboxed-nobm`, `…s5.unsandboxed` (the last one from the T17 sandboxed build).
- LaunchServices registrations of the probe apps (from `open -a`).
- In repo, gitignored: `spike/folders/build/`.
- `run-tests.sh` deletes the T6 folders it moves to the Trash by exact path.

Steps:
1. `spike/folders/scripts/uninstall.sh`. It lists any container it cannot delete; terminal processes cannot delete sandbox containers without Full Disk Access (as in S1). Drag those to the Trash in Finder and empty it.
2. Check: `ls ~/FocusPilotSpikeS5 ~/Library/Containers | grep -i s5` prints nothing.

## Sources

- Accessing files from the macOS App Sandbox (open panel, Dock drag, recursive folder access, stale bookmark → recreate, document-relative bookmarks, macOS 14 container/designated requirement): https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox
- App Sandbox (required for the Mac App Store; current file-access entitlements list): https://developer.apple.com/documentation/security/app-sandbox
- `com.apple.security.files.user-selected.read-write`: https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.files.user-selected.read-write
- Archived Entitlement Key Reference (app-scope bookmark entitlement described as required): https://developer.apple.com/library/archive/documentation/Miscellaneous/Reference/EntitlementKeyReference/Chapters/EnablingAppSandbox.html
- `init(resolvingBookmarkData:options:relativeTo:bookmarkDataIsStale:)`: https://developer.apple.com/documentation/foundation/nsurl/init(resolvingbookmarkdata:options:relativeto:bookmarkdataisstale:)
- `startAccessingSecurityScopedResource()` (balance calls; leaked kernel resources): https://developer.apple.com/documentation/foundation/nsurl/startaccessingsecurityscopedresource()
- `stopAccessingSecurityScopedResource()`: https://developer.apple.com/documentation/foundation/nsurl/stopaccessingsecurityscopedresource()
- `.withoutImplicitSecurityScope` (plain bookmarks carry implicit ephemeral scope, valid until reboot): https://developer.apple.com/documentation/foundation/nsurl/bookmarkcreationoptions/withoutimplicitsecurityscope
- `.withoutImplicitStartAccessing`, `.withoutUI`, `.withoutMounting`: https://developer.apple.com/documentation/foundation/nsurl/bookmarkresolutionoptions/withoutimplicitstartaccessing, https://developer.apple.com/documentation/foundation/nsurl/bookmarkresolutionoptions/withoutui, https://developer.apple.com/documentation/foundation/nsurl/bookmarkresolutionoptions/withoutmounting
- App-scoped bookmarks valid only in the creating app (Apple DTS): https://developer.apple.com/forums/thread/66259
- Selecting a file grants only that file, not its folder (Apple DTS): https://developer.apple.com/forums/thread/124895
- `fileResourceIdentifierKey` (not persistent across restarts), `fileIdentifierKey` (don't persist): https://developer.apple.com/documentation/foundation/urlresourcekey/fileresourceidentifierkey, https://developer.apple.com/documentation/foundation/urlresourcekey/fileidentifierkey
- `resolvingSymlinksInPath` (strips `/private`, leaves unresolvable links), `standardized` (only `.`/`..`): https://developer.apple.com/documentation/foundation/nsurl/resolvingsymlinksinpath, https://developer.apple.com/documentation/foundation/nsurl/standardized
- `FileManager.trashItem` (name may change in the Trash): https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)
- Hardened Runtime (required for notarization): https://developer.apple.com/documentation/security/hardened-runtime
- TCC/MAC applies to all processes (Apple DTS): https://developer.apple.com/forums/thread/678819
- Controlling app access to files (protected locations): https://support.apple.com/guide/security/controlling-app-access-to-files-secddd1d86a6/web
- Not found in Apple documentation: sandbox behavior for symlinks leaving a granted folder (measured in T8), the exact identity an app-scoped bookmark binds to (measured in T11/T16/T17), and whether an open-panel choice grants TCC consent to an unsandboxed app (M1 step 7).
