# Tab model rebuild

Status: approved 2026-09-15. Replaces `TabManager`, `Tab`, `TabFolder` and the tab SwiftData entities.

The current model stores a tab's location twice (one of four buckets plus `isPinned` / `isSpacePinned` / `folderId` / `spaceId` / `profileId` flags), uses integer indices with different meanings in storage and in the sidebar, keeps selection in both `TabManager.currentTab` and each window, and mixes saved data with the live `WKWebView` in a 3,500 line `Tab` class. The September 15 reviews traced every duplicate, disappearing and lost tab bug to one of those four causes. Folders have no parent field, so nesting is impossible without a new model.

## Decisions

| Question | Decision |
|---|---|
| Regular tabs | Per-device session. Restored on relaunch. Later shown read-only on other devices. |
| Folders | Nest in both the pinned section and the tabs section, up to 5 levels. Folders under pinned sync; folders under tabs are local. |
| Favorites | Per profile. |
| Pinned tab reopen | Keeps its open page across relaunch. Closing it ends the page; the next click opens the home URL. |
| Build approach | Foundation-only core package with unit tests first, then one cutover branch in the app. |
| Sidebar rendering | Flattened visible rows in a `LazyVStack`, existing NSView drag source kept. |
| Existing tab data | Discarded. Profile ids are imported once so each profile keeps its `WKWebsiteDataStore` (cookies and logins). |

## Data model (`NookTabsCore`)

Local Swift package at `Packages/NookTabsCore`. Imports Foundation only. No AppKit, WebKit or SwiftData.

```swift
public struct ProfileRecord: Identifiable, Codable, Hashable {
    public let id: UUID
    public var name: String
    public var icon: String
    public var order: OrderKey
    public var modifiedAt: Date
    public var deletedAt: Date?
}

public struct SpaceRecord: Identifiable, Codable, Hashable {
    public let id: UUID
    public var profileID: UUID
    public var name: String
    public var icon: String
    public var accentHex: String
    public var order: OrderKey
    public var modifiedAt: Date
    public var deletedAt: Date?
}

public enum Parent: Codable, Hashable {
    case favorites(profileID: UUID)
    case pinned(spaceID: UUID)
    case tabs(spaceID: UUID)
    case folder(itemID: UUID)
}

public enum ItemKind: Codable, Hashable {
    case tab(url: URL, pageTitle: String)
    case folder
}

public struct Item: Identifiable, Codable, Hashable {
    public let id: UUID
    public var parent: Parent
    public var order: OrderKey
    public var kind: ItemKind
    public var customTitle: String?
    public var modifiedAt: Date
    public var deletedAt: Date?
}
```

Sections (favorites, pinned, tabs) are `Parent` values and have no records, so two devices can never create duplicate sections.

`Scope` is derived by walking up to the section: `.favorites` and `.pinned` are `.synced`, `.tabs` is `.device`. Moving a folder between sections moves its whole subtree into the other scope.

`url` is the home URL for a synced tab and the last committed URL for a device tab.

`OrderKey` is a string that sorts lexicographically, with `key(between:and:)` generating a key strictly between two neighbors (or before the first, after the last). Siblings sort by `(order, id)`. A move writes one item.

### Rules

`TabTree` enforces these on every change and on load:

1. A parent exists and is not deleted. A space belongs to an existing profile.
2. An item is never its own ancestor.
3. Folder depth is at most 5.
4. `.favorites` holds tabs only.
5. Every item has exactly one parent (guaranteed by the single `parent` field).

A change that breaks a rule throws `TreeError` and leaves the tree unchanged. The loader repairs instead of throwing: an item whose parent is missing moves to the root of its original section, or to the first space's tabs section when the space is gone; depth beyond 5 is flattened to the fifth level; a folder in favorites moves to the first space of that profile.

### Device state

Kept only on this Mac, never synced:

```swift
public struct DeviceState: Codable {
    public var openFolders: Set<UUID>
    public var openPages: [UUID: OpenPage]          // pinned and favorite items with a live page
    public var windows: [WindowRecord]
    public var closed: [ClosedEntry]                 // newest last, capped at 50
    public var firstLaunchCompleted: Bool
}

public struct OpenPage: Codable, Hashable { public var url: URL; public var title: String }

public struct WindowRecord: Codable, Hashable {
    public var id: UUID
    public var spaceID: UUID?
    public var selectedItemBySpace: [UUID: UUID]
    public var split: SplitRecord?
    public var frame: String?                        // NSStringFromRect, restored by the app
}
```

