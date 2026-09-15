# Tab model rebuild implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `TabManager`, `Tab`, `TabFolder`, `Space` and the tab SwiftData entities with `NookTabsCore` plus a macOS `TabsController` and `PageSession`.

**Architecture:** `NookTabsCore` (done, commit `097b49f`, renamed in `db1d4a4`) owns the tree, rules, undo and storage. The app gets `TabsController` (intents, window selection, session table) and `PageSession` (one live page per open item). Foundation adds the new types beside the old ones so every track branch compiles; tracks migrate disjoint file sets; the final task deletes the old types and is the first build that runs correctly.

**Tech Stack:** Swift 5 language mode, SwiftUI with Observation, WebKit, local Swift package, Swift Testing for the package.

**Spec:** `docs/superpowers/specs/2026-09-15-tab-model-rebuild-design.md`
**Call-site inventory:** `docs/superpowers/plans/2026-09-15-tab-rebuild-inventory.md` (file:line for every use of the old API, and the track file lists in section 7.4 onward)

## Global constraints

- macOS deployment target 26.0, Apple Silicon, `SWIFT_VERSION = 5.0`. No `@available` guards below 26.
- No literals in UI code: `NookDesign` tokens only (see CLAUDE.md Design System).
- No polling timers. Heavy work off the main actor.
- Core type names: `ProfileRecord`, `SpaceRecord`, `Item`, `Parent`, `SidebarSection`, `Row`, `TabTree`, `DeviceState`, `TabStore`, `Change`, `ClosedEntry`, `OrderKey`. The app keeps its `Profile` class (owns `WKWebsiteDataStore`). View files may `import NookTabsCore`.
- `SpaceEntity`, `TabEntity`, `FolderEntity`, `TabsStateEntity` stay registered in `Persistence.schema` as unused tables. Removing them risks a schema-mismatch reset of the store that also holds history and extensions. `ProfileEntity` stays too (profile ids are imported from it once).
- Tab state files: `~/Library/Application Support/com.baingurley.nook/Tabs/`.
- Build check for every task: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath <track-specific path> CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO` must print `** BUILD SUCCEEDED **`. Use a derived data path outside the repo per worktree, e.g. `/Users/bain/Library/Developer/NookBuilds/<track>`.
- Package check: `cd Packages/NookTabsCore && swift test` passes.
- Commits end with `AI-assisted: implemented with Claude Code.` Never commit to `main`. Never push.
- Intermediate branches only need to compile. Runtime correctness is verified after task Z.

## Branches

- `rebuild/tab-model` (worktree `/Users/bain/git/Nook-tab-rebuild`): foundation commits go here and tracks merge back here.
- Tracks branch from foundation: `rebuild/t1-sidebar` ... `rebuild/t5-callers`, each in `/Users/bain/git/Nook-<track>`.

## Foundation API contract

Tracks code against these exact names. Foundation implements all of them; bodies may be minimal where the old model still drives runtime, but signatures and semantics are fixed.

### TabsController

`@MainActor @Observable final class TabsController`, file `Nook/Browser/TabsController.swift` (split into extensions by concern as it grows). Created once by `BrowserManager`, exposed as `browserManager.tabs`, injected with `.environment(tabs)`.

```swift
enum Placement { case newTab, background, replaceCurrent }

// State
private(set) var tree: TabTree
private(set) var device: DeviceState
var isReadOnly: Bool { get }
var loadOutcome: LoadOutcome { get }

// Reads
func space(_ id: UUID) -> SpaceRecord?
var orderedSpaces: [SpaceRecord] { get }
func spaces(inProfile profileID: UUID) -> [SpaceRecord]
func item(_ id: UUID) -> Item?
func children(of parent: Parent) -> [Item]
func favorites(of profileID: UUID) -> [Item]
func rows(space spaceID: UUID) -> [Row]                  // visibleRows with device.openFolders
func section(of itemID: UUID) -> Parent?
func spaceID(of itemID: UUID) -> UUID?
func profileID(of itemID: UUID) -> UUID?
func items(inProfile profileID: UUID) -> [Item]          // live tabs only, all sections
func isOpen(folder: UUID) -> Bool
func hasLeftHome(_ itemID: UUID) -> Bool                 // synced tab whose open page host+path differs from url
var canReopenClosed: Bool { get }

