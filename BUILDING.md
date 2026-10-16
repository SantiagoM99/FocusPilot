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

The script builds a release executable, wraps it in `build/FocusPilot.app` with `Packaging/Info.plist`, compiles the app icon with `actool`, and signs it ad hoc. The bundle runs only on the Mac that built it.

Before turning on "Open at Login", copy the app somewhere stable and launch that copy:

```sh
ditto build/FocusPilot.app ~/Applications/FocusPilot.app   # or /Applications
open ~/Applications/FocusPilot.app
```

The login item points at one specific app on disk. Every ad hoc rebuild changes the signature, and a worktree's `build/` folder goes away when the worktree is removed, so a login item registered from `build/` can stop working.

Prefer the bundle over `swift run FocusPilot`: the bare executable has no Info.plist, so `LSUIElement` and login-item registration do not apply to it.

## Artwork

The app icon and the menu bar glyphs are drawn from the logo geometry in code (`Sources/FocusPilotCore/AppIcon` and `Sources/FocusPilotCore/MenuBar`); there are no hand-drawn image files. `build-app.sh` writes `build/artwork/AppIcon.icon` (an Icon Composer file) and compiles it into the bundle.

To review the artwork without launching the app:

```sh
./scripts/render-review-images.sh /tmp/focuspilot-artwork
```

This writes the four menu bar glyphs in light and dark (with and without the time label) and the app icon at 1024, 128, 32 and 16 px, rendered by Icon Composer's `ictool`.

## Layout

| Path | Contents |
|---|---|
| `Sources/FocusPilotCore` | Testable logic: storage, coordinator, tasks and deadlines, login item, menu bar state, artwork geometry |
| `Sources/FocusPilot` | The SwiftUI app: menu bar item, planning window, settings |
| `Sources/RenderArtwork` | Build-time tool that writes `AppIcon.icon` and review images |
| `Tests/FocusPilotCoreTests` | Swift Testing suites for `FocusPilotCore` |
| `Packaging/Info.plist` | Bundle metadata, including `LSUIElement` |

## Data

The app stores two SQLite files in `~/Library/Application Support/FocusPilot`:

- `FocusPilot.sqlite`: owner data (tasks and, later, deadlines, preferences and focus rules).
- `Cache.sqlite` (with `Cache.sqlite-wal` and `Cache.sqlite-shm`): derived values. To clear it by hand, quit the app and delete all three files; it is recreated empty on launch. If the cache cannot be opened, the app deletes and recreates it on its own; owner data is never affected.