## Changes and undo

All edits go through `TabTree` mutating methods. Each returns a `Change` value that undoes it.

| Method | Effect |
|---|---|
| `createTab(url:title:in:after:)` | New tab under a parent, placed after a sibling (nil = first). |
| `createFolder(title:in:after:)` | New folder. |
| `move(_:to:after:)` | Reparent and reorder. Moving into `.pinned` or `.favorites` from `.tabs` sets `url` to the page the tab shows. Moving out sets `url` from the open page when there is one. |
| `rename(_:customTitle:)` | nil clears the custom title. |
| `setURL(_:_:)`, `setPageTitle(_:_:)` | Called by the page session after a committed navigation. |
| `close(_:)` | Removes an item and its subtree. Synced items get `deletedAt`; device items are removed. The subtree is appended to `DeviceState.closed` with original ids, parent and order. |
| `reopenLastClosed()` | Restores the newest closed entry under its original parent when it still exists, else at the root of its original section, else in the first space's tabs section. |
| `createSpace`, `moveSpace`, `renameSpace`, `deleteSpace` | Deleting a space closes its items as one closed entry. The last space of the last profile cannot be deleted. |
| `createProfile`, `renameProfile`, `deleteProfile` | Deleting moves the profile's spaces and favorites to another profile. The last profile cannot be deleted. |

`TabTree.visibleRows(space:openFolders:)` returns `[Row]` where `Row` is `(item, depth, section)` in display order: pinned section, then tabs section, folders expanded only when open. `TabTree.dropTarget(rows:index:intoFolder:)` converts a drop position in that list to `(parent, after)`.

## Storage

Two JSON files in `~/Library/Application Support/com.baingurley.nook/Tabs/`:

- `structure.json`: profiles, spaces, synced items, including `deletedAt` tombstones. Tombstones older than 30 days are purged on load.
- `device.json`: device items (tabs section and its folders) and `DeviceState`.

Each file carries a `formatVersion` integer.

`TabStore` is an actor. The app sends it the current tree and device state after each change; it coalesces for 500 ms, encodes, and writes with `Data.write(to:options: .atomic)`. `flushSync()` writes immediately and is called from `applicationShouldTerminate`. A move between scopes writes `device.json` and `structure.json` in the order destination first, so a crash between the two writes leaves a duplicate id; the loader keeps the synced copy.

Loading:

1. Missing files with `firstLaunchCompleted` absent: first launch. Seed one profile (imported ids from the old `ProfileEntity` table when present), one space and one tab. Set `firstLaunchCompleted`.
2. A file that fails to decode, or a `structure.json` with no profiles after first launch: treat as corruption. Load the newest backup that decodes. If none decodes, start in read-only mode: the UI works, `TabStore` writes nothing for the session, and an alert names the file.
3. After a successful load, copy both files to `Tabs/Backups/<yyyy-MM-dd>/`, keeping 7 days.

Pinned items and favorites always restore. A startup setting may only affect which device tabs load pages immediately.

## macOS layer

### PageSession

`@MainActor @Observable final class PageSession`, one per item that has a live page, keyed by item id. Holds committed URL, loading URL, title, favicon, loading state, back/forward availability, media and audio state, zoom and the per-window web views through `WebViewCoordinator`.

`Tab.swift` is split by responsibility into `Nook/Browser/Session/`: `PageSession.swift`, `PageSession+Navigation.swift`, `PageSession+UIDelegate.swift`, `PageSession+Media.swift`, `PageSession+Scripts.swift`. Behavior from the September 15 fixes carries over unchanged: revert URL when a provisional navigation fails, fresh cache policy on restore, crash recovery that loads the saved URL and unloads hidden pages, `refresh()` fallback to a load, popups with their own `WKUserContentController`, handler install on adopted Peek and mini window views, incognito routing for new tabs and popups.

A session reports to the tree through `setURL` after a committed navigation and `setPageTitle`. For pinned items it updates `DeviceState.openPages` instead.

Unloading (idle timer, tab budget, memory pressure, background) works on sessions. One predicate, `isVisibleInAnyWindow(itemID)`, covers every window's selection and both split panes.

### TabsController

`@MainActor @Observable final class TabsController` replaces `TabManager` and the tab code in `BrowserManager`. Owns `TabTree`, `DeviceState`, `TabStore` and the session table. Public intents:

