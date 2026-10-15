# Building and testing FocusPilot

Requires macOS 26 and Xcode 27 (selected with `xcode-select`). No Apple Developer membership is needed.

## Run the tests

```sh
swift test
```

Tests use Swift Testing and cover `FocusPilotCore`, so they need no app host or signing.

## Build and run the app

```sh
./scripts/build-app.sh
open build/FocusPilot.app
```

The script builds a release executable, wraps it in `build/FocusPilot.app` with `Packaging/Info.plist`, and signs it ad hoc. The bundle runs only on the Mac that built it.

Before turning on "Open at Login", copy the app somewhere stable and launch that copy:

```sh
ditto build/FocusPilot.app ~/Applications/FocusPilot.app   # or /Applications
open ~/Applications/FocusPilot.app
```

The login item points at one specific app on disk. Every ad hoc rebuild changes the signature, and a worktree's `build/` folder goes away when the worktree is removed, so a login item registered from `build/` can stop working.

Prefer the bundle over `swift run FocusPilot`: the bare executable has no Info.plist, so `LSUIElement` and login-item registration do not apply to it.

## Layout

| Path | Contents |
|---|---|
| `Sources/FocusPilotCore` | Testable logic: storage, coordinator, login item |
| `Sources/FocusPilot` | The SwiftUI app: menu bar item and planning window |
| `Tests/FocusPilotCoreTests` | Swift Testing suites for `FocusPilotCore` |
| `Packaging/Info.plist` | Bundle metadata, including `LSUIElement` |

## Data

The app stores two SQLite files in `~/Library/Application Support/FocusPilot`:

- `FocusPilot.sqlite`: owner data (tasks and, later, deadlines, preferences and focus rules).
- `Cache.sqlite` (with `Cache.sqlite-wal` and `Cache.sqlite-shm`): derived values. To clear it by hand, quit the app and delete all three files; it is recreated empty on launch. If the cache cannot be opened, the app deletes and recreates it on its own; owner data is never affected.
