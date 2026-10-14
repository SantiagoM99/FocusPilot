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
- `Cache.sqlite`: derived values. Deleting it while the app is quit is safe; it is recreated empty on launch.