- `open(url:in:placement:)` with placement `.newTab`, `.background`, `.replaceCurrent`
- `select(_:in:)`, `close(_:)`, `reopenLastClosed(in:)`
- `move(_:to:after:)`, `pin(_:to:)`, `unpin(_:)`, `rename(_:_:)`
- `resetToHome(_:)`, `setHomeToCurrent(_:)`
- space and profile intents matching the tree methods

Selecting a pinned item with no open page loads its home URL. Closing a pinned item ends its session and removes its `openPages` entry. A row shows a dot when the open page's host and path differ from the home URL.

### Windows

`BrowserWindowState` holds `spaceID`, `selectedItemBySpace` and the split pair, mirrored into `DeviceState.windows`. There is no global current tab. Code that needs one reads the active window's selection. Windows reopen from `DeviceState.windows` on launch.

### Private windows

Each private window owns an in-memory `TabTree` with one space, plus sessions on the ephemeral profile. It is never connected to `TabStore`.

### Sidebar

One `LazyVStack` per space renders `visibleRows`. Rows use `NookDesign` tokens with indentation of `Spacing.folderIndent` per depth level. The favorites grid stays above it. The shared context menu builders are rewritten against items. Drag uses the existing `NookDragSourceView` and preview window; drop zones resolve through `dropTarget` to `(parent, after)`. Dropping on the middle of a folder row inserts into the folder.

### Callers

Extensions (`ExtensionTabAdapter` keyed by item id), AI browser tools, command palette, site routing, Peek, mini window, history, keyboard shortcuts, split view, tab organizer and downloads call `TabsController` intents.

## Sync readiness

Structure records carry UUID ids, `modifiedAt` and `deletedAt`. Profiles are identified only by UUID. No sync code, CloudKit container or entitlement is added. The CKSyncEngine project adds pending change state, remote merge with cycle repair, and a guard that rejects remote deletes until the tree has loaded.

## Testing

`swift test` in `Packages/NookTabsCore`:

- Random sequences of 1,000 changes (seeded) keep every rule true.
- Applying a change and then its undo restores an equal tree.
- `OrderKey` generation between adjacent keys, at both ends, and after 10,000 inserts at one position.
- `visibleRows` and `dropTarget` for nested open and closed folders.
- `TabStore` round trip on disk, crash between the two cross-scope writes, corrupt file with a good backup, corrupt file with no backup (read-only), first launch.

The app is verified by Debug and Release builds and the manual checklist below. The Python and extracted-Swift regression scripts under `scripts/tests/tab-*` are deleted.

## Cutover

0. Commit the current working tree tab fixes on `main` as the baseline.
1. `NookTabsCore`: model, rules, `OrderKey`, changes and undo, rows and drop targets, `TabStore`. Tests pass.
2. Branch `rebuild/tab-model` in a worktree. Add the package to the Xcode project. `PageSession` split from `Tab`, `TabsController`, window selection.
3. Sidebar outline, favorites grid, context menus, drag.
4. Callers listed above.
5. Delete `TabManager`, `Tab`, `TabFolder`, `TabEntity`, `FolderEntity`, `SpaceEntity`, `TabsStateEntity`, `ProfileEntity` (after the one-time id import), `Nook/Managers/DragManager/`, and the old regression scripts. `HistoryEntity` and `ExtensionEntity` stay in `default.store`.
6. Release build, manual checklist, CLAUDE.md update, merge to `main`.

Steps 2 and 3 can run in parallel worktrees once step 1 fixes the package API.

## Acceptance checklist

- Quit and relaunch restores every space, pinned item, favorite, folder (nested), custom title, device tab, window, selection and split.
- A pinned tab navigated away shows the dot, survives relaunch on its current page, and opens its home URL after Cmd+W.
- Drag moves items into and out of nested folders at the drop position, in both sections and across spaces.
- Close, then reopen last closed, puts a tab or folder back with the same id and position, including after its folder was deleted.
- Deleting a space or profile never leaves an item that no sidebar shows.
- Two windows on the same space select independently; unloading never blanks a visible pane.
- A private window's tabs never appear in `device.json` or `structure.json`.
- Killing the app with `kill -9` mid-use loses at most the last 500 ms of changes.
- Corrupting `structure.json` restores from backup; with no backup the app runs read-only and says so.