// Sessions
func session(for itemID: UUID) -> PageSession?
var sessions: [PageSession] { get }                      // all live, including private windows
func session(for webView: WKWebView) -> PageSession?
func selectedItemID(in window: BrowserWindowState) -> UUID?
func selectedSession(in window: BrowserWindowState) -> PageSession?
var activeWindowSession: PageSession? { get }
func displayOrder(in window: BrowserWindowState) -> [UUID]   // favorites, then rows (tabs only), for Cmd+1..9 and compositor
func isVisibleInAnyWindow(_ itemID: UUID) -> Bool

// Intents
@discardableResult func open(url: URL, in window: BrowserWindowState, placement: Placement, parent: Parent? = nil) -> UUID?
@discardableResult func adopt(webView: WKWebView, url: URL, title: String, in window: BrowserWindowState, placement: Placement) -> UUID?
func select(_ itemID: UUID, in window: BrowserWindowState)
func selectNext(in window: BrowserWindowState)
func selectPrevious(in window: BrowserWindowState)
func select(index: Int, in window: BrowserWindowState)   // 0-based over displayOrder
func selectLast(in window: BrowserWindowState)
func setSpace(_ spaceID: UUID, in window: BrowserWindowState)
func selectNextSpace(in window: BrowserWindowState)
func selectPreviousSpace(in window: BrowserWindowState)
func close(_ itemID: UUID)                               // pinned/favorite: ends the page only; tabs section: closes the item
func close(_ itemIDs: [UUID])
func closeSelected(in window: BrowserWindowState)
func reopenLastClosed(in window: BrowserWindowState)
func move(_ itemID: UUID, to parent: Parent, after: UUID?)
func drop(_ itemID: UUID, section: Parent, rows: [Row], index: Int, intoFolder: Bool)
func pin(_ itemID: UUID, to parent: Parent)              // .pinned(space) or .favorites(profile)
func unpin(_ itemID: UUID)                               // to the top of its space's tabs section
func rename(_ itemID: UUID, _ customTitle: String?)
@discardableResult func duplicate(_ itemID: UUID, in window: BrowserWindowState) -> UUID?
func resetToHome(_ itemID: UUID)
func setHomeToCurrent(_ itemID: UUID)
func setHome(_ itemID: UUID, url: URL)
@discardableResult func createFolder(title: String, in parent: Parent, after: UUID?) -> UUID?
func toggleFolder(_ folderID: UUID)
func setAllFolders(open: Bool, space spaceID: UUID)
@discardableResult func createSpace(profileID: UUID, name: String, icon: String, accentHex: String, after: UUID?) -> UUID?
func updateSpace(_ spaceID: UUID, name: String?, icon: String?, accentHex: String?)
func moveSpace(_ spaceID: UUID, toProfile profileID: UUID, after: UUID?)
func deleteSpace(_ spaceID: UUID)
@discardableResult func createProfile(name: String, icon: String) -> UUID
func updateProfile(_ profileID: UUID, name: String?, icon: String?)
func deleteProfile(_ profileID: UUID, heir: UUID)
func unload(_ itemID: UUID)                              // user request; moves selection off a visible item first
func unloadAllHidden()
func apply(_ change: Change)                             // external undo (tab organizer)
func flushSync()
```

Every intent that changes the tree calls `TabStore.save(tree, device)` and keeps its `Change` on an undo stack. Errors from the tree are logged with `Logger(subsystem: "com.baingurley.nook", category: "Tabs")` and leave state unchanged.

### PageSession

`@MainActor @Observable final class PageSession`, files `Nook/Browser/Session/PageSession*.swift`, built by moving the live-page half of `Tab.swift`. Members (old name in parentheses):

- Identity: `itemID: UUID`, `isPrivate: Bool`, `profile: Profile?` (`resolveProfile()`)
- Web view: `webView: WKWebView?` (`existingWebView`), `activeWebView: WKWebView`, `assignedWebView`, `loadWebViewIfNeeded()`, `unload()` (`unloadWebView`), `isUnloaded: Bool`, `assignWebView(_:toWindow:)`, `cleanupClone(_:)`, `tearDown()` (`performComprehensiveWebViewCleanup`), `configure(_ webView: WKWebView)` (`configureTabWebView`), `static func loadPage(_ url: URL, in webView: WKWebView)`, `webProcessCrashCount`, `lastWebProcessCrashDate`
- Navigation: `url: URL` (committed), `title: String`, `favicon: Image`, `load(_ url: URL)`, `navigate(to input: String)`, `refresh()`, `stop()`, `goBack()`, `goForward()`, `canGoBack`, `canGoForward`, `loadingState: LoadingState`, `isLoading: Bool`
- Media: `hasPlayingAudio`, `hasPlayingVideo`, `hasAudioContent`, `hasVideoContent`, `isAudioMuted`, `toggleMute()`, `setMuted(_:)`, `hasPiPActive`, `requestPictureInPicture()`, `checkMediaState()`
- Chrome: `pageBackgroundColor`, `topBarBackgroundColor`, `blockedRequestCount`, `isOAuthFlow`, `onLinkHover`, `onCommandHover`, `pendingContextMenuPayload`, `deliverContextMenuPayload(_:)`, `isOptionKeyDown`
- Find: `find(_:completion:)`, `findNext(completion:)`, `findPrevious(completion:)`, `clearFind()`
- Reports to the controller: `controller?.pageCommitted(itemID:url:)` after a committed navigation or SPA URL change, `controller?.pageTitleChanged(itemID:title:)`.

Behavior carried over unchanged from commit `4cb64fb`: URL revert on failed provisional navigation, fresh cache policy on restore, crash recovery, `refresh()` fallback to load, popups with their own `WKUserContentController`, handler install on adopted views, private routing for new tabs and popups.

### BrowserWindowState additions

`spaceID: UUID?` (replaces `currentSpaceId`), `selectedItemBySpace: [UUID: UUID]` (replaces `activeTabForSpace`), computed `selectedItemID: UUID?` (replaces `currentTabId`), `split: SplitRecord?`, `profileID: UUID?` (replaces `currentProfileId`), `isIncognito`, `privateTree: TabTree?` and `privateSessions` for private windows. Old properties stay until task Z.

### Other foundation types

- `FaviconCache` (`Nook/Browser/FaviconCache.swift`): `static let shared`, `image(for key: String) -> NSImage?`, `store(_ image: NSImage, for key: String)`, `clear()`, `stats() -> (memory: Int, disk: Int)`. Moved from `Tab` statics.
- `SpaceRecord` presentation helpers in `Nook/Browser/SpaceRecord+UI.swift`: `accentColor: Color`, `accentNSColor: NSColor`.
- Extension hooks, called by `TabsController`, implemented by T4: `ExtensionManager.shared.notifyTabOpened(_ session: PageSession)`, `notifyTabActivated(new: PageSession, previous: PageSession?)`, `notifyTabClosed(itemID: UUID)`, `notifyTabPropertiesChanged(_ session: PageSession, properties: WKWebExtension.TabChangedProperties)`, `wakeBackgroundWorkers()`.
- `TabOrganizerManager.organizeTabs(in spaceID: UUID, using tabs: TabsController)`.

---

### Task F: Foundation

**Files:** owns every file in inventory 7.4 "F Foundation files", plus new `Nook/Browser/**`, `BrowserManager+Import.swift`, `BrowserManager+ActivePage.swift`, `Nook.xcodeproj/project.pbxproj`.

- [ ] Add `Packages/NookTabsCore` to the Xcode project as a local package (`XCLocalSwiftPackageReference`, product `NookTabsCore` linked to the Nook target). Build.
- [ ] Pure moves, no behavior change: `BrowserManager+Import.swift` (import functions) and `BrowserManager+ActivePage.swift` (current-page cookies/cache, window-aware page commands, URL copy, inspector, zoom), line ranges in inventory 7.1. Build. Commit.
- [ ] `FaviconCache` extracted from `Tab` statics; `Tab` forwards to it. `SpaceRecord+UI.swift`. Build. Commit.
- [ ] `PageSession` files created by copying the live-page code of `Tab.swift` (Tab stays intact until Z). Build. Commit.
- [ ] `TabsController` with the full contract. Loads through `TabStore`; first launch seeds from `ProfileEntity` ids (one profile record per existing profile, same UUID, so data stores keep cookies) plus one space and one tab per profile. Read-only outcome shows an `NSAlert` naming the reason. Build. Commit.
- [ ] `BrowserWindowState` additions; `BrowserManager.tabs` created and injected in `NookApp`; `AppDelegate.applicationShouldTerminate` calls `tabs.flushSync()`. Extension hook method stubs (empty bodies) in a new `ExtensionManager+PageSessionHooks.swift` owned by F until T4 fills them. Build. Commit.
- [ ] Controller-level test harness is out of scope (no app test target); add package tests for any new core helper.

### Task T1: Sidebar outline, favorites, drag

**Files:** inventory 7.4 "T1" list. Replace the sidebar with one `LazyVStack` per space over `tabs.rows(space:)`, indentation by `row.depth * NookDesign.Spacing.folderIndent`; favorites grid over `tabs.favorites(of:)`; `TabContextMenu(itemID:context:)` and `FolderContextMenu` against intents; drag sources carry item ids; drop zones call `tabs.drop(...)`; dot for `hasLeftHome`; delete `Nook/Managers/DragManager/`.

### Task T2: Spaces, profiles, settings chrome

**Files:** inventory "T2" list. Space switcher, space title (empty pinned section drop calls `tabs.drop`), space context menu and edit dialog, profile settings (counts from `items(inProfile:)`), air traffic control pickers, window view space paging, all against `SpaceRecord` and space/profile intents.

### Task T3: Page chrome and web view plumbing

**Files:** inventory "T3" list plus `BrowserManager+ActivePage.swift`. Compositor, `WebViewCoordinator` keyed by item id, website view, top bar, URL bar, nav buttons, progress bar (Observation instead of Combine), split view on `BrowserWindowState.split`, find, PiP, media controls, authentication, content blocker tab lookup, cache manager, focusable web view and context menu bridge, all against `PageSession`.

### Task T4: Extensions

**Files:** inventory "T4" list plus `ExtensionManager+PageSessionHooks.swift`. `ExtensionTabAdapter` keyed by item id wrapping `Item` + `PageSession`; window adapter lists `displayOrder(in:)`; hook implementations.

### Task T5: Intent callers

**Files:** inventory "T5" list plus `BrowserManager+Import.swift`. Commands, keyboard shortcuts, command palette, search, AI browser tools, site routing, Peek, mini window, tab organizer (undo becomes `tabs.apply(change)`), history menu, web context menu, onboarding, importers building `TabTree` changes.

### Task Z: Switch, delete, verify

- [ ] Merge T1 to T5 into `rebuild/tab-model`. Resolve conflicts in foundation-owned files only.
- [ ] Delete `TabManager.swift`, `Tab.swift`, `TabFolder.swift`, `Space.swift`, old `BrowserWindowState` properties, the old `BrowserManager` tab API, `scripts/tests/tab-*`. Keep the entity classes listed in Global constraints, moved into `Nook/Models/Legacy/LegacyTabEntities.swift`.
- [ ] Debug and Release builds succeed. `swift test` passes.
- [ ] Run the spec's acceptance checklist in the app with Bain.
- [ ] Update CLAUDE.md (architecture tables, key patterns, tab sections).
