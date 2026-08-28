# Shelf

A place to put files down. Drag them onto the menu bar, go find where they belong,
drag them off. Menu bar only — no Dock icon, no window, no dependencies, no App Store
paperwork.

Requires macOS 14+ and Swift 5.9+.

## Build & run

```bash
./build-app.sh --install     # release build, copy to /Applications, launch
./build-app.sh               # just produce ./Shelf.app
./build-app.sh --universal   # arm64 + x86_64
```

The bundle is ad-hoc signed (`codesign --sign -`). No developer account, provisioning
profile, or notarization is involved. Shelf needs no permissions.

## Using it

Drag any file or folder **onto the menu bar icon**. The icon highlights as a valid
target and fills in once it is holding something.

Click the icon to see what is on the shelf:

- **Drag a row off** to move or copy it wherever you are going — the destination gets
  the original file and decides what to do with it.
- **Click a row** to reveal it in Finder.
- **Hover a row** for an ✕ to take it off the shelf.
- **Clear** empties the shelf.

The point is the gap in between. Most file dragging on a Mac means keeping the source
and the destination visible at the same time — across Spaces, out of a message thread,
from a window you are about to navigate away from. Put things down, go somewhere else,
pick them back up.

## Nothing is moved or copied

The shelf holds *references*. Dropping a file here does not duplicate it, move it, or
take a snapshot — the file stays exactly where it was. Clearing the shelf deletes
nothing.

The consequence is that shelf entries can go stale: move or delete a file elsewhere
and its row is pointing at nothing. Shelf drops those rows automatically, checking
every five seconds and whenever the popover opens.

## How it works

`Sources/Shelf/`

- **`ShelfApp.swift`** — `@main`, `AppDelegate`, the status item, and `DropTargetView`.
- **`ShelfStore.swift`** — the held items and their persistence.
- **`PopoverView.swift`** — the SwiftUI popover.

`DropTargetView` sits over the status item button and handles everything. A plain
subview would swallow clicks, and returning nil from `hitTest` to let them through
would also stop drags from reaching it — so the view takes both and forwards clicks
on to the toggle.

Paths are normalised with `standardizedFileURL` in one place, when an item is built.
Normalising only on the way in meant an item loaded from disk did not compare equal to
the same file dropped again, so re-dropping something after a relaunch added a
duplicate row instead of promoting it. File attributes are read through symlinks, so a
dragged `/Applications` app reports as a bundle rather than as its link's few bytes.

## Known limits

- The shelf survives restarts by storing paths. A file renamed while Shelf is not
  running is simply gone from the shelf next launch, not followed.
- Dragging off hands over the file URL. What happens next — copy, move, or open — is
  the destination's decision, exactly as if you had dragged from Finder.
- No stacking or multi-select: rows drag one at a time.
