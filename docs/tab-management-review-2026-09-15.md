# Tab management review — 2026-09-15

Scope: current working tree, including existing uncommitted changes. Review only; no browser behavior changes. Findings cover existing code as well as recent changes.

## Findings

### 1. P1 — Startup merges unrelated spaces across profiles

**Location:** `Nook/Managers/TabManager/TabManager.swift:2145–2159`.

`loadFromStore` identifies duplicate spaces solely by name and icon. Two profiles with a “Personal” space using the same icon collapse into one on restart. The following tab/folder loading loops remap the removed space's contents into the surviving space. Tabs consequently resolve the surviving space's profile, and the migration is persisted. Intentionally matching spaces within one profile are also merged.

**Fix:** Remove this recurring heuristic. Any legacy repair should be a versioned migration based on evidence of the specific faulty creation event; profile plus name is still insufficient to identify intentional duplicates.

**Verification:** Ran the extracted Swift deduplication block with two spaces belonging to different profiles. It retained one space and mapped the second profile's space to the first.

### 2. P1 — Folder transitions duplicate tab membership

**Locations:** `Nook/Managers/TabManager/TabManager.swift:956–965`, `:1661–1684`; caller `Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:79–96`.

“Add to Folder” is offered for space-pinned tabs but always calls `moveTabToRegularFolder`. That method appends the tab to regular tabs without removing it from space-pinned tabs. The same object then belongs to both containers. The menu also lists both folder types without routing according to the destination type. Separately, dragging a regular-folder tab out to the regular area removes only from the pinned container, then inserts it into the regular container again.

Duplicate IDs fail `validateInput`, forcing persistence onto its fallback. This does not prove that every save fails: the fallback skips input validation. It also omits folder writes, making it an inadequate substitute for the atomic snapshot path.

**Fix:** Use one container-transfer operation for menu and drag actions. Resolve the destination folder's type, remove the source membership, update flags, insert once, normalize indices, and persist.

**Verification:** Executed extracted Swift container methods with lightweight storage stubs. Adding a pinned tab to a folder produced one pinned entry plus one regular entry: two IDs, one unique ID. The extracted drag branch also produced two entries with one unique ID.

### 3. P2 — Moving a folder tab to another space makes it disappear

**Location:** `Nook/Managers/TabManager/TabManager.swift:1792–1799`.

“Move to Space” updates `spaceId` but retains the source `folderId`. The destination loose-tab list excludes any tab with a folder, and the destination has no matching folder. The tab remains in storage but disappears from the normal sidebar lists, including after restart.

**Fix:** Clear folder membership on a space move unless the operation explicitly supplies a valid destination folder.

**Verification:** Executed extracted Swift move/container methods. Destination contained one tab, its loose-tab list contained zero, and the tab retained its source folder ID.

### 4. P2 — Bulk unloading discards tabs visible in other windows or split panes

**Location:** `Nook/Managers/TabManager/TabManager.swift:1478–1483`.

“Unload All Inactive Tabs” excludes only the manager's single `currentTab`. With two windows showing different regular tabs in the same space, the other window's visible tab qualifies for unloading. A non-focused split pane can qualify too. The direct compositor unload path discards its WebViews and page state; it does not apply the all-window visibility exemptions used by automatic eviction.

**Fix:** Share the visibility eligibility check between automatic eviction and bulk unloading, including every window and split pane.

**Verification:** Static trace through manager, compositor unload, all-window exemptions, and `Tab.unloadWebView`; no GUI reproduction.

### 5. P2 — Unloaded popup tabs restore as blank pages

**Location:** `Nook/Models/Tab/Tab.swift:619–620`; flag set at `Nook/Managers/TabManager/TabManager.swift:1428`.

Popup creation sets `isPopupHost`, causing initial setup to leave navigation to WebKit. The flag is never cleared. After unloading a popup tab, selecting it creates a replacement WebView that again skips loading the saved URL. This time there is no pending popup request to initiate navigation.

**Fix:** Make popup navigation suppression apply only to the original creation, or reset the flag when that WebView is discarded.

**Verification:** Static trace of flag assignments, popup creation, unload, and setup; no GUI reproduction.

### 6. P2 — Per-space active tab selection is never written to disk

**Locations:** `Nook/Managers/TabManager/TabManager.swift:297–315`, `:2377`; `Nook/Models/Space/SpaceModels.swift:15`.

Snapshots include `activeTabId`, but `SpaceEntity` has no corresponding field, the upsert never saves it, and load reconstructs each space with a nil active tab. After restarting, returning to a previously used space falls back to the first available tab instead of its prior selection. Global current-tab persistence only covers the startup selection; window-specific selection memory is also in-memory.

**Fix:** Persist and restore the per-space selection with an optional field, then validate that it belongs to the space or its profile's essentials.

**Verification:** Static schema/write/read trace.

### 7. P2 — Folder order is discarded on restoration

**Location:** `Nook/Managers/TabManager/TabManager.swift:2244–2256`.

`FolderEntity.index` is persisted but is neither used to sort fetched folders nor passed into the runtime `TabFolder` initializer. Every restored folder receives the default index of zero. The UI and next snapshot sort on those zero values, losing the previously saved ordering.

**Fix:** Restore `index: e.index` and load folders in index order. Give new folders an append index instead of the initializer's default zero.

**Verification:** Static schema/initializer/load/snapshot trace.

## Improvements

- Centralize tab transfers and enforce one container per tab, consistent pin flags, and valid same-space folder membership. Extend snapshot validation to folder relationships.
- Make fallback persistence preserve the full snapshot, including folders, and distinguish invalid input from transient storage failures. Return an explicit result for committed, fallback-committed, stale, and failed saves.
- Share a single visibility predicate for resource management, while keeping explicit user-requested unload behavior separate from bulk inactive-tab selection.
- Add focused regression coverage for container transitions, cross-profile restart, folder/selection round trips, popup eviction, and two-window/split unloading. A small model-level test harness can cover most state transitions without constructing WebViews.

## Validation limits

Four focused scenario reproductions used extracted production Swift logic with lightweight fixtures. These were not full application or SwiftData integration tests. Remaining findings are based on traced call paths. No application build or GUI test was run, and no runtime performance claims are made.
