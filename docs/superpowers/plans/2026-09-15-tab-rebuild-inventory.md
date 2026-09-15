# Tab model rebuild: call-site inventory

Worktree `/Users/bain/git/Nook-tab-rebuild`, branch `rebuild/tab-model`, commit `097b49f`. Read-only scan of App/, CommandPalette/, Navigation/, Nook/, Onboarding/, Settings/, UI/ (276 Swift files). Spec: `docs/superpowers/specs/2026-09-15-tab-model-rebuild-design.md`.

## Method and confidence

- Counts come from Python regex scans (`scratchpad/inv/*.py`) cross-checked with grep. Comment-only lines excluded. A "site" is one match; two matches on one line count twice.
- Section 1: every `tabManager.` / `tabManager?.` access plus the `tm.` alias in SplitViewManager. High confidence (grep totals agree: spaces 56, allTabs 38, currentSpace 25, handleDragOperation 8, persistSnapshot 8).
- Section 2: Swift has no receiver types in text. A match counts when the receiver is a Tab-typed name (`tab`, `*Tab`, `currentTab(for:)`, `currentTabForActiveWindow()`, `left/right` in SplitTabRow, `t` in ExtensionBridge, `current/candidate` in SplitViewManager and MediaControls, `cached` in MediaControlsManager) or `$0/$1` inside a closure over a `*tabs*` collection. Tab-unique members (webView, isUnloaded, pinnedURL...) accept any `$0`. Import DTOs (ImportManager/*.swift) and `SettingsWindow.swift` (SettingsTabs enum) excluded as false positives. Moderate-high confidence: generic names (`id`, `url`, `name`, `index`) may be under-counted where a Tab sits in an oddly named variable. `profileId` on Tab has 0 external reads (resolution goes through `resolveProfile()`).
- Section 3: same receiver heuristic for `space*`/`*Space` and `folder*`/`*Folder`. Moderate confidence.
- Enclosing function names come from a backward scan and are right for normal code; for WK delegate methods they show as `webView`.

## Totals

| Surface | Sites | Files |
|---|---|---|
| `tabManager` member accesses outside TabManager.swift | 327 (297 lines outside Tab.swift) | 44 (43 without Tab.swift) |
| Distinct TabManager members used externally | 65 | |
| `@EnvironmentObject var tabManager: TabManager` declarations | 16 | 16 |
| `.environmentObject(tabManager)` injections | 8 | 5 |
| Tab model/placement field reads/writes (2a) | 382 | see 2a |
| Tab live-page member uses (2b) | 203 | see 2b |
| Tab other members (2c) | 30 | see 2c |
| Space runtime member accesses | 188 | 23 |
| TabFolder runtime member accesses | 41 | 5 |
| Type references `Tab` / `Space` / `TabFolder` (annotations, generics, ctors) | 155 / 24 / 7 | 44 / 15 / 3 |
| BrowserManager tab API call sites | see 4 | |
| Files with any coupled line (excl. the replaced model files) | 79 files, 1,432 coupled lines | |

## 1. TabManager surface used outside TabManager.swift

### 1.1 Type references, injection, wiring

- Property: `BrowserManager.tabManager` (BrowserManager.swift:396), created at 519, back-ref `tabManager.browserManager = self` 541, `reattachBrowserManager` in init.
- `BrowserWindowState.tabManager` weak ref (BrowserWindowState.swift:97), used by computed `currentSpace` (121-130). Set at ContentView.swift:38, BrowserManager.swift:1871, 2561. Read by BrowserToolExecutor.swift:413, 438.
- `@EnvironmentObject var tabManager: TabManager` (16): App/Window/WindowView.swift:14, App/ContentView.swift:14, Navigation/Sidebar/SidebarBottomBar.swift:13, Navigation/Sidebar/SpacesSideBarView.swift:16, Navigation/Sidebar/SpacesList/SpacesList.swift:13, Navigation/Sidebar/SpacesList/SpacesListItem.swift:13, Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift:52, SpaceView.swift:38, SpaceTab.swift:21, SpaceTitle.swift:5, TabFolderView.swift:25, Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:29, SpaceContextMenu.swift:13, Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift:16, Nook/Components/Settings/Tabs/General.swift:12, Nook/Components/Peek/PeekOverlayView.swift:13.
- `.environmentObject(tabManager)` injections (8): App/NookApp.swift:50, 83; Navigation/Sidebar/SpacesSideBarView.swift:314, 332; BrowserManager.swift:2469, 2537; SplitTabRow.swift:110; SpaceTab.swift:155.
- Parameters typed `TabManager`: `SearchManager.setTabManager(_:)` (SearchManager.swift:51, stored weak at 21; called CommandPaletteView.swift:284); `TabOrganizerManager.organizeTabs(in:using:)` (71), `undoLastOrganization(using:)` (179), called SpaceView.swift:531, WindowView.swift:153, NookCommands.swift:196; `TabOrganizationApplier.apply(...tabManager:)` (103), `undo(...tabManager:)` (202); `WebViewCoordinator.getOrCreateWebView(for:in:tabManager:)` (90, called WebsiteView.swift:822), `cleanupWindow(_:tabManager:)` (210), `cleanupAllWebViews(tabManager:)` (245).
- Local aliases: `let tm = bm.tabManager` SplitViewManager.swift:278; `let tabManager = browserManager.tabManager` ExternalMiniWindowManager.swift:130, SiteRoutingManager.swift:56.

### 1.2 Notifications and observed publishers

- `.tabManagerDidLoadInitialData`: declared Nook/Managers/DragManager/TabDragManager.swift:22, posted TabManager.swift:1980. **No observers.** Delete.
- `"TabFoldersDidChange"`: posted TabManager.swift:841, 876, 916; observed only SpaceView.swift:194 (`.onReceive`, rebuilds folder caches).
- `@Published` on TabManager: `spaces`, `currentSpace`, `tabsBySpace` (public); `spacePinnedTabs`, `foldersBySpace`, `pinnedByProfile` (private). No `$tabsBySpace`/`$spaces` Combine subscriptions exist. Views re-render through `@EnvironmentObject` objectWillChange. Explicit observation: `.onChange(of: browserManager.tabManager.spaces)` MediaControlsView.swift:200.
- `Tab` is also observed as `ObservableObject`: `@ObservedObject var tab: Tab` in SpaceTab.swift:11, SplitTabRow.swift:42, MediaControlsView.swift:13, TabContextMenu.swift:25, PinnedGrid.swift:253, ExtensionLibraryView.swift:455; `@ObservedObject var folder: TabFolder` TabFolderView.swift:13; `tab.$loadingState` sink NavButtonsView.swift:80; `tab?.objectWillChange` PageLoadingProgressBar.swift:49. An `@Observable` PageSession breaks these 9 sites.

### 1.3 Lines per file

| File | Lines using `tabManager` members |
|---|---|
| Nook/Managers/BrowserManager/BrowserManager.swift | 89 |
| Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift | 18 |
| Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift | 17 |
| Nook/Components/Sidebar/SpaceSection/SpaceView.swift | 15 |
| Nook/Components/Settings/Tabs/Profiles.swift | 15 |
| Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift | 11 |
| Navigation/Sidebar/SpacesSideBarView.swift | 10 |
| Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift | 10 |
| Nook/Components/Sidebar/SpaceSection/TabFolderView.swift | 9 |
| Nook/Components/Browser/Window/TabCompositorView.swift | 9 |
| Nook/Managers/PeekManager/PeekManager.swift | 8 |
| Nook/Managers/SplitViewManager/SplitViewManager.swift | 7 |
| Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift | 6 |
| Nook/Managers/ExtensionManager/ExtensionBridge.swift | 6 |
| App/NookCommands.swift | 4 |
| Nook/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift | 4 |
| Nook/Managers/SearchManager/SearchManager.swift | 4 |
| Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift | 4 |
| Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift | 4 |
| Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift | 4 |
| Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift | 4 |
| App/AppDelegate.swift | 3 |
| App/Window/WindowView.swift | 3 |
| Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift | 3 |
| Nook/Utils/WebKit/WebContextMenu.swift | 3 |
| Navigation/Sidebar/SidebarBottomBar.swift | 2 |
| Navigation/Sidebar/SpacesList/SpacesList.swift | 2 |
| Navigation/Sidebar/SpacesList/SpacesListItem.swift | 2 |
| Nook/Managers/ExtensionManager/ExtensionManager.swift | 2 |
| Nook/Managers/TabOrganizerManager/TabOrganizerManager.swift | 2 |
| Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift | 2 |
| Nook/Components/Sidebar/FallbackDropBelowEssentialsModifier.swift | 2 |
| Nook/Components/Sidebar/Menu/SidebarMenuHistoryTab.swift | 2 |
| Nook/Components/Sidebar/MediaControls/MediaControlsView.swift | 2 |
| App/NookApp.swift | 1 |
| Nook/Managers/MediaControlsManager/MediaControlsManager.swift | 1 |
| Nook/Managers/ExtensionManager/ExtensionManager+Installation.swift | 1 |
| Nook/Models/BrowserWindowState.swift | 1 |
| Nook/Components/Sidebar/TopBar/TopBarView.swift | 1 |
| Nook/Components/Settings/Tabs/General.swift | 1 |
| Nook/Components/Browser/Window/SplitDropCaptureView.swift | 1 |
| Nook/Components/WebsiteView/WebsiteView.swift | 1 |
| Nook/Components/Peek/PeekOverlayView.swift | 1 |

### 1.4 Members and call sites

Format: `file:line` `Type.enclosingFunction`: code. "Replacement" names the expected foundation API (section 7).


#### `spaces` (56)
Use: list/lookup spaces by id, count for delete guard, filter by profile. Replacement: `tabs.tree.orderedSpaces` / `tabs.space(id)` / `tabs.spaces(in: profileID)`.

- App/NookCommands.swift:190 `NookCommands.body`: `browserManager.tabManager.spaces.first(where: { $0.id == id })`
- App/Window/WindowView.swift:147 `WindowView.body`: `browserManager.tabManager.spaces.first(where: { $0.id == id })`
- Navigation/Sidebar/SpacesList/SpacesList.swift:23 `SpacesList.layoutMode`: `: tabManager.spaces`
- Navigation/Sidebar/SpacesList/SpacesList.swift:34 `SpacesList.visibleSpaces`: `return tabManager.spaces`
- Navigation/Sidebar/SpacesList/SpacesListItem.swift:63 `SpacesListItem.body`: `canDelete: tabManager.spaces.count > 1,`
- Navigation/Sidebar/SpacesSideBarView.swift:145 `SpacesSideBarView.spacesPageView`: `: tabManager.spaces`
- Navigation/Sidebar/SpacesSideBarView.swift:365 `SpacesSideBarView.showSpaceCreationDialog`: `if let targetIndex = tabManager.spaces.firstIndex(where: { $0.id == newSpace.id }) {`
- Navigation/Sidebar/SpacesSideBarView.swift:391 `SpacesSideBarView.resolveCurrentSpace`: `return tabManager.spaces.first { $0.id == currentId }`
- Navigation/Sidebar/SpacesSideBarView.swift:393 `SpacesSideBarView.resolveCurrentSpace`: `return tabManager.spaces.first`
- Nook/Components/Peek/PeekOverlayView.swift:35 `PeekOverlayView.currentSpaceColor`: `let space = tabManager.spaces.first(where: { $0.id == spaceId }) {`
- Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift:65 `AirTrafficControlSettingsView.ruleRow`: `let space = browserManager.tabManager.spaces.first(where: { $0.id == rule.targetSpaceId })`
- Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift:202 `RuleEditSheet.body`: `let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId }) {`
- Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift:211 `RuleEditSheet.groupedSpaces`: `let spaces = browserManager.tabManager.spaces.filter { $0.profileId == profile.id }`
- Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift:214 `RuleEditSheet.groupedSpaces`: `let unassigned = browserManager.tabManager.spaces.filter { $0.profileId == nil && !$0.isEp...`
- Nook/Components/Settings/Tabs/Profiles.swift:81 `ProfilesSettingsView.body`: `if browserManager.tabManager.spaces.isEmpty {`
- Nook/Components/Settings/Tabs/Profiles.swift:88 `ProfilesSettingsView.body`: `ForEach(browserManager.tabManager.spaces, id: \.id) { space in`
- Nook/Components/Settings/Tabs/Profiles.swift:100 `ProfilesSettingsView.spacesCount`: `browserManager.tabManager.spaces.filter { $0.profileId == profile.id }`
- Nook/Components/Settings/Tabs/Profiles.swift:106 `ProfilesSettingsView.tabsCount`: `browserManager.tabManager.spaces.filter {`
- Nook/Components/Settings/Tabs/Profiles.swift:118 `ProfilesSettingsView.pinnedCount`: `let spaceIds = browserManager.tabManager.spaces`
- Nook/Components/Settings/Tabs/Profiles.swift:248 `ProfilesSettingsView.assignAllSpacesToCurrentProfile`: `for sp in browserManager.tabManager.spaces {`
- Nook/Components/Settings/Tabs/Profiles.swift:258 `ProfilesSettingsView.resetAllSpaceAssignments`: `for sp in browserManager.tabManager.spaces {`
- Nook/Components/Settings/Tabs/Profiles.swift:275 `SpaceAssignmentRowView.canDelete`: `browserManager.tabManager.spaces.count > 1`
- Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift:94 `SpaceContextMenu.showDeleteConfirmation`: `isLastSpace: tabManager.spaces.count <= 1,`
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:110 `TabContextMenu.moveToSpaceMenu`: `let spaces = tabManager.spaces`
- Nook/Components/Sidebar/MediaControls/MediaControlsView.swift:200 `MediaControlsView.body`: `.onChange(of: browserManager.tabManager.spaces) { _, _ in`
- Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:164 `SpaceTitle.canDeleteSpace`: `tabManager.spaces.count > 1`
- Nook/Managers/BrowserManager/BrowserManager.swift:627 `BrowserManager.applyStartupLoadMode`: `let activeSpace = tabManager.currentSpace ?? tabManager.spaces.first`
- Nook/Managers/BrowserManager/BrowserManager.swift:948 `BrowserManager.createNewTab`: `tabManager.spaces.first(where: { $0.id == id })`
- Nook/Managers/BrowserManager/BrowserManager.swift:951 `BrowserManager.createNewTab`: `tabManager.spaces.first(where: { $0.profileId == pid })`
- Nook/Managers/BrowserManager/BrowserManager.swift:984 `BrowserManager.duplicateTab`: `tab.spaceId.flatMap { id in tabManager.spaces.first(where: { $0.id == id }) }`
- Nook/Managers/BrowserManager/BrowserManager.swift:985 `BrowserManager.duplicateTab`: `?? activeWindow?.currentSpaceId.flatMap { id in tabManager.spaces.first(where: { $0.id == ...`
- Nook/Managers/BrowserManager/BrowserManager.swift:1890 `BrowserManager.setupWindowState`: `let space = tabManager.spaces.first(where: { $0.id == spaceId })`
- Nook/Managers/BrowserManager/BrowserManager.swift:1973 `BrowserManager.selectTab`: `let space = tabManager.spaces.first(where: { $0.id == spaceId })`
- Nook/Managers/BrowserManager/BrowserManager.swift:2029 `BrowserManager.tabsForDisplay`: `tabManager.spaces.first(where: { $0.id == id })`
- Nook/Managers/BrowserManager/BrowserManager.swift:2193 `BrowserManager.validateWindowStates`: `if tabManager.spaces.first(where: { $0.id == currentSpaceId }) == nil {`
- Nook/Managers/BrowserManager/BrowserManager.swift:2194 `BrowserManager.validateWindowStates`: `windowState.currentSpaceId = tabManager.spaces.first?.id`
- Nook/Managers/BrowserManager/BrowserManager.swift:2205 `BrowserManager.validateWindowStates`: `let windowSpace = windowState.currentSpaceId.flatMap { id in tabManager.spaces.first(where...`
- Nook/Managers/BrowserManager/BrowserManager.swift:2222 `BrowserManager.validateWindowStates`: `windowState.currentSpaceId = tabManager.spaces.first?.id`
- Nook/Managers/BrowserManager/BrowserManager.swift:2227 `BrowserManager.validateWindowStates`: `let space = tabManager.spaces.first(where: { $0.id == spaceId })`
- Nook/Managers/BrowserManager/BrowserManager.swift:2255 `BrowserManager.importArcData`: `let createdSpace = self.tabManager.spaces.first(where: {`
- Nook/Managers/BrowserManager/BrowserManager.swift:2294 `BrowserManager.importArcData`: `url: topTab.url, in: self.tabManager.spaces.first!)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2302 `BrowserManager.importDiaData`: `guard let defaultSpace = self.tabManager.spaces.first else { return }`
- Nook/Managers/BrowserManager/BrowserManager.swift:2327 `BrowserManager.importSafariData`: `guard let defaultSpace = self.tabManager.spaces.first else { return }`
- Nook/Managers/BrowserManager/BrowserManager.swift:2425 `BrowserManager.selectNextSpaceInActiveWindow`: `let currentSpaceIndex = tabManager.spaces.firstIndex(where: { $0.id == currentSpaceId })`
- Nook/Managers/BrowserManager/BrowserManager.swift:2428 `BrowserManager.selectNextSpaceInActiveWindow`: `let nextIndex = (currentSpaceIndex + 1) % tabManager.spaces.count`
- Nook/Managers/BrowserManager/BrowserManager.swift:2429 `BrowserManager.selectNextSpaceInActiveWindow`: `if let nextSpace = tabManager.spaces[safe: nextIndex] {`
- Nook/Managers/BrowserManager/BrowserManager.swift:2438 `BrowserManager.selectPreviousSpaceInActiveWindow`: `let currentSpaceIndex = tabManager.spaces.firstIndex(where: { $0.id == currentSpaceId })`
- Nook/Managers/BrowserManager/BrowserManager.swift:2442 `BrowserManager.selectPreviousSpaceInActiveWindow`: `currentSpaceIndex > 0 ? currentSpaceIndex - 1 : tabManager.spaces.count - 1`
- Nook/Managers/BrowserManager/BrowserManager.swift:2443 `BrowserManager.selectPreviousSpaceInActiveWindow`: `if let previousSpace = tabManager.spaces[safe: previousIndex] {`
- Nook/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift:101 `ExternalMiniWindowManager.present`: `} else if let firstSpace = browserManager?.tabManager.spaces.first {`
- Nook/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift:131 `ExternalMiniWindowManager.adopt`: `let targetSpace = tabManager.currentSpace ?? tabManager.spaces.first`
- Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift:58 `SiteRoutingManager.applyRoute`: `guard let targetSpace = tabManager.spaces.first(where: { $0.id == rule.targetSpaceId }),`
- Nook/Models/BrowserWindowState.swift:128 `BrowserWindowState.currentSpace`: `return tabManager.spaces.first { $0.id == spaceId }`
- Nook/Models/Tab/Tab.swift:311 `Tab.isActiveInSpace`: `let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId })`
- Nook/Models/Tab/Tab.swift:647 `Tab.resolveProfile`: `let space = browserManager?.tabManager.spaces.first(where: { $0.id == sid })`
- Nook/Utils/WebKit/WebContextMenu.swift:386 `FocusableWKWebView.openLinkInNewTab`: `let space = browserManager.tabManager.spaces.first(where: { $0.id == owningTab?.spaceId })`

#### `allTabs` (38)
Use: find live tab by id or webView; iterate all live pages (unload, content blocker, wake). Replacement: `tabs.item(id)` for model; `tabs.session(for: itemID)`, `tabs.sessions` (live), `tabs.session(for webView:)`.

- App/AppDelegate.swift:104 `AppDelegate.handleSystemWake`: `for tab in manager.tabManager.allTabs() {`
- App/AppDelegate.swift:141 `AppDelegate.setupMouseButtonHandling`: `let tab = manager.tabManager.allTabs().first(where: { $0.id == hoveredId }),`
- Nook/Components/Browser/Window/SplitDropCaptureView.swift:80 `SplitDropCaptureView.performDragOperation`: `let all = bm.tabManager.allTabs()`
- Nook/Components/Browser/Window/TabCompositorView.swift:252 `TabCompositorManager.handleMemoryPressure`: `let allTabs = browserManager.tabManager.allTabs()`
- Nook/Components/Browser/Window/TabCompositorView.swift:303 `TabCompositorManager.handleAppDidResignActive`: `for tab in browserManager.tabManager.allTabs() where canUnloadInactiveTab(tab) {`
- Nook/Components/Browser/Window/TabCompositorView.swift:315 `TabCompositorManager.enforceMaxLoadedTabs`: `let allTabs = browserManager.tabManager.allTabs()`
- Nook/Components/Browser/Window/TabCompositorView.swift:360 `TabCompositorManager.findTab`: `return browserManager.tabManager.allTabs().first { $0.id == id }`
- Nook/Components/Browser/Window/TabCompositorView.swift:365 `TabCompositorManager.findTabByWebView`: `return browserManager.tabManager.allTabs().first { $0.webView === webView }`
- Nook/Components/Settings/Tabs/Profiles.swift:110 `ProfilesSettingsView.tabsCount`: `return browserManager.tabManager.allTabs().filter { tab in`
- Nook/Components/Sidebar/FallbackDropBelowEssentialsModifier.swift:19 `FallbackDropBelowEssentialsModifier.handleFallbackDrop`: `let allTabs = browserManager.tabManager.allTabs()`
- Nook/Components/Sidebar/MediaControls/MediaControlsView.swift:251 `MediaControlsView.updateMediaState`: `let refreshed = browserManager.tabManager.allTabs().first(where: { $0.id == current.id }) ...`
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift:173 `PinnedGrid.handleEssentialsDrop`: `let allTabs = tabManager.allTabs()`
- Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:99 `SpaceTitle.body`: `let allTabs = tabManager.allTabs()`
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:225 `SpaceView.handlePendingDrop`: `let allTabs = tabManager.allTabs()`
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:260 `SpaceView.handlePendingReorder`: `guard let tab = tabManager.allTabs().first(where: { $0.id == reorder.item.tabId }) else {`
- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift:74 `TabFolderView.handleFolderDrop`: `let allTabs = tabManager.allTabs()`
- Nook/Components/WebsiteView/WebsiteView.swift:633 `TabCompositorWrapper.updateCompositor`: `let allKnownTabs = browserManager.tabManager.allTabs()`
- Nook/Managers/BrowserManager/BrowserManager.swift:634 `BrowserManager.applyStartupLoadMode`: `return tabManager.tabById(tabId) ?? tabManager.allTabs().first(where: { $0.id == tabId })`
- Nook/Managers/BrowserManager/BrowserManager.swift:1941 `BrowserManager.currentTab`: `return tabManager.allTabs().first { $0.id == tabId }`
- Nook/Managers/BrowserManager/BrowserManager.swift:2097 `BrowserManager.createWebView`: `guard let tab = tabManager.allTabs().first(where: { $0.id == tabId }),`
- Nook/Managers/BrowserManager/BrowserManager.swift:2106 `BrowserManager.syncTabAcrossWindows`: `guard let tab = tabManager.allTabs().first(where: { $0.id == tabId }),`
- Nook/Managers/BrowserManager/BrowserManager.swift:2185 `BrowserManager.validateWindowStates`: `if tabManager.allTabs().first(where: { $0.id == currentTabId }) == nil {`
- Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift:80 `ContentBlockerManager.allowDomain`: `for tab in bm.tabManager.allTabs() {`
- Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift:205 `ContentBlockerManager.setDetailedCountsEnabled`: `browserManager?.tabManager.allTabs().forEach { $0.blockedRequestCount = 0 }`
- Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift:210 `ContentBlockerManager.setDetailedCountsEnabled`: `for tab in bm.tabManager.allTabs() {`
- Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift:370 `ContentBlockerManager.applyToExistingWebViews`: `for tab in bm.tabManager.allTabs() {`
- Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift:378 `ContentBlockerManager.removeFromExistingWebViews`: `for tab in bm.tabManager.allTabs() {`
- Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift:402 `ContentBlockerManager.tab`: `browserManager?.tabManager.allTabs().first { $0.existingWebView === webView }`
- Nook/Managers/MediaControlsManager/MediaControlsManager.swift:60 `MediaControlsManager.findActiveMediaTab`: `let allTabs = browserManager.tabManager.allTabs()`
- Nook/Managers/SplitViewManager/SplitViewManager.swift:165 `SplitViewManager.closePane`: `if let rightId = state.rightTabId, let rightTab = bm.tabManager.allTabs().first(where: { $...`
- Nook/Managers/SplitViewManager/SplitViewManager.swift:169 `SplitViewManager.closePane`: `if let leftId = state.leftTabId, let leftTab = bm.tabManager.allTabs().first(where: { $0.i...`
- Nook/Managers/SplitViewManager/SplitViewManager.swift:211 `SplitViewManager.resolveTab`: `return bm.tabManager.allTabs().first(where: { $0.id == id })`
- Nook/Managers/SplitViewManager/SplitViewManager.swift:291 `WindowSplitState.maybeDuplicateIfPinned`: `let opposite = oppositeId.flatMap { id in tm.allTabs().first(where: { $0.id == id }) }`
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift:211 `TabOrganizationApplier.undo`: `let allCurrentTabs = tabManager.allTabs()`
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift:219 `WebViewCoordinator.cleanupWindow`: `let allTabsMap = Dictionary(tabManager.allTabs().map { ($0.id, $0) }, uniquingKeysWith: { ...`
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift:246 `WebViewCoordinator.cleanupAllWebViews`: `let allTabsMap = Dictionary(tabManager.allTabs().map { ($0.id, $0) }, uniquingKeysWith: { ...`
- Nook/Models/Tab/Tab.swift:2822 `Tab.webView`: `if let parentTab = bm.tabManager.allTabs().first(where: { $0.id == parentTabId }) {`
- Nook/Models/Tab/Tab.swift:2960 `Tab.checkOAuthCompletion`: `if let parentTab = bm.tabManager.allTabs().first(where: { $0.id == parentTabId }) {`

#### `currentSpace` (25)
Use: global current space as fallback target for new tabs / menus. Replacement: no global: `windowState.spaceID` via `tabs.space(for: windowState)`.

- App/NookCommands.swift:191 `NookCommands.body`: `} ?? browserManager.tabManager.currentSpace`
- App/NookCommands.swift:204 `NookCommands.body`: `|| browserManager.tabManager.currentSpace == nil`
- App/NookCommands.swift:392 `NookCommands.body`: `.disabled(browserManager.tabManager.currentSpace == nil)`
- App/Window/WindowView.swift:31 `WindowView.body`: `.disabled(tabManager.currentSpace == nil)`
- App/Window/WindowView.swift:148 `WindowView.body`: `} ?? browserManager.tabManager.currentSpace`
- Navigation/Sidebar/SidebarBottomBar.swift:66 `SidebarBottomBar.newSpaceButton`: `if let currentSpace = tabManager.currentSpace {`
- Navigation/Sidebar/SpacesSideBarView.swift:236 `SpacesSideBarView.sidebarContextMenu`: `if let currentSpace = tabManager.currentSpace {`
- Navigation/Sidebar/SpacesSideBarView.swift:387 `SpacesSideBarView.resolveCurrentSpace`: `if let current = tabManager.currentSpace {`
- Nook/Managers/BrowserManager/BrowserManager.swift:552 `BrowserManager.init`: `if let g = self.tabManager.currentSpace?.gradient {`
- Nook/Managers/BrowserManager/BrowserManager.swift:627 `BrowserManager.applyStartupLoadMode`: `let activeSpace = tabManager.currentSpace ?? tabManager.spaces.first`
- Nook/Managers/BrowserManager/BrowserManager.swift:986 `BrowserManager.duplicateTab`: `?? tabManager.currentSpace`
- Nook/Managers/BrowserManager/BrowserManager.swift:1087 `BrowserManager.showSpaceSettings`: `guard let space = tabManager.currentSpace else {`
- Nook/Managers/BrowserManager/BrowserManager.swift:1885 `BrowserManager.setupWindowState`: `windowState.currentSpaceId = tabManager.currentSpace?.id`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:363 `ExtensionManager.webExtensionController`: `let space = bm.tabManager.currentSpace`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:383 `ExtensionManager.webExtensionController`: `let space = bm.tabManager.currentSpace`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:401 `ExtensionManager.webExtensionController`: `let space = bm.tabManager.currentSpace`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:446 `ExtensionManager.webExtensionController`: `in: bm.tabManager.currentSpace`
- Nook/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift:99 `ExternalMiniWindowManager.present`: `if let currentSpace = browserManager?.tabManager.currentSpace {`
- Nook/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift:131 `ExternalMiniWindowManager.adopt`: `let targetSpace = tabManager.currentSpace ?? tabManager.spaces.first`
- Nook/Managers/PeekManager/PeekManager.swift:94 `PeekManager.moveToSplitView`: `in: browserManager.tabManager.currentSpace,`
- Nook/Managers/PeekManager/PeekManager.swift:101 `PeekManager.moveToSplitView`: `in: browserManager.tabManager.currentSpace`
- Nook/Managers/PeekManager/PeekManager.swift:134 `PeekManager.moveToNewTab`: `in: browserManager.tabManager.currentSpace,`
- Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift:65 `SiteRoutingManager.applyRoute`: `if tabManager.currentSpace?.id == targetSpace.id {`
- Nook/Models/Tab/Tab.swift:2679 `Tab.handleCommandClick`: `bm.tabManager.createNewTab(url: url.absoluteString, in: bm.tabManager.currentSpace)`
- Nook/Models/Tab/Tab.swift:2873 `Tab.webView`: `newTab = bm.tabManager.createPopupTab(in: bm.tabManager.currentSpace)`

#### `createNewTab` (23)
Use: open URL as new tab in a space (imports, extensions, routing, context menu, history). Replacement: `tabs.open(url:in:placement:)` (window-scoped); imports use tree-level `tabs.createTab(url:title:in: Parent, after:)`.

- Nook/Components/Sidebar/Menu/SidebarMenuHistoryTab.swift:400 `SidebarMenuHistoryTab.openInCurrentTab`: `_ = browserManager.tabManager.createNewTab(url: url.absoluteString)`
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:684 `SpaceView.addTabToFolder`: `let newTab = tabManager.createNewTab(in: space)`
- Nook/Managers/BrowserManager/BrowserManager.swift:926 `BrowserManager.createNewTab`: `_ = tabManager.createNewTab()`
- Nook/Managers/BrowserManager/BrowserManager.swift:953 `BrowserManager.createNewTab`: `let newTab = tabManager.createNewTab(url: url, in: targetSpace)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2266 `BrowserManager.importArcData`: `self.tabManager.createNewTab(url: tab.url, in: createdSpace)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2273 `BrowserManager.importArcData`: `let newtab = self.tabManager.createNewTab(url: tab.url, in: createdSpace)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2284 `BrowserManager.importArcData`: `let newtab = self.tabManager.createNewTab(url: tab.url, in: createdSpace)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2293 `BrowserManager.importArcData`: `let tab = self.tabManager.createNewTab(`
- Nook/Managers/BrowserManager/BrowserManager.swift:2308 `BrowserManager.importDiaData`: `let newTab = self.tabManager.createNewTab(url: tab.url, in: defaultSpace)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2316 `BrowserManager.importDiaData`: `self.tabManager.createNewTab(url: tab.url, in: defaultSpace)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2334 `BrowserManager.importSafariData`: `let tab = self.tabManager.createNewTab(url: bookmark.url, in: defaultSpace)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2352 `BrowserManager.importSafariData`: `let tab = self.tabManager.createNewTab(url: bookmark.url, in: defaultSpace)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2358 `BrowserManager.importSafariData`: `self.tabManager.createNewTab(url: bookmark.url, in: defaultSpace)`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:364 `ExtensionManager.webExtensionController`: `let newTab = bm.tabManager.createNewTab(`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:384 `ExtensionManager.webExtensionController`: `let newTab = bm.tabManager.createNewTab(`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:402 `ExtensionManager.webExtensionController`: `let newTab = bm.tabManager.createNewTab(in: space)`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:444 `ExtensionManager.webExtensionController`: `let newTab = bm.tabManager.createNewTab(`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:461 `ExtensionManager.webExtensionController`: `_ = bm.tabManager.createNewTab(`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:466 `ExtensionManager.webExtensionController`: `_ = bm.tabManager.createNewTab(in: newSpace)`
- Nook/Managers/PeekManager/PeekManager.swift:99 `PeekManager.moveToSplitView`: `newTab = browserManager.tabManager.createNewTab(`
- Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift:79 `SiteRoutingManager.applyRoute`: `let _ = tabManager.createNewTab(url: url.absoluteString, in: targetSpace)`
- Nook/Models/Tab/Tab.swift:2679 `Tab.handleCommandClick`: `bm.tabManager.createNewTab(url: url.absoluteString, in: bm.tabManager.currentSpace)`
- Nook/Utils/WebKit/WebContextMenu.swift:387 `FocusableWKWebView.openLinkInNewTab`: `_ = browserManager.tabManager.createNewTab(url: url.absoluteString, in: space)`

#### `tabs` (14)
Use: `tabs(in: space)` regular tabs of a space (8); `tabs` property = current-space regular tabs (6, extensions + zoom lookup). Replacement: `tabs.tree.children(of: .tabs(spaceID:))` or `visibleRows`; zoom lookup -> `tabs.session(for:)`.

- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:87 `SpaceView.tabs`: `return tabManager.tabs(in: space)`
- Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift:418 `BrowserToolExecutor.executeGetTabList`: `let tabs = tabManager.tabs(in: space)`
- Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift:443 `BrowserToolExecutor.executeSwitchTab`: `let tabs = tabManager.tabs(in: space)`
- Nook/Managers/BrowserManager/BrowserManager.swift:636 `BrowserManager.applyStartupLoadMode`: `return activeSpace.flatMap { tabManager.tabs(in: $0).first }`
- Nook/Managers/BrowserManager/BrowserManager.swift:654 `BrowserManager.applyStartupLoadMode`: `warmTabs += tabManager.tabs(in: space)`
- Nook/Managers/BrowserManager/BrowserManager.swift:1001 `BrowserManager.duplicateTab`: `let sourcePosition = tabManager.tabs(in: targetSpace).filter({ $0.id != newTab.id }).first...`
- Nook/Managers/BrowserManager/BrowserManager.swift:2043 `BrowserManager.tabsForDisplay`: `let regularTabs = currentSpace.map { tabManager.tabs(in: $0) } ?? []`
- Nook/Managers/BrowserManager/BrowserManager.swift:2138 `BrowserManager.setActiveSpace`: `let regularTabs = tabManager.tabs(in: space)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2829 `BrowserManager.applyZoomLevel`: `let tab = tabManager.tabs.first(where: { $0.id == tabId })`
- Nook/Managers/BrowserManager/BrowserManager.swift:2842 `BrowserManager.loadZoomForTab`: `let tab = tabManager.tabs.first(where: { $0.id == tabId }),`
- Nook/Managers/ExtensionManager/ExtensionBridge.swift:59 `ExtensionWindowAdapter.activeTab`: `} else if let first = browserManager.tabManager.pinnedTabs.first ?? browserManager.tabMana...`
- Nook/Managers/ExtensionManager/ExtensionBridge.swift:73 `ExtensionWindowAdapter.tabs`: `let all = browserManager.tabManager.pinnedTabs + browserManager.tabManager.tabs`
- Nook/Managers/ExtensionManager/ExtensionManager+Installation.swift:371 `ExtensionManager.registerContext`: `for tab in bm.tabManager.pinnedTabs + bm.tabManager.tabs where openedTabIDs.contains(tab.i...`
- Nook/Managers/ExtensionManager/ExtensionManager.swift:203 `ExtensionManager.attach`: `+ browserManager.tabManager.tabs`

#### `currentTab` (9)
Use: global selected tab (history open-in-current, top bar color, startup, Tab.isCurrentTab). Replacement: `tabs.selectedItemID(in: windowState)` / `tabs.selectedSession(in:)`.

- Nook/Components/Sidebar/Menu/SidebarMenuHistoryTab.swift:397 `SidebarMenuHistoryTab.openInCurrentTab`: `if let currentTab = browserManager.tabManager.currentTab {`
- Nook/Components/Sidebar/TopBar/TopBarView.swift:560 `ChatButton.backgroundColor`: `let isDark = browserManager.tabManager.currentTab?.topBarBackgroundColor?.isPerceivedDark ...`
- Nook/Managers/BrowserManager/BrowserManager.swift:632 `BrowserManager.applyStartupLoadMode`: `if let tab = tabManager.currentTab { return tab }`
- Nook/Managers/BrowserManager/BrowserManager.swift:1413 `BrowserManager.currentTabForActiveWindow`: `return tabManager.currentTab`
- Nook/Managers/BrowserManager/BrowserManager.swift:1886 `BrowserManager.setupWindowState`: `windowState.currentTabId = tabManager.currentTab?.id`
- Nook/Managers/BrowserManager/BrowserManager.swift:2206 `BrowserManager.validateWindowStates`: `if let managerCurrentTab = tabManager.currentTab, !managerCurrentTab.isUnloaded,`
- Nook/Managers/SplitViewManager/SplitViewManager.swift:307 `WindowSplitState.maybeDuplicateIfPinned`: `let current = bm.currentTab(for: windowState) ?? tm.currentTab`
- Nook/Models/Tab/Tab.swift:305 `Tab.isCurrentTab`: `return browserManager?.tabManager.currentTab?.id == id`
- Nook/Models/Tab/Tab.swift:694 `Tab.closeTab`: `currentTabId: browserManager?.tabManager.currentTab?.id)`

#### `setActiveTab` (9)
Use: activate a tab (AI switch, extension activate/create, OAuth parent, popup). Replacement: `tabs.select(_ itemID:, in: windowState)`.

- Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift:449 `BrowserToolExecutor.executeSwitchTab`: `tabManager.setActiveTab(tab)`
- Nook/Managers/ExtensionManager/ExtensionBridge.swift:240 `ExtensionTabAdapter.activate`: `browserManager.tabManager.setActiveTab(tab)`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:374 `ExtensionManager.webExtensionController`: `bm.tabManager.setActiveTab(newTab)`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:390 `ExtensionManager.webExtensionController`: `bm.tabManager.setActiveTab(newTab)`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:403 `ExtensionManager.webExtensionController`: `if configuration.shouldBeActive { bm.tabManager.setActiveTab(newTab) }`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:448 `ExtensionManager.webExtensionController`: `bm.tabManager.setActiveTab(newTab)`
- Nook/Models/Tab/Tab.swift:1768 `Tab.activate`: `browserManager?.tabManager.setActiveTab(self)`
- Nook/Models/Tab/Tab.swift:2825 `Tab.webView`: `bm.tabManager.setActiveTab(parentTab)`
- Nook/Models/Tab/Tab.swift:2963 `Tab.checkOAuthCompletion`: `bm?.tabManager.setActiveTab(parentTab)`

#### `createEphemeralTab` (8)
Use: open tab in private window. Replacement: `tabs.open(url:in: privateWindow, placement:)` (private windows own in-memory items).

- Nook/Managers/BrowserManager/BrowserManager.swift:937 `BrowserManager.createNewTab`: `let newTab = tabManager.createEphemeralTab(`
- Nook/Managers/BrowserManager/BrowserManager.swift:977 `BrowserManager.duplicateTab`: `let copy = tabManager.createEphemeralTab(url: tab.url, in: window, profile: profile)`
- Nook/Managers/BrowserManager/BrowserManager.swift:1040 `BrowserManager.closeCurrentTab`: `let newTab = tabManager.createEphemeralTab(url: url, in: activeWindow, profile: profile)`
- Nook/Managers/PeekManager/PeekManager.swift:79 `PeekManager.moveToSplitView`: `let newTab = browserManager.tabManager.createEphemeralTab(url: session.currentURL, in: win...`
- Nook/Managers/PeekManager/PeekManager.swift:121 `PeekManager.moveToNewTab`: `let newTab = browserManager.tabManager.createEphemeralTab(url: session.currentURL, in: win...`
- Nook/Models/Tab/Tab.swift:2674 `Tab.handleCommandClick`: `_ = bm.tabManager.createEphemeralTab(url: url, in: window, profile: profile)`
- Nook/Models/Tab/Tab.swift:2868 `Tab.webView`: `newTab = bm.tabManager.createEphemeralTab(`
- Nook/Utils/WebKit/WebContextMenu.swift:382 `FocusableWKWebView.openLinkInNewTab`: `browserManager.tabManager.createEphemeralTab(url: url, in: window, profile: profile)`

#### `handleDragOperation` (8)
Use: commit sidebar drop (essentials, pinned, regular, folder, reorder). Replacement: `tabs.move(_:to:after:)` with `TabTree.dropTarget(section:rows:index:intoFolder:dragged:)`.

- Nook/Components/Sidebar/FallbackDropBelowEssentialsModifier.swift:23 `FallbackDropBelowEssentialsModifier.handleFallbackDrop`: `browserManager.tabManager.handleDragOperation(op)`
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift:180 `PinnedGrid.handleEssentialsDrop`: `tabManager.handleDragOperation(op)`
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift:197 `PinnedGrid.handleEssentialsReorder`: `tabManager.handleDragOperation(op)`
- Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:103 `SpaceTitle.body`: `tabManager.handleDragOperation(op)`
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:242 `SpaceView.handlePendingDrop`: `tabManager.handleDragOperation(op)`
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:279 `SpaceView.handlePendingReorder`: `tabManager.handleDragOperation(op)`
- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift:81 `TabFolderView.handleFolderDrop`: `tabManager.handleDragOperation(op)`
- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift:97 `TabFolderView.handleFolderReorder`: `tabManager.handleDragOperation(op)`

#### `persistSnapshot` (8)
Use: force save after rename/space edit/organizer/navigation. Replacement: delete (TabStore saves on every change); `tabs.flushSync()` only at quit.

- Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:28 `SpaceTitle.body`: `tabManager.persistSnapshot()`
- Nook/Managers/BrowserManager/BrowserManager.swift:1136 `BrowserManager.showSpaceSettings`: `self.tabManager.persistSnapshot()`
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift:177 `TabOrganizationApplier.apply`: `tabManager.persistSnapshot()`
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift:182 `TabOrganizationApplier.apply`: `tabManager.persistSnapshot()`
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift:247 `TabOrganizationApplier.undo`: `tabManager.persistSnapshot()`
- Nook/Models/Tab/Tab.swift:2164 `Tab.webView`: `self?.browserManager?.tabManager.persistSnapshot()`
- Nook/Models/Tab/Tab.swift:2167 `Tab.webView`: `self?.browserManager?.tabManager.persistSnapshot()`
- Nook/Models/Tab/Tab.swift:2584 `Tab.userContentController`: `self?.browserManager?.tabManager.persistSnapshot()`

#### `spacePinnedTabs` (8)
Use: space-pinned tabs of a space (render, counts, empty-state drop target). Replacement: `tabs.tree.children(of: .pinned(spaceID:))`.

- Nook/Components/Settings/Tabs/Profiles.swift:123 `ProfilesSettingsView.pinnedCount`: `total += browserManager.tabManager.spacePinnedTabs(for: sid).count`
- Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift:86 `SpaceContextMenu.showDeleteConfirmation`: `let spacePinnedTabsCount = tabManager.spacePinnedTabs(for: space.id).count`
- Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:98 `SpaceTitle.body`: `guard tabManager.spacePinnedTabs(for: space.id).isEmpty else { return }`
- Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:149 `SpaceTitle.isDropHovering`: `&& tabManager.spacePinnedTabs(for: space.id).isEmpty`
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:94 `SpaceView.spacePinnedTabs`: `return tabManager.spacePinnedTabs(for: space.id)`
- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift:34 `TabFolderView.tabsInFolder`: `let tabs = tabManager.spacePinnedTabs(for: space.id)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2042 `BrowserManager.tabsForDisplay`: `let spacePinned = currentSpace.map { tabManager.spacePinnedTabs(for: $0.id) } ?? []`
- Nook/Managers/BrowserManager/BrowserManager.swift:2137 `BrowserManager.setActiveSpace`: `let spacePinned = tabManager.spacePinnedTabs(for: space.id)`

#### `assign` (7)
Use: move space to a profile. Replacement: `tabs.moveSpace(_:toProfile:after:)`.

- Navigation/Sidebar/SpacesSideBarView.swift:362 `SpacesSideBarView.showSpaceCreationDialog`: `tabManager.assign(spaceId: newSpace.id, toProfile: profileId)`
- Nook/Components/Settings/Tabs/Profiles.swift:249 `ProfilesSettingsView.assignAllSpacesToCurrentProfile`: `browserManager.tabManager.assign(spaceId: sp.id, toProfile: pid)`
- Nook/Components/Settings/Tabs/Profiles.swift:259 `ProfilesSettingsView.resetAllSpaceAssignments`: `browserManager.tabManager.assign(`
- Nook/Components/Settings/Tabs/Profiles.swift:387 `SpaceAssignmentRowView.assign`: `browserManager.tabManager.assign(spaceId: space.id, toProfile: id)`
- Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift:32 `SpaceContextMenu.body`: `tabManager.assign(spaceId: space.id, toProfile: newProfileId)`
- Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:204 `SpaceTitle.assignProfile`: `tabManager.assign(spaceId: space.id, toProfile: id)`
- Nook/Managers/BrowserManager/BrowserManager.swift:1128 `BrowserManager.showSpaceSettings`: `self.tabManager.assign(spaceId: space.id, toProfile: profileId)`

#### `removeTab` (7)
Use: close tab. Replacement: `tabs.close(_ itemID:)`.

- Navigation/Sidebar/SpacesSideBarView.swift:328 `SpacesSideBarView.makeSpaceView`: `onCloseTab: { tabManager.removeTab($0.id) },`
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:277 `TabContextMenu.closeSection`: `tabManager.removeTab(tab.id)`
- Nook/Managers/BrowserManager/BrowserManager.swift:1047 `BrowserManager.closeCurrentTab`: `tabManager.removeTab(currentTab.id)`
- Nook/Managers/ExtensionManager/ExtensionBridge.swift:245 `ExtensionTabAdapter.close`: `browserManager.tabManager.removeTab(tab.id)`
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift:162 `TabOrganizationApplier.apply`: `tabManager.removeTab(tab.id)`
- Nook/Models/Tab/Tab.swift:706 `Tab.closeTab`: `browserManager?.tabManager.removeTab(self.id)`
- Nook/Models/Tab/Tab.swift:2972 `Tab.checkOAuthCompletion`: `bm.tabManager.removeTab(self.id)`

#### `moveTabToFolder` (6)
Use: put tab into folder (menu, new tab in folder, alphabetize, imports, organizer). Replacement: `tabs.move(_:to: .folder(itemID:), after:)`.

- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:96 `TabContextMenu.addToFolderMenu`: `tabManager.moveTabToFolder(tab: tab, folderId: folder.id)`
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:685 `SpaceView.addTabToFolder`: `tabManager.moveTabToFolder(tab: newTab, folderId: folder.id)`
- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift:281 `TabFolderView.alphabetizeTabs`: `tabManager.moveTabToFolder(tab: tab, folderId: folder.id, index: index)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2285 `BrowserManager.importArcData`: `self.tabManager.moveTabToFolder(tab: newtab, folderId: newFolder.id)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2353 `BrowserManager.importSafariData`: `self.tabManager.moveTabToFolder(tab: tab, folderId: newFolder.id)`
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift:120 `TabOrganizationApplier.apply`: `tabManager.moveTabToFolder(tab: tab, folderId: folder.id)`

#### `pinnedTabs` (6)
Use: essentials list for extension window tab enumeration. Replacement: `tabs.tree.favorites(of: profileID)`.

- Nook/Managers/ExtensionManager/ExtensionBridge.swift:59 `ExtensionWindowAdapter.activeTab`: `} else if let first = browserManager.tabManager.pinnedTabs.first ?? browserManager.tabMana...`
- Nook/Managers/ExtensionManager/ExtensionBridge.swift:73 `ExtensionWindowAdapter.tabs`: `let all = browserManager.tabManager.pinnedTabs + browserManager.tabManager.tabs`
- Nook/Managers/ExtensionManager/ExtensionBridge.swift:204 `ExtensionTabAdapter.indexInWindow`: `if browserManager.tabManager.pinnedTabs.contains(where: { $0.id == tab.id }) {`
- Nook/Managers/ExtensionManager/ExtensionBridge.swift:215 `ExtensionTabAdapter.isPinned`: `return browserManager.tabManager.pinnedTabs.contains(where: { $0.id == tab.id })`
- Nook/Managers/ExtensionManager/ExtensionManager+Installation.swift:371 `ExtensionManager.registerContext`: `for tab in bm.tabManager.pinnedTabs + bm.tabManager.tabs where openedTabIDs.contains(tab.i...`
- Nook/Managers/ExtensionManager/ExtensionManager.swift:202 `ExtensionManager.attach`: `browserManager.tabManager.pinnedTabs`

#### `createFolder` (5)
Use: create folder in space pinned section. Replacement: `tabs.createFolder(title:in: .pinned(spaceID:), after:)`.

- Navigation/Sidebar/SidebarBottomBar.swift:67 `SidebarBottomBar.newSpaceButton`: `tabManager.createFolder(for: currentSpace.id)`
- Navigation/Sidebar/SpacesSideBarView.swift:237 `SpacesSideBarView.sidebarContextMenu`: `tabManager.createFolder(for: currentSpace.id)`
- Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:200 `SpaceTitle.createFolder`: `tabManager.createFolder(for: space.id)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2280 `BrowserManager.importArcData`: `let newFolder = self.tabManager.createFolder(`
- Nook/Managers/BrowserManager/BrowserManager.swift:2350 `BrowserManager.importSafariData`: `let newFolder = self.tabManager.createFolder(for: defaultSpace.id, name: folderName)`

#### `essentialTabs` (5)
Use: essentials for a profile (grid, warm-up, display order, validation). Replacement: `tabs.tree.favorites(of: profileID)`.

- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift:32 `PinnedGrid.body`: `? tabManager.essentialTabs(for: effectiveProfileId)`
- Nook/Managers/BrowserManager/BrowserManager.swift:652 `BrowserManager.applyStartupLoadMode`: `warmTabs = tabManager.essentialTabs(for: windowState.currentProfileId)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2041 `BrowserManager.tabsForDisplay`: `let essentials = profileId.flatMap { tabManager.essentialTabs(for: $0) } ?? []`
- Nook/Managers/BrowserManager/BrowserManager.swift:2140 `BrowserManager.setActiveSpace`: `(space.profileId ?? currentProfile?.id).flatMap { tabManager.essentialTabs(for: $0) }`
- Nook/Managers/BrowserManager/BrowserManager.swift:2209 `BrowserManager.validateWindowStates`: `|| tabManager.essentialTabs(for: windowSpace.profileId).contains(where: { $0.id == manager...`

#### `browserManager` (4)
Use: back-reference wiring / profile id lookup via tab manager. Replacement: delete; SearchManager reads `browserManager.currentProfile` or `tabs` directly.

- Nook/Managers/BrowserManager/BrowserManager.swift:541 `BrowserManager.init`: `self.tabManager.browserManager = self`
- Nook/Managers/SearchManager/SearchManager.swift:64 `SearchManager.updateProfileContext`: `let pid = tabManager?.browserManager?.currentProfile?.id`
- Nook/Managers/SearchManager/SearchManager.swift:96 `SearchManager.searchSuggestions`: `self.tabManager?.browserManager?.currentProfile?.id == profile else { return }`
- Nook/Managers/SearchManager/SearchManager.swift:100 `SearchManager.searchSuggestions`: `self.tabManager?.browserManager?.currentProfile?.id == profile else { return }`

#### `debouncedPersistSnapshot` (4)
Use: save after rename / navigation. Replacement: delete (automatic).

- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:155 `TabContextMenu.editSection`: `tabManager.debouncedPersistSnapshot()`
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:221 `TabContextMenu.editSection`: `tabManager.debouncedPersistSnapshot()`
- Nook/Models/Tab/Tab.swift:831 `Tab.saveRename`: `browserManager?.tabManager.debouncedPersistSnapshot()`
- Nook/Models/Tab/Tab.swift:2282 `Tab.webView`: `browserManager?.tabManager.debouncedPersistSnapshot()`

#### `unloadTab` (4)
Use: compositor unload on timeout / memory pressure / resign active / budget. Replacement: `tabs.unload(_ itemID:)` or `session.unload()` gated by `tabs.isVisibleInAnyWindow(_:)`.

- Nook/Components/Browser/Window/TabCompositorView.swift:178 `TabCompositorManager.handleTabTimeout`: `browserManager?.tabManager.unloadTab(tab)`
- Nook/Components/Browser/Window/TabCompositorView.swift:273 `TabCompositorManager.handleMemoryPressure`: `browserManager.tabManager.unloadTab(tab)`
- Nook/Components/Browser/Window/TabCompositorView.swift:304 `TabCompositorManager.handleAppDidResignActive`: `browserManager.tabManager.unloadTab(tab)`
- Nook/Components/Browser/Window/TabCompositorView.swift:337 `TabCompositorManager.enforceMaxLoadedTabs`: `browserManager.tabManager.unloadTab(tab)`

#### `addToEssentials` (3)
Use: importers pin tab to favorites. Replacement: `tabs.move(_:to: .favorites(profileID:), after:)` or create directly in favorites.

- Nook/Managers/BrowserManager/BrowserManager.swift:2295 `BrowserManager.importArcData`: `self.tabManager.addToEssentials(tab)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2309 `BrowserManager.importDiaData`: `self.tabManager.addToEssentials(newTab)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2335 `BrowserManager.importSafariData`: `self.tabManager.addToEssentials(tab)`

#### `createNewTabWithWebView` (3)
Use: adopt existing WKWebView (Peek, mini window) as a tab. Replacement: `tabs.adopt(webView:url:title:in:placement:)` -> PageSession wrapping given view.

- Nook/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift:136 `ExternalMiniWindowManager.adopt`: `let newTab = tabManager.createNewTabWithWebView(`
- Nook/Managers/PeekManager/PeekManager.swift:92 `PeekManager.moveToSplitView`: `newTab = browserManager.tabManager.createNewTabWithWebView(`
- Nook/Managers/PeekManager/PeekManager.swift:132 `PeekManager.moveToNewTab`: `let newTab = browserManager.tabManager.createNewTabWithWebView(`

#### `createSpace` (3)
Use: create space (sidebar dialog, Arc import, extension windows.create). Replacement: `tabs.createSpace(profileID:name:icon:accentHex:after:)`.

- Navigation/Sidebar/SpacesSideBarView.swift:354 `SpacesSideBarView.showSpaceCreationDialog`: `let newSpace = tabManager.createSpace(`
- Nook/Managers/BrowserManager/BrowserManager.swift:2252 `BrowserManager.importArcData`: `self.tabManager.createSpace(name: space.title, icon: space.emoji ?? "person.fill")`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:459 `ExtensionManager.webExtensionController`: `let newSpace = bm.tabManager.createSpace(name: "Window")`

#### `folders` (3)
Use: folders of a space (menu, sidebar, organizer names). Replacement: `tabs.tree.children(of:)` filtered `isFolder`.

- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:90 `TabContextMenu.addToFolderMenu`: `let folders = tabManager.folders(for: spaceId)`
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:102 `SpaceView.folders`: `return tabManager.folders(for: space.id).filter { !$0.isRegular }`
- Nook/Managers/TabOrganizerManager/TabOrganizerManager.swift:112 `TabOrganizerManager.organizeTabs`: `let existingFolderNames = tabManager.folders(for: space.id).map(\.name)`

#### `forceRemoveTab` (3)
Use: close pinned/essential tab bypassing guard. Replacement: `tabs.close(_:)` (pinned close ends session per spec).

- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:275 `TabContextMenu.closeSection`: `tabManager.forceRemoveTab(tab.id)`
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:471 `SpaceView.pinnedTabView`: `onClose: { tabManager.forceRemoveTab(tab.id) },`
- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift:252 `TabFolderView.folderTabView`: `onClose: { tabManager.forceRemoveTab(tab.id) },`

#### `pinTab` (3)
Use: pin to essentials (context menu, extensions). Replacement: `tabs.pin(_:to: .favorites(profileID:))`.

- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:72 `TabContextMenu.placementSection`: `tabManager.pinTab(tab)`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:372 `ExtensionManager.webExtensionController`: `if configuration.shouldBePinned { bm.tabManager.pinTab(newTab) }`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:388 `ExtensionManager.webExtensionController`: `if configuration.shouldBePinned { bm.tabManager.pinTab(newTab) }`

#### `removeSpace` (3)
Use: delete space. Replacement: `tabs.deleteSpace(_:)`.

- Navigation/Sidebar/SpacesList/SpacesListItem.swift:67 `SpacesListItem.body`: `onDeleteSpace: { tabManager.removeSpace(space.id) }`
- Nook/Components/Settings/Tabs/Profiles.swift:365 `SpaceAssignmentRowView.body`: `browserManager.tabManager.removeSpace(space.id)`
- Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:196 `SpaceTitle.deleteSpace`: `tabManager.removeSpace(space.id)`

#### `setActiveSpace` (3)
Use: switch active space globally. Replacement: `tabs.setSpace(_ spaceID:, in: windowState)`.

- Nook/Managers/BrowserManager/BrowserManager.swift:2128 `BrowserManager.setActiveSpace`: `tabManager.setActiveSpace(space)`
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift:468 `ExtensionManager.webExtensionController`: `bm.tabManager.setActiveSpace(newSpace)`
- Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift:78 `SiteRoutingManager.applyRoute`: `tabManager.setActiveSpace(targetSpace)`

#### `tabsBySpace` (3)
Use: regular tab count / hasOtherTabs. Replacement: `tabs.tree.children(of: .tabs(spaceID:)).count`.

- Nook/Components/Settings/Tabs/Profiles.swift:368 `SpaceAssignmentRowView.body`: `let tabCount = (browserManager.tabManager.tabsBySpace[space.id]?.count ?? 0)`
- Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift:85 `SpaceContextMenu.showDeleteConfirmation`: `let regularTabsCount = tabManager.tabsBySpace[space.id]?.count ?? 0`
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:285 `TabContextMenu.closeSection`: `let hasOtherTabs = (tabManager.tabsBySpace[spaceId]?.filter { $0.id != tab.id }.isEmpty ==...`

#### `addTab` (2)
Use: insert prebuilt Tab (duplicate, organizer undo). Replacement: `tabs.open(url:...)` / `TabTree.apply(change)` for undo.

- Nook/Managers/BrowserManager/BrowserManager.swift:997 `BrowserManager.duplicateTab`: `tabManager.addTab(newTab)`
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift:242 `TabOrganizationApplier.undo`: `tabManager.addTab(tab)`

#### `deleteFolder` (2)
Use: delete folder (sidebar, organizer undo). Replacement: `tabs.close(folderID)`.

- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:679 `SpaceView.deleteFolder`: `tabManager.deleteFolder(folder.id)`
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift:206 `TabOrganizationApplier.undo`: `tabManager.deleteFolder(folderId)`

#### `pinTabToSpace` (2)
Use: pin to space (menu, Arc import). Replacement: `tabs.pin(_:to: .pinned(spaceID:))`.

- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:50 `TabContextMenu.placementSection`: `tabManager.pinTabToSpace(tab, spaceId: spaceId)`
- Nook/Managers/BrowserManager/BrowserManager.swift:2274 `BrowserManager.importArcData`: `self.tabManager.pinTabToSpace(newtab, spaceId: createdSpace.id)`

#### `regularFolders` (2)
Use: folders in tabs section. Replacement: `tabs.tree.children(of: .tabs(spaceID:))` folders.

- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:118 `SpaceView.regularFolderRows`: `return tabManager.regularFolders(for: space.id).reduce(0) { $0 + rowCount(of: $1, tabs: ta...`
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:612 `SpaceView.regularTabsView`: `let regFolders = tabManager.regularFolders(for: space.id)`

#### `renameSpace` (2)
Use: rename space. Replacement: `tabs.updateSpace(_:name:)`.

- Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:184 `SpaceTitle.commitRename`: `try tabManager.renameSpace(`
- Nook/Managers/BrowserManager/BrowserManager.swift:1125 `BrowserManager.showSpaceSettings`: `try self.tabManager.renameSpace(spaceId: space.id, newName: newName)`

#### `tabById` (2)
Use: startup: restore last active tab. Replacement: `tabs.tree.item(_:)`.

- Nook/Managers/BrowserManager/BrowserManager.swift:634 `BrowserManager.applyStartupLoadMode`: `return tabManager.tabById(tabId) ?? tabManager.allTabs().first(where: { $0.id == tabId })`
- Nook/Managers/BrowserManager/BrowserManager.swift:670 `BrowserManager.applyStartupLoadMode`: `let tab = self.tabManager.tabById(id) else { return }`

#### `unloadAllInactiveTabs` (2)
Use: settings / menu: unload hidden pages. Replacement: `tabs.unloadAllHidden()`.

- Nook/Components/Settings/Tabs/General.swift:46 `SettingsGeneralTab.body`: `tabManager.unloadAllInactiveTabs()`
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:261 `TabContextMenu.stateSection`: `tabManager.unloadAllInactiveTabs()`

#### `unloadTabMovingSelection` (2)
Use: unload current tab and select neighbor. Replacement: `tabs.unload(_:)` + `tabs.select(neighbor, in:)`.

- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:253 `TabContextMenu.stateSection`: `tabManager.unloadTabMovingSelection(tab)`
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:472 `SpaceView.pinnedTabView`: `onUnload: { tabManager.unloadTabMovingSelection(tab) },`

#### `unpinTab` (2)
Use: remove from essentials. Replacement: `tabs.unpin(_:)`.

- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:66 `TabContextMenu.placementSection`: `tabManager.unpinTab(tab)`
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift:157 `TabOrganizationApplier.apply`: `tabManager.unpinTab(tab)`

#### `unpinTabFromSpace` (2)
Use: remove from space pinned. Replacement: `tabs.unpin(_:)`.

- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:58 `TabContextMenu.placementSection`: `tabManager.unpinTabFromSpace(tab)`
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift:159 `TabOrganizationApplier.apply`: `tabManager.unpinTabFromSpace(tab)`

#### `allTabsForCurrentProfile` (1)
Use: command palette tab search. Replacement: `tabs.items(inProfile:)` + open sessions.

- Nook/Managers/SearchManager/SearchManager.swift:112 `SearchManager.searchTabs`: `let allTabs: [Tab] = tabManager.allTabsForCurrentProfile()`

#### `cleanupProfileReferences` (1)
Use: profile deleted. Replacement: `tabs.deleteProfile(_:heir:)`.

- Nook/Managers/BrowserManager/BrowserManager.swift:1827 `BrowserManager.deleteProfile`: `self.tabManager.cleanupProfileReferences(profile.id)`

#### `clearRegularTabs` (1)
Use: "clear" button in tabs section. Replacement: `tabs.close(ids)` for `.tabs(spaceID:)` children.

- Nook/Components/Sidebar/SpaceSection/SpaceView.swift:525 `SpaceView.newTabButtonSectionWithClear`: `tabManager.clearRegularTabs(for: space.id)`

#### `closeActiveTab` (1)
Use: Cmd+W fallback. Replacement: `tabs.close(selected)` via window selection.

- Nook/Managers/BrowserManager/BrowserManager.swift:1051 `BrowserManager.closeCurrentTab`: `tabManager.closeActiveTab()`

#### `closeAllTabsBelow` (1)
Use: context menu. Replacement: `tabs.close(ids)`.

- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:299 `TabContextMenu.closeSection`: `tabManager.closeAllTabsBelow(tab)`

#### `closeOtherTabs` (1)
Use: context menu. Replacement: `tabs.close(ids)`.

- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:289 `TabContextMenu.closeSection`: `tabManager.closeOtherTabs(tab)`

#### `createPopupTab` (1)
Use: WKUIDelegate createWebViewWith popup. Replacement: `tabs.adopt(webView:...)` / `tabs.openPopup(configuration:from:)`.

- Nook/Models/Tab/Tab.swift:2873 `Tab.webView`: `newTab = bm.tabManager.createPopupTab(in: bm.tabManager.currentSpace)`

#### `createRegularFolder` (1)
Use: organizer creates folder in tabs section. Replacement: `tabs.createFolder(title:in: .tabs(spaceID:), after:)`.

- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift:114 `TabOrganizationApplier.apply`: `let folder = tabManager.createRegularFolder(for: spaceId, name: group.name)`

#### `duplicateAsRegularForSplit` (1)
Use: split with pinned tab duplicates it. Replacement: `tabs.duplicate(_:placement:)`.

- Nook/Managers/SplitViewManager/SplitViewManager.swift:284 `WindowSplitState.maybeDuplicateIfPinned`: `return tm.duplicateAsRegularForSplit(from: candidate, anchor: anchor, placeAfterAnchor: tr...`

#### `handleProfileSwitch` (1)
Use: profile switch side effects. Replacement: delete / fold into window profile change.

- Nook/Managers/BrowserManager/BrowserManager.swift:766 `BrowserManager.switchToProfile`: `self.tabManager.handleProfileSwitch()`

#### `isGlobalPinned` (1)
Use: split: is candidate an essential. Replacement: `tabs.tree.section(of:)` == `.favorites`.

- Nook/Managers/SplitViewManager/SplitViewManager.swift:283 `WindowSplitState.maybeDuplicateIfPinned`: `if tm.isGlobalPinned(candidate) || tm.isSpacePinned(candidate) {`

#### `isSpacePinned` (1)
Use: split: is candidate space-pinned. Replacement: `tabs.tree.section(of:)` == `.pinned`.

- Nook/Managers/SplitViewManager/SplitViewManager.swift:283 `WindowSplitState.maybeDuplicateIfPinned`: `if tm.isGlobalPinned(candidate) || tm.isSpacePinned(candidate) {`

#### `looseTabs` (1)
Use: organizer inputs. Replacement: `tabs.tree.children(of: .tabs(spaceID:))`.

- Nook/Managers/TabOrganizerManager/TabOrganizerManager.swift:82 `TabOrganizerManager.organizeTabs`: `let tabs = tabManager.looseTabs(in: space)`

#### `moveTab` (1)
Use: move to another space. Replacement: `tabs.move(_:to: .tabs(spaceID:), after:)`.

- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift:114 `TabContextMenu.moveToSpaceMenu`: `tabManager.moveTab(tab.id, to: space.id)`

#### `nookSettings` (1)
Use: wiring. Replacement: delete (controller init param).

- App/NookApp.swift:137 `NookApp.setupApplicationLifecycle`: `browserManager.tabManager.nookSettings = settingsManager`

#### `persistFinalSnapshotBlocking` (1)
Use: quit flush. Replacement: `tabs.flushSync()`.

- App/AppDelegate.swift:189 `AppDelegate.applicationShouldTerminate`: `manager.tabManager.persistFinalSnapshotBlocking()`

#### `reattachBrowserManager` (1)
Use: init wiring. Replacement: delete.

- Nook/Managers/BrowserManager/BrowserManager.swift:542 `BrowserManager.init`: `self.tabManager.reattachBrowserManager(self)`

#### `regularFolderTabs` (1)
Use: tabs inside a tabs-section folder. Replacement: `tabs.tree.children(of: .folder(itemID:))`.

- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift:32 `TabFolderView.tabsInFolder`: `return tabManager.regularFolderTabs(for: space.id, folderId: folder.id)`

#### `renameFolder` (1)
Use: rename folder. Replacement: `tabs.rename(_:_:)`.

- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift:302 `TabFolderView.commitRename`: `tabManager.renameFolder(folder.id, newName: newName)`

#### `reorderRegular` (1)
Use: BrowserManager duplicate places copy. Replacement: `tabs.move(_:to:after:)`.

- Nook/Managers/BrowserManager/BrowserManager.swift:1002 `BrowserManager.duplicateTab`: `tabManager.reorderRegular(newTab, in: targetSpace.id, to: sourcePosition + 1)`

#### `toggleFolder` (1)
Use: expand/collapse. Replacement: `tabs.toggleFolder(_:)` (DeviceState.openFolders).

- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift:105 `TabFolderView.folderHeader`: `tabManager.toggleFolder(folder.id)`

#### `undoCloseTab` (1)
Use: Cmd+Shift+T. Replacement: `tabs.reopenLastClosed(in:)`.

- Nook/Managers/BrowserManager/BrowserManager.swift:2698 `BrowserManager.undoCloseTab`: `tabManager.undoCloseTab()`

#### `updateActiveTabState` (1)
Use: BrowserManager selection sync. Replacement: delete.

- Nook/Managers/BrowserManager/BrowserManager.swift:2012 `BrowserManager.selectTab`: `tabManager.updateActiveTabState(tab)`

#### `updateSpaceIcon` (1)
Use: space icon edit. Replacement: `tabs.updateSpace(_:icon:)`.

- Nook/Managers/BrowserManager/BrowserManager.swift:1122 `BrowserManager.showSpaceSettings`: `try self.tabManager.updateSpaceIcon(spaceId: space.id, icon: newIcon)`

#### `updateTabNavigationState` (1)
Use: Tab.swift after navigation. Replacement: `PageSession` calls `tabs.setURL` / `setPageTitle`.

- Nook/Models/Tab/Tab.swift:421 `Tab.updateNavigationState`: `browserManager?.tabManager.updateTabNavigationState(self)`

#### `validateTabProfileAssignments` (1)
Use: startup validation. Replacement: delete (TabTree.repair on load).

- Nook/Managers/BrowserManager/BrowserManager.swift:1750 `BrowserManager.validateProfileIntegrity`: `tabManager.validateTabProfileAssignments()`

## 2. Tab members used outside Tab.swift (and outside TabManager.swift)

Line lists per member. Tab.swift's own outbound calls (useful for PageSession): `windowRegistry?.activeWindow` 6, `getWebView` 5, `tabManager.setActiveTab` 3, `tabManager.persistSnapshot` 3, `syncTabAcrossWindows` 3, `profileManager.profiles` 3, `keyboardShortcutManager?.websiteShortcutDetector` 3, `ExtensionManager.shared` 16, `siteRoutingManager.applyRoute` 2, `peekManager.presentExternalURL` 2, `downloadManager.addDownload` 2, `incognitoWindow` 2, `tabManager.createEphemeralTab/currentTab/currentSpace/spaces/allTabs/removeTab/debouncedPersistSnapshot` 2 each, `historyManager.addVisit` 1, `externalMiniWindowManager.present` 1, `contentBlockerManager.strippedTrackingParams/setupContentBlockerScripts` 1 each, `compositorManager.updateTabVisibility/unloadTab` 1 each, `authenticationManager.handleAuthenticationChallenge` 1, `loadZoomForTab/cleanupZoomForTab/setMuteState/selectTab/currentTabForActiveWindow` 1 each.

Destination: 2(a) fields become `Item` / `Row` reads (`item.url` home or last URL, `displayTitle`, `customTitle`, `parent`, `order`) or `TabTree` queries (`section(of:)`, `spaceID(of:)`, `profileID(of:)`); `favicon` moves to a favicon cache keyed by host. 2(b) becomes `PageSession`. 2(c) splits: rename state goes to row view state, favicon statics to a `FaviconCache` type, `resolveProfile`/`isOAuthFlow` to PageSession, `resetToPinnedURL` to `TabsController.resetToHome`.

### 2(a) Model / placement fields: 382 call sites

| Member | Sites | Files |
|---|---|---|
| `id` | 188 | 33 |
| `url` | 68 | 27 |
| `name` | 27 | 14 |
| `displayName` | 10 | 7 |
| `displayNameOverride` | 7 | 2 |
| `spaceId` | 18 | 7 |
| `index` | 10 | 4 |
| `profileId` | 0 | 0 |
| `folderId` | 13 | 4 |
| `isPinned` | 13 | 4 |
| `isSpacePinned` | 12 | 4 |
| `pinnedURL` | 4 | 3 |
| `favicon` | 9 | 8 |
| `hasNavigatedAwayFromPinnedURL` | 1 | 1 |
| `isEphemeral` | 2 | 2 |

#### `id` (188)
- App/AppDelegate.swift: 141, 151, 160
- Nook/Components/Browser/Window/SplitDropCaptureView.swift: 102
- Nook/Components/Browser/Window/TabCompositorView.swift: 27, 42, 47, 115, 116, 117, 123, 188, 202, 208, 219, 327, 344, 360
- Nook/Components/Extensions/ExtensionLibraryButton.swift: 32
- Nook/Components/Extensions/ExtensionLibraryView.swift: 243, 248
- Nook/Components/Navigation/NavigationHistoryContextMenu.swift: 66, 78, 111
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 114, 275, 277, 285
- Nook/Components/Sidebar/FallbackDropBelowEssentialsModifier.swift: 20
- Nook/Components/Sidebar/MediaControls/MediaControlsView.swift: 251, 252, 261, 271
- Nook/Components/Sidebar/NavButtonsView.swift: 26, 36, 63, 202, 213, 222
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift: 100, 102, 110, 126, 174
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 165
- Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift: 100
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift: 226, 260, 462, 471, 477, 481, 484, 563, 564, 643, 656, 660, 663, 752, 797, 805
- Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift: 58, 115, 126
- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift: 75, 88, 240, 252, 258
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 103, 105, 258, 271, 287
- Nook/Components/WebsiteView/PageLoadingProgressBar.swift: 42
- Nook/Components/WebsiteView/WebsiteView.swift: 514, 560, 593, 635, 645, 826, 837
- Nook/Managers/AIManager/AIService.swift: 364
- Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift: 95, 425
- Nook/Managers/BrowserManager/BrowserManager.swift: 443, 634, 640, 658, 704, 709, 962, 1001, 1028, 1047, 1240, 1886, 1937, 1941, 1957, 1960, 1969, 1988, 2053, 2092, 2097, 2106, 2149, 2185, 2209, 2210, 2379, 2393, 2773, 2779, 2787, 2793, 2801, 2807, 2826, 2829, 2842
- Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift: 63, 67, 68, 93
- Nook/Managers/ExtensionManager/ExtensionBridge.swift: 184, 188, 200, 204, 215, 245
- Nook/Managers/ExtensionManager/ExtensionManager+Installation.swift: 371
- Nook/Managers/ExtensionManager/ExtensionManager+TabNotifications.swift: 20, 27, 40, 43, 50, 116, 117
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 438, 447
- Nook/Managers/MediaControlsManager/MediaControlsManager.swift: 100, 105, 294
- Nook/Managers/PeekManager/PeekManager.swift: 38
- Nook/Managers/SearchManager/SearchManager.swift: 42
- Nook/Managers/SplitViewManager/SplitViewManager.swift: 165, 169, 211, 308
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift: 75, 144, 162, 163, 212
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 91, 128, 135, 146, 201, 219, 246, 266, 267

#### `url` (68)
- App/NookCommands.swift: 149, 276, 303
- CommandPalette/CommandPaletteView.swift: 516
- Nook/Components/Extensions/ExtensionActionView.swift: 91
- Nook/Components/Extensions/ExtensionLibraryMoreMenu.swift: 133
- Nook/Components/Extensions/ExtensionLibraryView.swift: 26, 56, 202, 243, 248
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 169, 175
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift: 110, 119, 226
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift: 462, 643
- Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift: 58
- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift: 240
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 207, 448
- Nook/Components/Sidebar/URLBarView.swift: 49, 56, 135, 138, 139, 141
- Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift: 424
- Nook/Managers/BrowserManager/BrowserManager.swift: 977, 990, 1199, 1223, 1234, 1453, 2109, 2266, 2273, 2284, 2294, 2308, 2316, 2778, 2792, 2806, 2834, 2843
- Nook/Managers/DialogManager/Dialogs/EditPinnedURLDialog.swift: 25
- Nook/Managers/ExtensionManager/ExtensionBridge.swift: 192
- Nook/Managers/ExtensionManager/ExtensionManager+Installation.swift: 372
- Nook/Managers/ExtensionManager/ExtensionManager+TabNotifications.swift: 106
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 509
- Nook/Managers/MediaControlsManager/MediaControlsManager.swift: 49, 63
- Nook/Managers/PeekManager/PeekManager.swift: 39
- Nook/Managers/SearchManager/SearchManager.swift: 116, 117
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift: 145
- Nook/Managers/TabOrganizerManager/TabOrganizationPrompt.swift: 120
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 180
- Nook/Utils/WebKit/FocusableWKWebView.swift: 193, 197, 233
- Nook/Utils/WebKit/WebContextMenu.swift: 319

#### `name` (27)
- CommandPalette/CommandPalette Accessories/TabSuggestionItem.swift: 32
- Nook/Components/Extensions/ExtensionActionView.swift: 153, 157
- Nook/Components/Extensions/ExtensionLibraryView.swift: 64
- Nook/Components/Sidebar/MediaControls/MediaControlsView.swift: 16
- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift: 276
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 449
- Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift: 423, 450
- Nook/Managers/BrowserManager/BrowserManager.swift: 991, 2006, 2053, 2173, 2213
- Nook/Managers/ExtensionManager/ExtensionBridge.swift: 196
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift: 392, 404
- Nook/Managers/ExtensionManager/ExtensionManager+TabNotifications.swift: 28
- Nook/Managers/MediaControlsManager/MediaControlsManager.swift: 82
- Nook/Managers/SearchManager/SearchManager.swift: 115, 121, 131, 132, 139
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift: 146

#### `displayName` (10)
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift: 225
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 83, 89
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift: 462, 643
- Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift: 58, 72
- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift: 240
- Nook/Managers/DialogManager/Dialogs/EditPinnedURLDialog.swift: 26
- Nook/Managers/TabOrganizerManager/TabOrganizationPrompt.swift: 119

#### `displayNameOverride` (7)
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 152, 154
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift: 81, 130, 152, 225, 240

#### `spaceId` (18)
- Nook/Components/Settings/Tabs/Profiles.swift: 111
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 48, 89, 118, 284, 297
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift: 745, 763, 787
- Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift: 60
- Nook/Managers/BrowserManager/BrowserManager.swift: 984, 1000, 1963, 2208
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift: 76, 147, 220
- Nook/Utils/WebKit/WebContextMenu.swift: 386

#### `index` (10)
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift: 85, 166
- Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift: 61
- Nook/Managers/ExtensionManager/ExtensionBridge.swift: 207
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift: 78, 149, 174, 222

#### `folderId` (13)
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift: 109, 152, 454, 536, 626, 638
- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift: 35
- Nook/Managers/BrowserManager/BrowserManager.swift: 1000, 2053
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift: 77, 148, 221, 239

#### `isPinned` (13)
- Nook/Components/Browser/Window/TabCompositorView.swift: 162, 193, 217, 319
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 70, 287, 297
- Nook/Managers/BrowserManager/BrowserManager.swift: 1000
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift: 79, 150, 156, 223, 237

#### `isSpacePinned` (12)
- Nook/Components/Browser/Window/TabCompositorView.swift: 162, 193, 217, 319
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 287, 297
- Nook/Managers/BrowserManager/BrowserManager.swift: 1000
- Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift: 80, 151, 158, 224, 238

#### `pinnedURL` (4)
- App/AppDelegate.swift: 142
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 212, 218
- Nook/Managers/DialogManager/Dialogs/EditPinnedURLDialog.swift: 25

#### `favicon` (9)
- CommandPalette/CommandPalette Accessories/TabSuggestionItem.swift: 21
- CommandPalette/CommandPaletteView.swift: 544
- Nook/Components/DragDrop/NookDragPreviewWindow.swift: 223, 255
- Nook/Components/Sidebar/MediaControls/MediaControlsView.swift: 78
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift: 120
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 49
- Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift: 67
- Nook/Managers/DialogManager/Dialogs/EditPinnedURLDialog.swift: 27

#### `hasNavigatedAwayFromPinnedURL` (1)
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 204

#### `isEphemeral` (2)
- Nook/Managers/BrowserManager/BrowserManager.swift: 2628
- Nook/Managers/ExtensionManager/ExtensionManager+TabNotifications.swift: 34

### 2(b) Live-page members (webview, navigation, media, find, PiP, loading, theme, webview pool): 203 call sites

| Member | Sites | Files |
|---|---|---|
| `activate` | 2 | 1 |
| `activeWebView` | 3 | 2 |
| `applyWebViewConfigurationOverride` | 1 | 1 |
| `assignWebViewToWindow` | 4 | 2 |
| `assignedWebView` | 5 | 3 |
| `blockedRequestCount` | 4 | 2 |
| `canGoBack` | 1 | 1 |
| `canGoForward` | 1 | 1 |
| `checkMediaState` | 1 | 1 |
| `cleanupCloneWebView` | 4 | 1 |
| `clearFindInPage` | 2 | 1 |
| `configureTabWebView` | 1 | 1 |
| `deliverContextMenuPayload` | 2 | 1 |
| `didNotifyOpenToExtensions` | 0 | 0 |
| `existingWebView` | 18 | 6 |
| `findInPage` | 1 | 1 |
| `findNextInPage` | 1 | 1 |
| `findPreviousInPage` | 1 | 1 |
| `finishIdentityFlow` | 5 | 1 |
| `goBack` | 2 | 2 |
| `goForward` | 2 | 2 |
| `hasAssignedPrimaryWebView` | 0 | 0 |
| `hasAudioContent` | 5 | 4 |
| `hasPiPActive` | 11 | 4 |
| `hasPlayingAudio` | 11 | 5 |
| `hasPlayingVideo` | 9 | 3 |
| `hasVideoContent` | 3 | 3 |
| `isAudioMuted` | 15 | 8 |
| `isLoading` | 5 | 3 |
| `isOptionKeyDown` | 2 | 1 |
| `isUnloaded` | 16 | 7 |
| `lastWebProcessCrashDate` | 1 | 1 |
| `loadPage` | 2 | 1 |
| `loadURL` | 6 | 5 |
| `loadWebViewIfNeeded` | 3 | 3 |
| `loadingState` | 3 | 3 |
| `navigateToURL` | 1 | 1 |
| `onCommandHover` | 1 | 1 |
| `onLinkHover` | 1 | 1 |
| `pageBackgroundColor` | 6 | 1 |
| `pause` | 0 | 0 |
| `pendingContextMenuPayload` | 4 | 1 |
| `performComprehensiveWebViewCleanup` | 2 | 1 |
| `primaryWindowId` | 0 | 0 |
| `refresh` | 3 | 3 |
| `removeNavigationStateObservers` | 0 | 0 |
| `removeThemeColorObserver` | 0 | 0 |
| `requestPictureInPicture` | 3 | 3 |
| `restoredCanGoBack` | 0 | 0 |
| `restoredCanGoForward` | 0 | 0 |
| `setMuted` | 1 | 1 |
| `setupNavigationStateObservers` | 1 | 1 |
| `setupThemeColorObserver` | 1 | 1 |
| `stop` | 2 | 2 |
| `toggleMute` | 5 | 5 |
| `topBarBackgroundColor` | 6 | 1 |
| `unloadWebView` | 3 | 2 |
| `updateNavigationStateEnhanced` | 0 | 0 |
| `updateTitle` | 1 | 1 |
| `webProcessCrashCount` | 1 | 1 |
| `webView` | 8 | 5 |
| `webViewWebContentProcessDidTerminate` | 0 | 0 |

#### `activate` (2)
- Nook/Utils/WebKit/FocusableWKWebView.swift: 31, 40

#### `activeWebView` (3)
- Nook/Managers/AuthenticationManager/AuthenticationManager.swift: 186, 218
- Nook/Managers/BrowserManager/BrowserManager.swift: 1491

#### `applyWebViewConfigurationOverride` (1)
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift: 371

#### `assignWebViewToWindow` (4)
- Nook/Managers/BrowserManager/BrowserManager.swift: 708
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 108, 229, 271

#### `assignedWebView` (5)
- Nook/Components/Navigation/NavigationHistoryContextMenu.swift: 78, 111
- Nook/Managers/MediaControlsManager/MediaControlsManager.swift: 114
- Nook/Managers/PiPManager.swift: 26, 84

#### `blockedRequestCount` (4)
- Nook/Components/Extensions/ExtensionLibraryView.swift: 461
- Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift: 205, 295, 454

#### `canGoBack` (1)
- Nook/Components/Sidebar/NavButtonsView.swift: 29

#### `canGoForward` (1)
- Nook/Components/Sidebar/NavButtonsView.swift: 39

#### `checkMediaState` (1)
- Nook/Managers/BrowserManager/BrowserManager.swift: 1991

#### `cleanupCloneWebView` (4)
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 203, 230, 235, 252

#### `clearFindInPage` (2)
- Nook/Managers/FindManager/FindManager.swift: 32, 108

#### `configureTabWebView` (1)
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 175

#### `deliverContextMenuPayload` (2)
- Nook/Utils/WebKit/WebContextMenuBridge.swift: 33, 37

#### `existingWebView` (18)
- Nook/Components/Browser/Window/TabCompositorView.swift: 189
- Nook/Components/WebsiteView/PageLoadingProgressBar.swift: 43, 46, 50
- Nook/Managers/BrowserManager/BrowserManager.swift: 663, 673, 708
- Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift: 81, 97, 101, 211, 371, 379, 402
- Nook/Managers/ExtensionManager/ExtensionBridge.swift: 236
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 126, 151, 227

#### `findInPage` (1)
- Nook/Managers/FindManager/FindManager.swift: 61

#### `findNextInPage` (1)
- Nook/Managers/FindManager/FindManager.swift: 78

#### `findPreviousInPage` (1)
- Nook/Managers/FindManager/FindManager.swift: 93

#### `finishIdentityFlow` (5)
- Nook/Managers/AuthenticationManager/AuthenticationManager.swift: 83, 92, 181, 185, 191

#### `goBack` (2)
- Nook/Components/Sidebar/NavButtonsView.swift: 216
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 264

#### `goForward` (2)
- Nook/Components/Sidebar/NavButtonsView.swift: 225
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 277

#### `hasAudioContent` (5)
- Nook/Components/Browser/Window/TabCompositorView.swift: 187, 216
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 239
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 54
- Nook/Managers/BrowserManager/BrowserManager.swift: 1448

#### `hasPiPActive` (11)
- Nook/Components/Browser/Window/TabCompositorView.swift: 187
- Nook/Components/Sidebar/URLBarView.swift: 66, 70, 72, 75
- Nook/Managers/BrowserManager/BrowserManager.swift: 1438
- Nook/Managers/PiPManager.swift: 74, 86, 92, 124, 128

#### `hasPlayingAudio` (11)
- Nook/Components/Browser/Window/TabCompositorView.swift: 187, 216
- Nook/Components/Sidebar/MediaControls/MediaControlsView.swift: 57, 282
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 54
- Nook/Managers/ExtensionManager/ExtensionBridge.swift: 223
- Nook/Managers/MediaControlsManager/MediaControlsManager.swift: 50, 64, 199, 201, 206

#### `hasPlayingVideo` (9)
- Nook/Components/Browser/Window/TabCompositorView.swift: 187, 216
- Nook/Components/Sidebar/MediaControls/MediaControlsView.swift: 57, 282
- Nook/Managers/MediaControlsManager/MediaControlsManager.swift: 50, 65, 198, 203, 207

#### `hasVideoContent` (3)
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 31
- Nook/Components/Sidebar/URLBarView.swift: 66
- Nook/Managers/BrowserManager/BrowserManager.swift: 1433

#### `isAudioMuted` (15)
- Nook/Components/Extensions/ExtensionLibraryView.swift: 283, 284
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 239, 244, 245
- Nook/Components/Sidebar/MediaControls/MediaControlsView.swift: 64, 286
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 54, 56, 62
- Nook/Managers/BrowserManager/BrowserManager.swift: 1443
- Nook/Managers/ExtensionManager/ExtensionBridge.swift: 219, 268
- Nook/Managers/MediaControlsManager/MediaControlsManager.swift: 288
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 181

#### `isLoading` (5)
- Nook/Components/Sidebar/NavButtonsView.swift: 174, 180
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 174, 180
- Nook/Managers/ExtensionManager/ExtensionBridge.swift: 211

#### `isOptionKeyDown` (2)
- Nook/Utils/WebKit/FocusableWKWebView.swift: 29, 52

#### `isUnloaded` (16)
- Nook/Components/Browser/Window/TabCompositorView.swift: 28, 157, 186, 263
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 257
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift: 266
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 68, 102, 133
- Nook/Components/WebsiteView/WebsiteView.swift: 586, 657
- Nook/Managers/BrowserManager/BrowserManager.swift: 641, 671, 2206
- Nook/Managers/ExtensionManager/ExtensionManager.swift: 204, 210

#### `lastWebProcessCrashDate` (1)
- App/AppDelegate.swift: 106

#### `loadPage` (2)
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 180, 333

#### `loadURL` (6)
- App/NookCommands.swift: 375
- CommandPalette/CommandPaletteView.swift: 424, 458
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 219
- Nook/Components/Sidebar/Menu/SidebarMenuHistoryTab.swift: 398
- Nook/Managers/ExtensionManager/ExtensionBridge.swift: 263

#### `loadWebViewIfNeeded` (3)
- Nook/Components/Browser/Window/TabCompositorView.swift: 124
- Nook/Managers/BrowserManager/BrowserManager.swift: 700
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 125

#### `loadingState` (3)
- Nook/Components/Extensions/ExtensionActionView.swift: 94
- Nook/Components/Sidebar/NavButtonsView.swift: 80
- Nook/Components/WebsiteView/WebsiteLoadingIndicator.swift: 38

#### `navigateToURL` (1)
- CommandPalette/CommandPaletteView.swift: 468

#### `onCommandHover` (1)
- Nook/Components/WebsiteView/WebsiteView.swift: 811

#### `onLinkHover` (1)
- Nook/Components/WebsiteView/WebsiteView.swift: 802

#### `pageBackgroundColor` (6)
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 116, 300, 319, 349, 380, 403

#### `pendingContextMenuPayload` (4)
- Nook/Utils/WebKit/FocusableWKWebView.swift: 74, 85, 404, 420

#### `performComprehensiveWebViewCleanup` (2)
- Nook/Managers/BrowserManager/BrowserManager.swift: 1025, 2592

#### `refresh` (3)
- Nook/Components/Sidebar/NavButtonsView.swift: 230
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 282
- Nook/Managers/BrowserManager/BrowserManager.swift: 1418

#### `requestPictureInPicture` (3)
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 503
- Nook/Components/Sidebar/URLBarView.swift: 68
- Nook/Managers/BrowserManager/BrowserManager.swift: 1428

#### `setMuted` (1)
- Nook/Managers/MediaControlsManager/MediaControlsManager.swift: 289

#### `setupNavigationStateObservers` (1)
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 178

#### `setupThemeColorObserver` (1)
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 177

#### `stop` (2)
- Nook/Components/Sidebar/NavButtonsView.swift: 175
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 175

#### `toggleMute` (5)
- Navigation/Sidebar/SpacesSideBarView.swift: 329
- Nook/Components/Extensions/ExtensionLibraryView.swift: 262
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 241
- Nook/Components/Sidebar/SpaceSection/TabFolderView.swift: 253
- Nook/Managers/BrowserManager/BrowserManager.swift: 1423

#### `topBarBackgroundColor` (6)
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 294, 312, 332, 373, 392, 560

#### `unloadWebView` (3)
- Nook/Components/Browser/Window/TabCompositorView.swift: 119
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 232, 258

#### `updateTitle` (1)
- Nook/Managers/MediaControlsManager/MediaControlsManager.swift: 83

#### `webProcessCrashCount` (1)
- App/AppDelegate.swift: 105

#### `webView` (8)
- Nook/Components/Browser/Window/TabCompositorView.swift: 365
- Nook/Components/Extensions/ExtensionLibraryMoreMenu.swift: 215
- Nook/Components/Extensions/ExtensionLibraryView.swift: 242, 247
- Nook/Managers/BrowserManager/BrowserManager.swift: 1244
- Nook/Managers/ExtensionManager/ExtensionBridge.swift: 250, 273, 278

### 2(c) Other Tab members (rename UI state, back-references, favicon cache statics, OAuth/popup flags): 30 call sites

| Member | Sites | Files |
|---|---|---|
| `isRenaming` | 4 | 1 |
| `editingName` | 1 | 1 |
| `startRenaming` | 2 | 2 |
| `saveRename` | 3 | 1 |
| `cancelRename` | 1 | 1 |
| `browserManager` | 2 | 2 |
| `nookSettings` | 0 | 0 |
| `resolveProfile` | 3 | 3 |
| `isCurrentTab` | 1 | 1 |
| `isActiveInSpace` | 0 | 0 |
| `resetToPinnedURL` | 2 | 2 |
| `closeTab` | 0 | 0 |
| `ensureFaviconLoaded` | 1 | 1 |
| `restoreFaviconFromCache` | 0 | 0 |
| `cacheFavicon` | 3 | 3 |
| `getCachedFavicon` | 3 | 3 |
| `getMemoryCachedFavicon` | 0 | 0 |
| `getDiskCachedFavicon` | 0 | 0 |
| `clearFaviconCache` | 2 | 1 |
| `getFaviconCacheStats` | 1 | 1 |
| `isOAuthFlow` | 1 | 1 |
| `oauthParentTabId` | 0 | 0 |
| `oauthProviderHost` | 0 | 0 |
| `oauthCompletionURLPattern` | 0 | 0 |
| `isPopupHost` | 0 | 0 |

#### `isRenaming` (4)
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 42, 65, 124, 143

#### `editingName` (1)
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 66

#### `startRenaming` (2)
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 146
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 39

#### `saveRename` (3)
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 43, 71, 147

#### `cancelRename` (1)
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 74

#### `browserManager` (2)
- Nook/Utils/WebKit/FocusableWKWebView.swift: 251
- Nook/Utils/WebKit/WebContextMenu.swift: 377

#### `resolveProfile` (3)
- Nook/Managers/PeekManager/PeekManager.swift: 41
- Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift: 44
- Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift: 155

#### `isCurrentTab` (1)
- Nook/Components/Browser/Window/TabCompositorView.swift: 199

#### `resetToPinnedURL` (2)
- App/AppDelegate.swift: 143
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 206

#### `ensureFaviconLoaded` (1)
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 160

#### `cacheFavicon` (3)
- CommandPalette/CommandPalette Accessories/CommandPaletteSuggestionView.swift: 117
- CommandPalette/CommandPalette Accessories/HistorySuggestionItem.swift: 91
- Nook/Components/Sidebar/Menu/SidebarMenuHistoryTab.swift: 578

#### `getCachedFavicon` (3)
- CommandPalette/CommandPalette Accessories/CommandPaletteSuggestionView.swift: 102
- CommandPalette/CommandPalette Accessories/HistorySuggestionItem.swift: 77
- Nook/Components/Sidebar/Menu/SidebarMenuHistoryTab.swift: 561

#### `clearFaviconCache` (2)
- Nook/Managers/CacheManager/CacheManager.swift: 179, 197

#### `getFaviconCacheStats` (1)
- Nook/Managers/CacheManager/CacheManager.swift: 201

#### `isOAuthFlow` (1)
- Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift: 93

## 3. Space and TabFolder runtime classes

`Space` (Space.swift): `@Observable` NSObject with `id, name, icon, color, gradient, accentHex (computed), accentColor (computed), activeTabId, profileId, isEphemeral`. `TabFolder` (TabFolder.swift): `ObservableObject` with `id, name, spaceId, isOpen, icon, index, color, isRegular`.

Construction outside TabManager: `Space(` only at BrowserManager.swift:2512 (incognito window ephemeral space). `TabFolder(` none. `Tab(` at BrowserManager.swift:989 (duplicateTab) and TabOrganizationApplier.swift:230 (undo). `Space.color` and `TabFolder.color/icon/spaceId` have zero external reads: drop them. `Space.activeTabId` has one read (BrowserManager.swift:2153, setActiveSpace), replaced by `selectedItemBySpace`.

Holders of `Space`/`TabFolder` values: `let space: Space` in SpacesListItem.swift:16, SpaceView.swift:34, SpaceTitle.swift:7, TabFolderView.swift:14, SpaceProfileBadge.swift:13, SpaceContextMenu.swift:14, Profiles.swift:271; `let folder: TabFolder` SpaceView.swift:13 (`FolderWithTabs`), FolderContextMenu.swift:13; `SpaceEditDialog(space:)` SpaceEditDialog.swift:32; `refreshGradientsForSpace(_ space: Space,...)` BrowserManager.swift:471; `showSpaceSettings(for: Space)` BrowserManager.swift:1113; `TabOrganizerManager.organizeTabs(in: Space, ...)`; `BrowserWindowState.ephemeralSpaces: [Space]` and computed `currentSpace: Space?`.

### 3(a) Space runtime class: 188 member accesses in 23 files

| Member | Sites | Files (line numbers) |
|---|---|---|
| `id` | 106 | App/NookCommands.swift: 190; App/Window/WindowView.swift: 147; Navigation/Sidebar/SidebarBottomBar.swift: 67; Navigation/Sidebar/SpacesList/SpacesList.swift: 49,54,58,65,72,96,101; Navigation/Sidebar/SpacesList/SpacesListItem.swift: 67; Navigation/Sidebar/SpacesSideBarView.swift: 170,179,237,325,340,362,365,382,391; Nook/Components/Peek/PeekOverlayView.swift: 35; Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift: 65,156,202; Nook/Components/Settings/Tabs/Profiles.swift: 108,120,249,260,365,368,387; Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift: 32,85,86; Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 114,118; Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift: 97,98,148,149,185,196,200,204; Nook/Components/Sidebar/SpaceSection/SpaceView.swift: 94,102,118,178,219,254,296,406,453,464,485,486,525,596,612,635,645,664,665,745,763,787; Nook/Components/Sidebar/SpaceSection/TabFolderView.swift: 32,34; Nook/Managers/BrowserManager/BrowserManager.swift: 479,948,984,985,993,1000,1002,1122,1125,1128,1885,1890,1973,2029,2035,2132,2137,2148,2193,2205,2208,2227,2274,2281,2350,2425,2438,2520; Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift: 58,65; Nook/Managers/TabOrganizerManager/TabOrganizerManager.swift: 112,151,157; Nook/Models/BrowserWindowState.swift: 125,128; Nook/Utils/WebKit/WebContextMenu.swift: 386 |
| `name` | 24 | Navigation/Sidebar/SpacesList/SpacesList.swift: 97; Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift: 92,155; Nook/Components/Settings/Tabs/Profiles.swift: 299,362; Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift: 91; Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 129,134; Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift: 41,54,170,176,182; Nook/Managers/BrowserManager/BrowserManager.swift: 1124,2035,2173,2256; Nook/Managers/DialogManager/Dialogs/SpaceEditDialog.swift: 37; Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift: 474; Nook/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift: 100,102; Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift: 69; Nook/Managers/TabOrganizerManager/TabOrganizerManager.swift: 99,117 |
| `icon` | 15 | Navigation/Sidebar/SpacesList/SpacesListItem.swift: 82; Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift: 90,155; Nook/Components/Settings/Tabs/Profiles.swift: 282,283,286; Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift: 92; Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 127,131,134; Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift: 21,26,27; Nook/Managers/BrowserManager/BrowserManager.swift: 1121; Nook/Managers/DialogManager/Dialogs/SpaceEditDialog.swift: 38 |
| `color` | 0 |  |
| `gradient` | 10 | Nook/Components/Peek/PeekOverlayView.swift: 36; Nook/Managers/BrowserManager/BrowserManager.swift: 482,484,552,1134,1893,1975,2134,2229; Nook/Models/BrowserWindowState.swift: 136 |
| `accentHex` | 2 | Nook/Managers/BrowserManager/BrowserManager.swift: 1133; Nook/Managers/DialogManager/Dialogs/SpaceEditDialog.swift: 40 |
| `accentColor` | 3 | Navigation/Sidebar/SpacesList/SpacesListItem.swift: 82; Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift: 21; Nook/Components/Sidebar/SpaceSection/TabFolderView.swift: 117 |
| `activeTabId` | 1 | Nook/Managers/BrowserManager/BrowserManager.swift: 2153 |
| `profileId` | 25 | Navigation/Sidebar/SpacesSideBarView.swift: 311; Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift: 203,211,214; Nook/Components/Settings/Tabs/Profiles.swift: 100,107,119,330,374; Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift: 29,109,118; Nook/Components/Sidebar/SpaceSection/SpaceProfileBadge.swift: 19; Nook/Managers/BrowserManager/BrowserManager.swift: 951,1127,1892,1976,2040,2133,2140,2209,2230; Nook/Managers/DialogManager/Dialogs/SpaceEditDialog.swift: 39; Nook/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift: 135 |
| `isEphemeral` | 2 | Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift: 214; Nook/Managers/BrowserManager/BrowserManager.swift: 2518 |

### 3(b) TabFolder runtime class: 41 member accesses in 5 files

| Member | Sites | Files (line numbers) |
|---|---|---|
| `id` | 27 | Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 96; Nook/Components/Sidebar/SpaceSection/SpaceView.swift: 18,22,109,161,679,685; Nook/Components/Sidebar/SpaceSection/TabFolderView.swift: 32,35,45,73,87,105,200,222,228,234,242,259,260,281,302; Nook/Managers/BrowserManager/BrowserManager.swift: 2285,2353; Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift: 115,120 |
| `name` | 6 | Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 98; Nook/Components/Sidebar/SpaceSection/TabFolderView.swift: 128,140,289,295,301 |
| `spaceId` | 0 |  |
| `isOpen` | 5 | Nook/Components/Sidebar/SpaceSection/SpaceView.swift: 109; Nook/Components/Sidebar/SpaceSection/TabFolderView.swift: 54,112,113,115 |
| `icon` | 0 |  |
| `index` | 2 | Nook/Components/Sidebar/SpaceSection/SpaceView.swift: 613 |
| `color` | 0 |  |
| `isRegular` | 1 | Nook/Components/Sidebar/SpaceSection/SpaceView.swift: 102 |

### Type references to `Space` (type annotations, generics, constructors): 24 in 15 files

Navigation/Sidebar/SpacesSideBarView.swift (4); Nook/Managers/BrowserManager/BrowserManager.swift (4); Navigation/Sidebar/SpacesList/SpacesListItem.swift (2); Nook/Models/BrowserWindowState.swift (2); Nook/Components/Settings/Tabs/Profiles.swift (2); Navigation/Sidebar/SpacesList/SpacesList.swift (1); Nook/Managers/DialogManager/Dialogs/SpaceEditDialog.swift (1); Nook/Managers/TabOrganizerManager/TabOrganizerManager.swift (1); Nook/Components/Sidebar/SpaceSection/SpaceView.swift (1); Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift (1); Nook/Components/Sidebar/SpaceSection/TabFolderView.swift (1); Nook/Components/Sidebar/SpaceSection/SpaceProfileBadge.swift (1); Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift (1); Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift (1); Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift (1)

Constructor calls `Space(`: Nook/Managers/BrowserManager/BrowserManager.swift:2512

### Type references to `TabFolder` (type annotations, generics, constructors): 7 in 3 files

Nook/Components/Sidebar/SpaceSection/SpaceView.swift (5); Nook/Components/Sidebar/SpaceSection/TabFolderView.swift (1); Nook/Components/Sidebar/ContextMenus/FolderContextMenu.swift (1)

Constructor calls `TabFolder(`: none

### Type references to `Tab` (type annotations, generics, constructors): 155 in 44 files

Nook/Managers/BrowserManager/BrowserManager.swift (14); Nook/Components/Sidebar/SpaceSection/SpaceView.swift (12); Nook/Managers/MediaControlsManager/MediaControlsManager.swift (10); Nook/Managers/SplitViewManager/SplitViewManager.swift (9); Nook/Components/Browser/Window/TabCompositorView.swift (9); Nook/Managers/ExtensionManager/ExtensionManager+TabNotifications.swift (8); Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift (8); Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift (7); Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift (5); Nook/Managers/FindManager/FindManager.swift (4); Nook/Managers/AuthenticationManager/AuthenticationManager.swift (4); Nook/Components/Sidebar/URLBarView.swift (4); Nook/Components/Extensions/ExtensionLibraryView.swift (4); Nook/Components/DragDrop/NookDragSessionManager.swift (4); Nook/Components/DragDrop/NookDragSourceView.swift (4); Nook/Managers/PiPManager.swift (3); Nook/Managers/CacheManager/CacheManager.swift (3); Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift (3); Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift (3); Nook/Components/Sidebar/MediaControls/MediaControlsView.swift (3); CommandPalette/CommandPalette Accessories/CommandPaletteSuggestionView.swift (2); CommandPalette/CommandPalette Accessories/HistorySuggestionItem.swift (2); Nook/Managers/PeekManager/PeekManager.swift (2); Nook/Managers/ExtensionManager/ExtensionBridge.swift (2); Nook/Managers/TabOrganizerManager/TabOrganizerManager.swift (2); Nook/Utils/WebKit/WebContextMenuBridge.swift (2); Nook/Components/Sidebar/NavButtonsView.swift (2); Nook/Components/Sidebar/SpaceSection/TabFolderView.swift (2); Nook/Components/Sidebar/Menu/SidebarMenuHistoryTab.swift (2); Nook/Components/WebsiteView/WebsiteView.swift (2); CommandPalette/CommandPalette Accessories/TabSuggestionItem.swift (1); Nook/Managers/DragManager/TabDragManager.swift (1); Nook/Managers/SearchManager/SearchManager.swift (1); Nook/Managers/DialogManager/Dialogs/EditPinnedURLDialog.swift (1); Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift (1); Nook/Managers/TabOrganizerManager/TabOrganizationPrompt.swift (1); Nook/Utils/WebKit/FocusableWKWebView.swift (1); Nook/Models/BrowserWindowState.swift (1); Nook/Components/Sidebar/SpaceSection/SpaceTab.swift (1); Nook/Components/Sidebar/TopBar/TopBarView.swift (1); Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift (1); Nook/Components/Extensions/ExtensionActionView.swift (1); Nook/Components/DragDrop/NookDragPreviewWindow.swift (1); Nook/Components/WebsiteView/PageLoadingProgressBar.swift (1)

Constructor calls `Tab(`: Nook/Managers/BrowserManager/BrowserManager.swift:989, Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift:230

## 4. BrowserManager tab API and window-state reads

### 4.1 Tab-related functions inside BrowserManager.swift (the hotspot)

| Line | Function | Tab/space coupling |
|---|---|---|
| 440 | `enforceExclusiveAudio` | tab id |
| 471 | `refreshGradientsForSpace(_:animate:)` | windows on space, gradient |
| 490 (private) | `adoptProfileIfNeeded(for:context:)` | `windowState.currentProfileId` -> `switchToProfile` |
| 509 | `init` | creates TabManager, back-ref, `currentSpace?.gradient`, `migrateUnassignedDataToDefaultProfile` |
| 610 (private) | `applyStartupLoadMode(for:)` | `tabManager.currentTab/tabById/allTabs/essentialTabs/tabs(in:)`, `windowState.currentTabId`, warm tabs |
| 697 | `preloadTabInCoordinator` | `loadWebViewIfNeeded`, `assignWebViewToWindow`, `existingWebView` |
| 729 | `switchToProfile(_:context:in:)` | `tabManager.handleProfileSwitch`, `activeWindow.currentProfileId` |
| 911-921 | `showFindBar`, `updateFindManagerCurrentTab` | `currentTabForActiveWindow` |
| 925, 930 | `createNewTab()`, `createNewTab(in:url:)` | private: `createEphemeralTab`; else space by `currentSpaceId`/`currentProfileId` + `tabManager.createNewTab` + `selectTab` |
| 959 | `incognitoWindow(containing:)` | scans `ephemeralTabs` of incognito windows |
| 966, 974 | `duplicateCurrentTab`, `duplicateTab(_:)` | builds `Tab(` at 989, copies placement flags, `addTab`, `reorderRegular`, `selectTab` |
| 1012 | `closeCurrentTab` | private window close path (`ephemeralTabs`, `performComprehensiveWebViewCleanup`), `removeTab`, `closeActiveTab` |
| 1086, 1113 | `showSpaceSettings()`, `showSpaceSettings(for:)` | `renameSpace`, `updateSpaceIcon`, `assign`, gradient, `persistSnapshot` |
| 1197-1248 | `clearCurrentPageCookies`, `clearCurrentPageCache`, `hardReloadCurrentPage` | `currentTabForActiveWindow()?.url/webView` |
| 1350, 1355 | `migrateUnassignedDataToDefaultProfile`, `assignDefaultProfileToExistingData` | history profile backfill (HistoryEntity only after TabManager gone) |
| 1408 | `currentTabForActiveWindow()` | `windowRegistry.activeWindow` -> `currentTab(for:)`, fallback `tabManager.currentTab` (1413) |
| 1417-1447 | `refreshCurrentTabInActiveWindow`, `toggleMuteCurrentTabInActiveWindow`, `requestPiPForCurrentTabInActiveWindow`, `currentTabHasVideoContent`, `currentTabHasPiPActive`, `currentTabIsMuted`, `currentTabHasAudioContent` | live page of active window |
| 1452, 1483 | `copyCurrentURL`, `openWebInspector` | live page |
| 1789 | `deleteProfile(_:)` | `tabManager.cleanupProfileReferences` (1827) |
| 1860 | `presentExternalURL(_:)` | mini window |
| 1869 | `setupWindowState(_:)` | sets `windowState.tabManager`, `currentTabId/currentSpaceId` from global TabManager state |
| 1905 | `setActiveWindowState(_:)` | `notifyTabActivated`, gradient |
| 1934 | `currentTab(for:)` | private: `ephemeralTabs`; else `allTabs().first { id == currentTabId }` |
| 1945, 1956 | `selectTab(_:)`, `selectTab(_:in:)` | writes `currentTabId`, `activeTabForSpace`, `currentSpaceId`, `setActiveTab`, extension notify, compositor |
| 2017 | `tabsForDisplay(in:)` | essentials + space pinned + regular for compositor |
| 2068-2120 | `isCurrentTabFrozen`, `refreshCompositor(for:)`, `getWebView(for:in:)`, `createWebView(for:in:)`, `syncTabAcrossWindows`, `navigateTabAcrossWindows`, `reloadTabAcrossWindows`, `setMuteState` | webview pool by tab id |
| 2125 | `setActiveSpace(_:in:)` | `tabManager.setActiveSpace`, restores `activeTabForSpace`/`Space.activeTabId` |
| 2179 | `validateWindowStates()` | repairs `currentTabId`/`currentSpaceId` against TabManager |
| 2245, 2299, 2320 | `importArcData`, `importDiaData`, `importSafariData` | create spaces/tabs/folders/essentials |
| 2375-2445 | `selectNext/PreviousTabInActiveWindow`, `selectTabByIndexInActiveWindow`, `selectLastTabInActiveWindow`, `selectNext/PreviousSpaceInActiveWindow` | `tabsForDisplay`, `spaces` |
| 2449 | `createNewWindow` | new window state |
| 2494 | `createIncognitoWindow` | ephemeral profile, `Space(` at 2512, `ephemeralSpaces` |
| 2575 | `closeIncognitoWindow(_:)` | destroys `ephemeralTabs` webviews |
| 2627, 2636 | `canDragTab(_:toWindow:)`, `isIncognitoWindow(_:)` | zero callers (dead) |
| 2682-2697 | `showTabClosureToast`, `undoCloseTab` | `tabManager.undoCloseTab` |
| 2702 | `expandAllFoldersInSidebar` | stub (TODO, only toggles sidebar); becomes a real `TabsController` intent or is deleted |
| 2770-2852 | zoom functions | `currentTabForActiveWindow`, `tabManager.tabs.first` (2829, 2842) |

### 4.2 Call counts (all files, including BrowserManager.swift itself, TabManager.swift, Tab.swift)

| API | Total sites | Outside BrowserManager.swift | Inside |
|---|---|---|---|
| `currentTab` | 61 | 56 | 5 |
| `currentTabForActiveWindow` | 46 | 27 | 19 |
| `selectTab` | 27 | 14 | 13 |
| `setActiveSpace` | 5 | 3 | 2 |
| `validateWindowStates` | 2 | 2 | 0 |
| `closeCurrentTab` | 1 | 1 | 0 |
| `duplicateTab` | 2 | 1 | 1 |
| `duplicateCurrentTab` | 1 | 1 | 0 |
| `undoCloseTab` | 3 | 3 | 0 |
| `incognitoWindow` | 4 | 3 | 1 |
| `createNewTab` | 6 | 5 | 1 |
| `createNewWindow` | 2 | 2 | 0 |
| `createIncognitoWindow` | 1 | 1 | 0 |
| `closeIncognitoWindow` | 1 | 1 | 0 |
| `isIncognitoWindow` | 0 | 0 | 0 |
| `canDragTab` | 0 | 0 | 0 |
| `switchToProfile` | 6 | 3 | 3 |
| `adoptProfileIfNeeded` | 2 | 0 | 2 |
| `setupWindowState` | 2 | 2 | 0 |
| `applyStartupLoadMode` | 2 | 0 | 2 |
| `setActiveWindowState` | 1 | 1 | 0 |
| `tabsForDisplay` | 6 | 2 | 4 |
| `isCurrentTabFrozen` | 0 | 0 | 0 |
| `refreshCompositor` | 9 | 9 | 0 |
| `getWebView` | 29 | 23 | 6 |
| `createWebView` | 2 | 2 | 0 |
| `syncTabAcrossWindows` | 3 | 3 | 0 |
| `navigateTabAcrossWindows` | 0 | 0 | 0 |
| `reloadTabAcrossWindows` | 0 | 0 | 0 |
| `setMuteState` | 2 | 2 | 0 |
| `selectNextTabInActiveWindow` | 1 | 1 | 0 |
| `selectPreviousTabInActiveWindow` | 1 | 1 | 0 |
| `selectTabByIndexInActiveWindow` | 1 | 1 | 0 |
| `selectLastTabInActiveWindow` | 1 | 1 | 0 |
| `selectNextSpaceInActiveWindow` | 1 | 1 | 0 |
| `selectPreviousSpaceInActiveWindow` | 1 | 1 | 0 |
| `refreshCurrentTabInActiveWindow` | 3 | 3 | 0 |
| `toggleMuteCurrentTabInActiveWindow` | 2 | 2 | 0 |
| `requestPiPForCurrentTabInActiveWindow` | 2 | 2 | 0 |
| `currentTabHasVideoContent` | 1 | 1 | 0 |
| `currentTabHasPiPActive` | 3 | 3 | 0 |
| `currentTabIsMuted` | 1 | 1 | 0 |
| `currentTabHasAudioContent` | 1 | 1 | 0 |
| `copyCurrentURL` | 2 | 2 | 0 |
| `openWebInspector` | 2 | 2 | 0 |
| `hardReloadCurrentPage` | 2 | 2 | 0 |
| `clearCurrentPageCookies` | 2 | 2 | 0 |
| `clearCurrentPageCache` | 1 | 1 | 0 |
| `updateFindManagerCurrentTab` | 1 | 0 | 1 |
| `showFindBar` | 2 | 2 | 0 |
| `presentExternalURL` | 1 | 1 | 0 |
| `deleteProfile` | 1 | 1 | 0 |
| `showSpaceSettings` | 7 | 6 | 1 |
| `refreshGradientsForSpace` | 4 | 3 | 1 |
| `expandAllFoldersInSidebar` | 1 | 1 | 0 |
| `showTabClosureToast` | 4 | 4 | 0 |
| `zoomInCurrentTab` | 3 | 3 | 0 |
| `zoomOutCurrentTab` | 3 | 3 | 0 |
| `resetZoomCurrentTab` | 3 | 3 | 0 |
| `applyZoomLevel` | 1 | 1 | 0 |
| `loadZoomForTab` | 1 | 1 | 0 |
| `cleanupZoomForTab` | 1 | 1 | 0 |
| `getCurrentZoomLevel` | 0 | 0 | 0 |
| `getCurrentZoomPercentage` | 0 | 0 | 0 |
| `hoveredPinnedTabId` | 2 | 2 | 0 |
| `currentProfile` | 39 | 34 | 5 |
| `importArcData` | 1 | 1 | 0 |
| `importDiaData` | 1 | 1 | 0 |
| `importSafariData` | 1 | 1 | 0 |
| `migrateUnassignedDataToDefaultProfile` | 1 | 0 | 1 |
| `assignDefaultProfileToExistingData` | 1 | 0 | 1 |

### 4.3 Call sites per API (`line (enclosing function)`)

#### `currentTab` (61)
- App/AppDelegate.swift: 150 (setupMouseButtonHandling), 159 (setupMouseButtonHandling)
- CommandPalette/CommandPaletteView.swift: 422 (handleReturn), 424 (handleReturn), 456 (selectSuggestion), 458 (selectSuggestion), 466 (selectSuggestion), 468 (selectSuggestion)
- Nook/Components/Extensions/ExtensionActionView.swift: 36 (currentTab), 135 (showExtensionPopup)
- Nook/Components/Extensions/ExtensionLibraryButton.swift: 32 (body)
- Nook/Components/Extensions/ExtensionLibraryMoreMenu.swift: 133 (currentHost), 214 (loadSiteInfo)
- Nook/Components/Extensions/ExtensionLibraryView.swift: 22 (currentTab), 346 (currentTab)
- Nook/Components/Navigation/NavigationHistoryContextMenu.swift: 66 (body), 76 (loadHistoryItemsFresh), 109 (navigateToHistoryItem)
- Nook/Components/Sidebar/NavButtonsView.swift: 202 (body), 208 (updateCurrentTab)
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift: 100 (body)
- Nook/Components/Sidebar/SpaceSection/SpaceTab.swift: 165 (isCurrentTab)
- Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift: 126 (isActive)
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 29 (body), 103 (body), 105 (body), 116 (body), 121 (body), 195 (urlBar), 206 (urlBar), 252 (updateCurrentTab), 287 (shouldAnimateColorChange), 293 (topBarBackgroundColor), 299 (topBarBackgroundColor), 311 (navButtonColor), 318 (navButtonColor), 331 (urlBarBackgroundColor), 348 (urlBarBackgroundColor), 372 (urlBarTextColor), 379 (urlBarTextColor), 391 (bottomBorderColor), 402 (bottomBorderColor), 442 (displayURL)
- Nook/Components/Sidebar/URLBarView.swift: 20 (body)
- Nook/Components/WebsiteView/WebsiteLoadingIndicator.swift: 38 (indicatorWidth)
- Nook/Components/WebsiteView/WebsiteView.swift: 203 (body), 504 (makeNSView), 514 (updateNSView), 559 (updateNSView), 585 (updateCompositor), 593 (updateCompositor), 656 (updateCompositor), 837 (shouldShowSplit)
- Nook/Managers/AIManager/AIService.swift: 363 (extractPageContext)
- Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift: 94 (getWebView)
- Nook/Managers/BrowserManager/BrowserManager.swift: 1020 (closeCurrentTab), 1410 (currentTabForActiveWindow), 1924 (setActiveWindowState), 2378 (selectNextTabInActiveWindow), 2392 (selectPreviousTabInActiveWindow)
- Nook/Managers/SplitViewManager/SplitViewManager.swift: 307 (maybeDuplicateIfPinned)

#### `currentTabForActiveWindow` (46)
- App/NookCommands.swift: 149 (body), 153 (body), 159 (body), 180 (body), 215 (body), 221 (body), 229 (body), 235 (body), 241 (body), 249 (body), 257 (body), 266 (body), 276 (body), 303 (body), 374 (body)
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift: 744 (updateActiveTabPosition), 762 (updateArrowIndicators), 786 (scrollToActiveTab)
- Nook/Managers/BrowserManager/BrowserManager.swift: 915 (showFindBar), 921 (updateFindManagerCurrentTab), 967 (duplicateCurrentTab), 1198 (clearCurrentPageCookies), 1222 (clearCurrentPageCache), 1233 (hardReloadCurrentPage), 1418 (refreshCurrentTabInActiveWindow), 1423 (toggleMuteCurrentTabInActiveWindow), 1428 (requestPiPForCurrentTabInActiveWindow), 1433 (currentTabHasVideoContent), 1438 (currentTabHasPiPActive), 1443 (currentTabIsMuted), 1448 (currentTabHasAudioContent), 1453 (copyCurrentURL), 1484 (openWebInspector), 2772 (zoomInCurrentTab), 2786 (zoomOutCurrentTab), 2800 (resetZoomCurrentTab), 2826 (applyZoomLevel)
- Nook/Managers/ExtensionManager/ExtensionBridge.swift: 56 (activeTab), 200 (isSelected)
- Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift: 498 (webExtensionController), 686 (setupInternalPortHandler)
- Nook/Managers/ExtensionManager/ExtensionManager.swift: 209 (attach)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 436 (executeAction), 445 (executeAction), 509 (executeAction)
- Nook/Models/Tab/Tab.swift: 576 (setupWebView)

#### `selectTab` (27)
- CommandPalette/CommandPaletteView.swift: 453 (selectSuggestion)
- Navigation/Sidebar/SpacesSideBarView.swift: 327 (makeSpaceView)
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift: 122 (body)
- Nook/Managers/BrowserManager/BrowserManager.swift: 942 (createNewTab), 954 (createNewTab), 978 (duplicateTab), 1006 (duplicateTab), 1008 (duplicateTab), 1033 (closeCurrentTab), 1041 (closeCurrentTab), 1952 (selectTab), 2164 (setActiveSpace), 2384 (selectNextTabInActiveWindow), 2398 (selectPreviousTabInActiveWindow), 2409 (selectTabByIndexInActiveWindow), 2418 (selectLastTabInActiveWindow)
- Nook/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift: 142 (adopt)
- Nook/Managers/PeekManager/PeekManager.swift: 80 (moveToSplitView), 109 (moveToSplitView), 122 (moveToNewTab), 139 (moveToNewTab)
- Nook/Managers/SplitViewManager/SplitViewManager.swift: 166 (closePane), 170 (closePane)
- Nook/Managers/TabManager/TabManager.swift: 1094 (deactivateTab), 1507 (moveTab), 2571 (selectRestoredTab)
- Nook/Models/Tab/Tab.swift: 2902 (webView)

#### `setActiveSpace` (5)
- Navigation/Sidebar/SpacesList/SpacesListItem.swift: 44 (body)
- Navigation/Sidebar/SpacesSideBarView.swift: 173 (spacesContent), 302 (handleSpaceIndexChange)
- Nook/Managers/BrowserManager/BrowserManager.swift: 2430 (selectNextSpaceInActiveWindow), 2444 (selectPreviousSpaceInActiveWindow)

#### `validateWindowStates` (2)
- Nook/Managers/TabManager/TabManager.swift: 724 (removeSpace), 1068 (removeTab)

#### `closeCurrentTab` (1)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 462 (executeAction)

#### `duplicateTab` (2)
- Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift: 162 (editSection)
- Nook/Managers/BrowserManager/BrowserManager.swift: 968 (duplicateCurrentTab)

#### `duplicateCurrentTab` (1)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 475 (executeAction)

#### `undoCloseTab` (3)
- App/NookCommands.swift: 121 (body), 126 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 464 (executeAction)

#### `incognitoWindow` (4)
- Nook/Managers/BrowserManager/BrowserManager.swift: 975 (duplicateTab)
- Nook/Models/Tab/Tab.swift: 2671 (handleCommandClick), 2865 (webView)
- Nook/Utils/WebKit/WebContextMenu.swift: 378 (openLinkInNewTab)

#### `createNewTab` (6)
- CommandPalette/CommandPaletteView.swift: 426 (handleReturn), 462 (selectSuggestion), 476 (selectSuggestion)
- Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift: 107 (executeNavigateToURL), 454 (executeCreateTab)
- Nook/Managers/BrowserManager/BrowserManager.swift: 2564 (createIncognitoWindow)

#### `createNewWindow` (2)
- App/NookCommands.swift: 138 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 487 (executeAction)

#### `createIncognitoWindow` (1)
- App/NookCommands.swift: 143 (body)

#### `closeIncognitoWindow` (1)
- App/NookApp.swift: 192 (setupApplicationLifecycle)

#### `switchToProfile` (6)
- Nook/Components/Settings/Tabs/Profiles.swift: 43 (body), 150 (showCreateDialog)
- Nook/Managers/BrowserManager/BrowserManager.swift: 499 (adoptProfileIfNeeded), 1759 (recoverFromProfileError), 1822 (deleteProfile)
- Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift: 75 (applyRoute)

#### `adoptProfileIfNeeded` (2)
- Nook/Managers/BrowserManager/BrowserManager.swift: 1920 (setActiveWindowState), 2168 (setActiveSpace)

#### `setupWindowState` (2)
- App/NookApp.swift: 170 (setupApplicationLifecycle), 175 (setupApplicationLifecycle)

#### `applyStartupLoadMode` (2)
- Nook/Managers/BrowserManager/BrowserManager.swift: 622 (applyStartupLoadMode), 1899 (setupWindowState)

#### `setActiveWindowState` (1)
- App/NookApp.swift: 204 (setupApplicationLifecycle)

#### `tabsForDisplay` (6)
- Nook/Components/Browser/Window/TabCompositorView.swift: 27 (updateCompositor)
- Nook/Components/WebsiteView/WebsiteView.swift: 574 (updateCompositor)
- Nook/Managers/BrowserManager/BrowserManager.swift: 2377 (selectNextTabInActiveWindow), 2391 (selectPreviousTabInActiveWindow), 2405 (selectTabByIndexInActiveWindow), 2415 (selectLastTabInActiveWindow)

#### `refreshCompositor` (9)
- Nook/Components/Browser/Window/TabCompositorView.swift: 375 (updateTabVisibility), 380 (updateTabVisibility)
- Nook/Managers/SplitViewManager/SplitViewManager.swift: 130 (enterSplit), 151 (exitSplit), 302 (maybeDuplicateIfPinned), 342 (maybeDuplicateIfPinned), 373 (swapSides), 404 (beginPreview), 443 (endPreview)

#### `getWebView` (29)
- App/AppDelegate.swift: 151 (setupMouseButtonHandling), 160 (setupMouseButtonHandling)
- Nook/Components/Browser/Window/TabCompositorView.swift: 42 (getOrCreateWebView)
- Nook/Components/Navigation/NavigationHistoryContextMenu.swift: 78 (loadHistoryItemsFresh), 111 (navigateToHistoryItem)
- Nook/Components/Sidebar/NavButtonsView.swift: 26 (canGoBack), 36 (canGoForward), 63 (observeWebView), 213 (goBack), 222 (goForward)
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 257 (goBack), 270 (goForward)
- Nook/Managers/AIManager/AIService.swift: 364 (extractPageContext)
- Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift: 95 (getWebView)
- Nook/Managers/BrowserManager/BrowserManager.swift: 1240 (hardReloadCurrentPage), 2773 (zoomInCurrentTab), 2787 (zoomOutCurrentTab), 2801 (resetZoomCurrentTab), 2828 (applyZoomLevel), 2841 (loadZoomForTab)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 263 (forwardEventToWebView), 438 (executeAction), 447 (executeAction)
- Nook/Managers/MediaControlsManager/MediaControlsManager.swift: 100 (resolveWebViews)
- Nook/Models/Tab/Tab.swift: 808 (requestPictureInPicture), 3171 (findInPage), 3303 (findNextInPage), 3380 (findPreviousInPage), 3457 (clearFindInPage)

#### `createWebView` (2)
- Nook/Components/Browser/Window/TabCompositorView.swift: 47 (getOrCreateWebView)
- Nook/Components/WebsiteView/WebsiteView.swift: 826 (webView)

#### `syncTabAcrossWindows` (3)
- Nook/Models/Tab/Tab.swift: 763 (loadURL), 2090 (webView), 2129 (webView)

#### `setMuteState` (2)
- Nook/Managers/MediaControlsManager/MediaControlsManager.swift: 294 (toggleMute)
- Nook/Models/Tab/Tab.swift: 1091 (setMuted)

#### `selectNextTabInActiveWindow` (1)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 466 (executeAction)

#### `selectPreviousTabInActiveWindow` (1)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 468 (executeAction)

#### `selectTabByIndexInActiveWindow` (1)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 471 (executeAction)

#### `selectLastTabInActiveWindow` (1)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 473 (executeAction)

#### `selectNextSpaceInActiveWindow` (1)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 481 (executeAction)

#### `selectPreviousSpaceInActiveWindow` (1)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 483 (executeAction)

#### `refreshCurrentTabInActiveWindow` (3)
- App/NookCommands.swift: 218 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 453 (executeAction), 456 (executeAction)

#### `toggleMuteCurrentTabInActiveWindow` (2)
- App/NookCommands.swift: 262 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 532 (executeAction)

#### `requestPiPForCurrentTabInActiveWindow` (2)
- App/NookCommands.swift: 176 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 526 (executeAction)

#### `currentTabHasVideoContent` (1)
- App/NookCommands.swift: 181 (body)

#### `currentTabHasPiPActive` (3)
- App/NookCommands.swift: 182 (body)
- Nook/Components/Sidebar/TopBar/TopBarView.swift: 32 (body), 506 (pipButton)

#### `currentTabIsMuted` (1)
- App/NookCommands.swift: 261 (body)

#### `currentTabHasAudioContent` (1)
- App/NookCommands.swift: 267 (body)

#### `copyCurrentURL` (2)
- App/NookCommands.swift: 156 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 528 (executeAction)

#### `openWebInspector` (2)
- App/NookCommands.swift: 254 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 499 (executeAction)

#### `hardReloadCurrentPage` (2)
- App/NookCommands.swift: 246 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 530 (executeAction)

#### `clearCurrentPageCookies` (2)
- App/NookCommands.swift: 274 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 455 (executeAction)

#### `clearCurrentPageCache` (1)
- App/NookCommands.swift: 301 (body)

#### `updateFindManagerCurrentTab` (1)
- Nook/Managers/BrowserManager/BrowserManager.swift: 1997 (selectTab)

#### `showFindBar` (2)
- App/NookCommands.swift: 212 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 512 (executeAction)

#### `presentExternalURL` (1)
- App/AppDelegate.swift: 250 (handleIncoming)

#### `deleteProfile` (1)
- Nook/Components/Settings/Tabs/Profiles.swift: 209 (startDelete)

#### `showSpaceSettings` (7)
- App/NookCommands.swift: 389 (body)
- App/Window/WindowView.swift: 29 (body)
- Navigation/Sidebar/SpacesList/SpacesListItem.swift: 66 (body)
- Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift: 79 (body), 136 (body)
- Nook/Managers/BrowserManager/BrowserManager.swift: 1109 (showSpaceSettings)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 536 (executeAction)

#### `refreshGradientsForSpace` (4)
- Nook/Managers/BrowserManager/BrowserManager.swift: 1135 (showSpaceSettings)
- Nook/Managers/TabManager/TabManager.swift: 749 (setActiveSpace), 1974 (loadFromStore), 2243 (reattachBrowserManager)

#### `expandAllFoldersInSidebar` (1)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 505 (executeAction)

#### `showTabClosureToast` (4)
- App/Window/WindowView.swift: 65 (body), 87 (body)
- Nook/Managers/TabManager/TabManager.swift: 2436 (trackRecentlyClosedTab), 2493 (trackRecentlyClosedTabs)

#### `zoomInCurrentTab` (3)
- App/NookCommands.swift: 226 (body)
- App/Window/WindowView.swift: 96 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 514 (executeAction)

#### `zoomOutCurrentTab` (3)
- App/NookCommands.swift: 232 (body)
- App/Window/WindowView.swift: 97 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 516 (executeAction)

#### `resetZoomCurrentTab` (3)
- App/NookCommands.swift: 238 (body)
- App/Window/WindowView.swift: 98 (body)
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift: 518 (executeAction)

#### `applyZoomLevel` (1)
- App/Window/WindowView.swift: 99 (body)

#### `loadZoomForTab` (1)
- Nook/Models/Tab/Tab.swift: 2132 (webView)

#### `cleanupZoomForTab` (1)
- Nook/Models/Tab/Tab.swift: 688 (closeTab)

#### `hoveredPinnedTabId` (2)
- App/AppDelegate.swift: 140 (setupMouseButtonHandling)
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift: 126 (body)

#### `currentProfile` (39)
- CommandPalette/CommandPaletteView.swift: 310 (body)
- Navigation/Sidebar/SpacesSideBarView.swift: 311 (makeSpaceView)
- Nook/Components/Settings/Tabs/Profiles.swift: 36 (body), 62 (body), 247 (assignAllSpacesToCurrentProfile), 312 (body)
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift: 30 (body)
- Nook/Components/Sidebar/SpaceSection/SpaceProfileBadge.swift: 29 (isCurrentProfile)
- Nook/Managers/BrowserManager/BrowserManager.swift: 517 (init), 744 (switchToProfile), 758 (switchToProfile), 1728 (startMigrationToCurrentProfile), 1818 (deleteProfile)
- Nook/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift: 92 (present)
- Nook/Managers/SearchManager/SearchManager.swift: 64 (updateProfileContext), 96 (searchSuggestions), 100 (searchSuggestions)
- Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift: 72 (applyRoute)
- Nook/Managers/TabManager/TabManager.swift: 457 (pinnedTabs), 588 (allTabsForCurrentProfile), 672 (createSpace), 732 (setActiveSpace), 1234 (createNewTab), 1312 (createNewTabWithWebView), 1356 (createPopupTab), 1385 (ensureDefaultSpaceIfNeeded), 1446 (handleDragOperation), 1562 (withCurrentProfilePinnedArray), 1572 (pinTab), 1648 (transferTab), 1823 (loadFromStore), 1851 (loadFromStore), 2210 (reattachBrowserManager), 2214 (reattachBrowserManager), 2320 (reconcileSpaceProfilesIfNeeded), 2338 (validateTabProfileAssignments), 2561 (restoreClosedTab)
- Nook/Models/Tab/Tab.swift: 656 (resolveProfile), 2151 (webView)

#### `importArcData` (1)
- Onboarding/OnboardingView.swift: 115 (performImport)

#### `importDiaData` (1)
- Onboarding/OnboardingView.swift: 117 (performImport)

#### `importSafariData` (1)
- Onboarding/Stages/SafariImportFlow.swift: 405 (startImport)

#### `migrateUnassignedDataToDefaultProfile` (1)
- Nook/Managers/BrowserManager/BrowserManager.swift: 565 (init)

#### `assignDefaultProfileToExistingData` (1)
- Nook/Managers/BrowserManager/BrowserManager.swift: 1352 (migrateUnassignedDataToDefaultProfile)


### 4.4 BrowserWindowState fields

Receivers counted: names containing window/state (`windowState`, `activeWindow`, `window`, `ws`, `incognitoWindow`...) and `$0` in window collections. `w` suffix marks a write. Fields not listed (sidebar widths, toasts) are unrelated.


| Field | Reads+writes | Writes (`=`/mutations) | Files |
|---|---|---|---|
| `currentTabId` | 36 | 12 | 10 |
| `currentSpaceId` | 37 | 7 | 7 |
| `activeTabForSpace` | 2 | 1 | 1 |
| `ephemeralTabs` | 15 | 3 | 4 |
| `ephemeralSpaces` | 8 | 2 | 3 |
| `ephemeralProfile` | 11 | 2 | 4 |
| `currentProfileId` | 17 | 11 | 2 |
| `currentSpace` | 2 | 0 | 1 |
| `isIncognito` | 27 | 1 | 8 |
| `tabManager` | 5 | 3 | 3 |
| `compositorVersion` | 3 | 0 | 1 |

#### `windowState.currentTabId` (36)
- Nook/Managers/BrowserManager/BrowserManager.swift (11): 633, 640w, 1886w, 1937, 1940, 1957w, 2184, 2186w, 2204, 2210w, 2605w
- Nook/Managers/TabManager/TabManager.swift (8): 1052, 1053w, 1099, 1100w, 1170w, 1289w, 1409, 1506
- Nook/Components/Browser/Window/TabCompositorView.swift (4): 26, 202, 205, 205
- Nook/Models/Tab/Tab.swift (3): 380, 2673, 2675w
- Nook/Components/Sidebar/MediaControls/MediaControlsView.swift (3): 204, 252, 261
- Nook/Utils/WebKit/WebContextMenu.swift (2): 381, 383w
- Nook/Components/WebsiteView/WebsiteView.swift (2): 199, 215
- Nook/Managers/SplitViewManager/SplitViewManager.swift (1): 118
- Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift (1): 425
- Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift (1): 261

#### `windowState.currentSpaceId` (37)
- Nook/Managers/BrowserManager/BrowserManager.swift (25): 479, 947, 985, 1885w, 1889, 1963, 1964w, 1968, 1972, 1977, 2028, 2033, 2033, 2132w, 2192, 2194w, 2205, 2221, 2222w, 2226, 2231, 2424, 2437, 2520w, 2613w
- Navigation/Sidebar/SpacesSideBarView.swift (6): 170, 178, 179, 325, 381, 390
- Navigation/Sidebar/SpacesList/SpacesList.swift (2): 49, 95
- App/NookCommands.swift (1): 189
- App/Window/WindowView.swift (1): 146
- Nook/Components/Sidebar/FallbackDropBelowEssentialsModifier.swift (1): 29
- Nook/Components/Peek/PeekOverlayView.swift (1): 34

#### `windowState.activeTabForSpace` (2)
- Nook/Managers/BrowserManager/BrowserManager.swift (2): 1969w, 2148

#### `windowState.ephemeralTabs` (15)
- Nook/Managers/BrowserManager/BrowserManager.swift (11): 962, 1028, 1029w, 1032, 1937, 2020, 2092, 2585, 2591, 2601, 2603w
- Nook/Models/Tab/Tab.swift (2): 633, 2901
- Nook/Managers/TabManager/TabManager.swift (1): 1288w
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift (1): 85

#### `windowState.ephemeralSpaces` (8)
- Navigation/Sidebar/SpacesSideBarView.swift (3): 144, 382, 384
- Nook/Managers/BrowserManager/BrowserManager.swift (3): 2519w, 2602, 2604w
- Navigation/Sidebar/SpacesList/SpacesList.swift (2): 22, 32

#### `windowState.ephemeralProfile` (11)
- Nook/Managers/BrowserManager/BrowserManager.swift (5): 932, 976, 1036, 2508w, 2612w
- Nook/Models/Tab/Tab.swift (3): 635, 2671, 2867
- Nook/Managers/PeekManager/PeekManager.swift (2): 78, 120
- Nook/Utils/WebKit/WebContextMenu.swift (1): 380

#### `windowState.currentProfileId` (17)
- Nook/Managers/BrowserManager/BrowserManager.swift (16): 493, 502w, 652, 759w, 950, 1882w, 1892w, 1917, 1918w, 1976w, 1979w, 2040, 2133w, 2230w, 2233w, 2509w
- Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift (1): 30

#### `windowState.currentSpace` (2)
- Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift (2): 414, 439

#### `windowState.isIncognito` (27)
- Nook/Managers/BrowserManager/BrowserManager.swift (12): 460, 478, 932, 962, 1023, 1936, 2019, 2081, 2091, 2504w, 2576, 2629
- Nook/Components/Sidebar/SpaceSection/SpaceView.swift (4): 84, 91, 99, 117
- Navigation/Sidebar/SpacesSideBarView.swift (3): 143, 308, 380
- Navigation/Sidebar/SidebarBottomBar.swift (2): 25, 33
- Navigation/Sidebar/SpacesList/SpacesList.swift (2): 21, 31
- Nook/Managers/PeekManager/PeekManager.swift (2): 77, 119
- App/NookApp.swift (1): 190
- Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift (1): 50

#### `windowState.tabManager` (5)
- Nook/Managers/BrowserManager/BrowserManager.swift (2): 1871w, 2561w
- Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift (2): 413, 438
- App/ContentView.swift (1): 38w

#### `windowState.compositorVersion` (3)
- Nook/Components/WebsiteView/WebsiteView.swift (3): 200, 214, 515


## 5. Subsystems coupled to tabs

Each bullet: file: `enclosingFunction`:firstLine [members touched]. Members include TabManager members, Tab/Space/TabFolder fields, BrowserManager APIs and window-state fields.

### 5.1 ExtensionManager / ExtensionBridge

`ExtensionTabAdapter` wraps a `Tab` (`internal let tab: Tab`, ExtensionBridge.swift:171) and is cached in `ExtensionManager.tabAdapters: [UUID: ExtensionTabAdapter]` (ExtensionManager.swift:38) keyed by tab id; keying by item id keeps the shape. One `ExtensionWindowAdapter` (ExtensionBridge.swift:13) for the whole app enumerates `pinnedTabs + tabs` (global current space only) with a generation cache; it must become per `BrowserWindowState`. Delegate `openNewTabUsing` (Delegate:331) and `openNewWindowUsing` (Delegate:413) create tabs/spaces through `tabManager`. Notifications `notifyTabOpened/Activated/Closed/PropertiesChanged` are fired from TabManager.swift (709, 795, ...) and BrowserManager.swift (1925, 1994); after cutover TabsController and PageSession fire them. Extension UI views read `browserManager.currentTab(for:)` then `tab.webView/url/isAudioMuted`.

- `Nook/Managers/ExtensionManager/ExtensionBridge.swift`: `activeTab`:56 [currentTabForActiveWindow, pinnedTabs, tabs]; `tabs`:73 [pinnedTabs, tabs]; `ExtensionTabAdapter`:171 []; `init`:174 []; `isEqual`:184 [id]; `hash`:188 [id]; `url`:192 [url]; `title`:196 [name]; `isSelected`:200 [currentTabForActiveWindow, id]; `indexInWindow`:204 [id, index, pinnedTabs]; `isLoadingComplete`:211 [isLoading]; `isPinned`:215 [id, pinnedTabs]; `isMuted`:219 [isAudioMuted]; `isPlayingAudio`:223 [hasPlayingAudio]; `webView`:236 [existingWebView]; `activate`:240 [setActiveTab]; `close`:245 [id, removeTab]; `reload`:250 [webView]; `loadURL`:263 [loadURL]; `setMuted`:268 [isAudioMuted]; `setZoomFactor`:273 [webView]; `zoomFactor`:278 [webView]
- `Nook/Managers/ExtensionManager/ExtensionManager+TabNotifications.swift`: `adapter`:17 [id, name]; `stableAdapter`:33 [isEphemeral]; `notifyTabOpened`:38 [id]; `openedAdapter`:49 [id]; `notifyTabActivated`:89 [url]; `notifyTabClosed`:114 [id]; `notifyTabPropertiesChanged`:125 []
- `Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift`: `webExtensionController`:363 [applyWebViewConfigurationOverride, createNewTab, createSpace, currentSpace, currentTabForActiveWindow, name, pinTab, setActiveSpace, setActiveTab]; `setupInternalPortHandler`:686 [currentTabForActiveWindow]
- `Nook/Managers/ExtensionManager/ExtensionManager+Installation.swift`: `registerContext`:371 [id, pinnedTabs, tabs, url]
- `Nook/Managers/ExtensionManager/ExtensionManager.swift`: `attach`:202 [currentTabForActiveWindow, isUnloaded, pinnedTabs, tabs]
- `Nook/Components/Extensions/ExtensionActionView.swift`: `currentTab`:35 [currentTab]; `body`:91 [loadingState, url]; `showExtensionPopup`:135 [currentTab, name]
- `Nook/Components/Extensions/ExtensionLibraryButton.swift`: `body`:32 [currentTab, id]
- `Nook/Components/Extensions/ExtensionLibraryMoreMenu.swift`: `currentHost`:133 [currentTab, url]; `loadSiteInfo`:214 [currentTab, webView]
- `Nook/Components/Extensions/ExtensionLibraryView.swift`: `currentTab`:21 [currentTab]; `currentHost`:26 [url]; `utilityButtonsSection`:56 [name, url]; `footerSection`:202 [url]; `zoomIn`:242 [id, url, webView]; `zoomOut`:247 [id, url, webView]; `MuteButton`:255 []; `body`:262 [isAudioMuted, toggleMute]; `ContentBlockerSiteRow`:455 []; `subtitle`:461 [blockedRequestCount]

### 5.2 AI BrowserToolExecutor

Uses `windowState.tabManager` (413, 438) for `tabs(in: currentSpace)` and `setActiveTab`; `createNewTab(in:url:)` on BrowserManager for navigate/create tools; page context via `currentTab(for:)` + `getWebView(for:in:)`.

- `Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift`: `getWebView`:94 [currentTab, getWebView, id]; `executeNavigateToURL`:107 [createNewTab]; `executeGetTabList`:413 [currentSpace, currentTabId, id, name, tabManager, tabs, url]; `executeSwitchTab`:438 [currentSpace, name, setActiveTab, tabManager, tabs]; `executeCreateTab`:454 [createNewTab]
- `Nook/Managers/AIManager/AIService.swift`: `extractPageContext`:363 [currentTab, getWebView, id]

### 5.3 CommandPalette + SearchManager

`CommandPaletteView.swift:284` injects `browserManager.tabManager` into `SearchManager.setTabManager`; `SearchManager.searchTabs` (112) uses `allTabsForCurrentProfile()`. Suggestion `.tab(Tab)` carries a live `Tab`; selecting it calls `browserManager.selectTab`. Return key: `currentTab(for:)?.loadURL` or `createNewTab(in:url:)`. Favicon cache statics `Tab.getCachedFavicon/cacheFavicon` used by suggestion rows (move to a standalone `FaviconCache`).

- `CommandPalette/CommandPaletteView.swift`: `body`:310 [currentProfile]; `handleReturn`:422 [createNewTab, currentTab, loadURL]; `selectSuggestion`:453 [createNewTab, currentTab, loadURL, navigateToURL, selectTab]; `displayTextForSuggestion`:516 [url]; `iconForSuggestion`:544 [favicon]
- `CommandPalette/CommandPalette Accessories/TabSuggestionItem.swift`: `TabSuggestionItem`:11 []; `body`:21 [favicon, name]
- `CommandPalette/CommandPalette Accessories/CommandPaletteSuggestionView.swift`: `fetchFavicon`:102 [cacheFavicon, getCachedFavicon]
- `CommandPalette/CommandPalette Accessories/HistorySuggestionItem.swift`: `fetchFavicon`:77 [cacheFavicon, getCachedFavicon]
- `Nook/Managers/SearchManager/SearchManager.swift`: `SuggestionType`:42 [id]; `updateProfileContext`:64 [browserManager, currentProfile]; `searchSuggestions`:96 [browserManager, currentProfile]; `searchTabs`:112 [allTabsForCurrentProfile, name, url]

### 5.4 SiteRoutingManager

`applyRoute(url:from:)` (40) is called from `Tab.decidePolicyFor`, popup creation and `AppDelegate.handleIncoming` (247). It resolves `tabManager.spaces`, switches profile, `setActiveSpace`, `createNewTab(url:in:)`. Settings view lists spaces grouped by `profileId`.

- `Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift`: `applyRoute`:40 [createNewTab, currentProfile, currentSpace, id, isIncognito, name, resolveProfile, setActiveSpace, spaces, switchToProfile]
- `Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift`: `ruleRow`:65 [icon, id, name, spaces]; `body`:155 [icon, id, name, profileId, spaces]; `groupedSpaces`:208 [isEphemeral, profileId, spaces]

### 5.5 PeekManager

`moveToSplitView` (79-109) and `moveToNewTab` (119-139) adopt the Peek `WKWebView` through `createNewTabWithWebView` or `createEphemeralTab` (private) then `selectTab`. `presentExternalURL` resolves profile from a `Tab`. Overlay reads space gradient by `windowState.currentSpaceId`.

- `Nook/Managers/PeekManager/PeekManager.swift`: `presentExternalURL`:26 [id, resolveProfile, url]; `moveToSplitView`:77 [createEphemeralTab, createNewTab, createNewTabWithWebView, currentSpace, ephemeralProfile, isIncognito, selectTab]; `moveToNewTab`:119 [createEphemeralTab, createNewTabWithWebView, currentSpace, ephemeralProfile, isIncognito, selectTab]
- `Nook/Components/Peek/PeekOverlayView.swift`: `currentSpaceColor`:34 [currentSpaceId, gradient, id, spaces]

### 5.6 ExternalMiniWindowManager / MiniWindow

`present(url:)` picks `tabManager.currentSpace ?? spaces.first` for profile; `adopt` (130-142) turns the mini window webview into a tab via `createNewTabWithWebView` + `selectTab`. Needs `TabsController.adopt(webView:...)`.

- `Nook/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift`: `present`:92 [currentProfile, currentSpace, name, spaces]; `adopt`:131 [createNewTabWithWebView, currentSpace, profileId, selectTab, spaces]

### 5.7 SplitViewManager

Per-window `WindowSplitState { leftTabId, rightTabId, dividerFraction, activeSide }` (29) keyed by window id plus published mirror (`leftTabId/rightTabId`, 9-10). `resolveTab` uses `allTabs()`; `maybeDuplicateIfPinned` (282) uses `isGlobalPinned/isSpacePinned/duplicateAsRegularForSplit`. Spec moves split pair into `BrowserWindowState`/`WindowRecord.split`.

- `Nook/Managers/SplitViewManager/SplitViewManager.swift`: `enterSplit`:118 [currentTabId, refreshCompositor]; `exitSplit`:151 [refreshCompositor]; `closePane`:165 [allTabs, id, selectTab]; `resolveTab`:209 [allTabs, id]; `tab`:214 []; `maybeDuplicateIfPinned`:282 [allTabs, currentTab, duplicateAsRegularForSplit, id, isGlobalPinned, isSpacePinned, refreshCompositor]; `swapSides`:373 [refreshCompositor]; `beginPreview`:404 [refreshCompositor]; `endPreview`:443 [refreshCompositor]
- `Nook/Components/Browser/Window/SplitDropCaptureView.swift`: `performDragOperation`:80 [allTabs, id]
- `Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift`: `SplitTabRow`:4 []; `SplitHalfTab`:42 []; `body`:58 [displayName, favicon, id, index, spaceId, url]; `isActive`:126 [currentTab, id]

### 5.8 WebViewCoordinator

Pool `webViewsByTabAndWindow[tabId][windowId]`; `getOrCreateWebView(for: Tab, in:, tabManager:)` (90), `cleanupWindow(_:tabManager:)` (210), `cleanupAllWebViews(tabManager:)` (245) take `TabManager`. Uses Tab webview-ownership members (`existingWebView`, `assignWebViewToWindow`, `cleanupCloneWebView`, `unloadWebView`, `configureTabWebView`, `resolveProfile`, `Tab.loadPage`). Becomes PageSession-owned or keyed by item id with `PageSession` argument.

- `Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift`: `getOrCreateWebView`:90 [assignWebViewToWindow, id]; `createPrimaryWebView`:122 [existingWebView, id, loadWebViewIfNeeded]; `createCloneWebView`:134 [id]; `createWebViewInternal`:145 [configureTabWebView, existingWebView, id, isAudioMuted, loadPage, resolveProfile, setupNavigationStateObservers, setupThemeColorObserver, url]; `removeAllWebViews`:200 [cleanupCloneWebView, id]; `cleanupWindow`:219 [allTabs, assignWebViewToWindow, cleanupCloneWebView, existingWebView, id, unloadWebView]; `cleanupAllWebViews`:246 [allTabs, cleanupCloneWebView, id, unloadWebView]; `createWebView`:265 [assignWebViewToWindow, id]; `syncTab`:333 [loadPage]

### 5.9 TabCompositorView / compositorManager

`TabCompositorManager` unload policy: `handleTabTimeout` (178), `handleMemoryPressure` (252), `handleAppDidResignActive` (303), `enforceMaxLoadedTabs` (315), `isCurrentTabInAnyWindow`, `tabImportanceScore`, `findTab`, `findTabByWebView`. Maps to spec `isVisibleInAnyWindow(itemID)` plus session media flags. `WebsiteView.Coordinator.updateCompositor` (585-656) uses `tabsForDisplay(in:)`, `allTabs()`, `currentTab(for:)`, `compositorVersion`; status-bar link hover via `onLinkHover/onCommandHover` (setupHoverCallbacks).

- `Nook/Components/Browser/Window/TabCompositorView.swift`: `updateCompositor`:26 [currentTabId, id, isUnloaded, tabsForDisplay]; `getOrCreateWebView`:40 [createWebView, getWebView, id]; `unloadTab`:114 [id, unloadWebView]; `loadTab`:122 [id, loadWebViewIfNeeded]; `handleTabTimeout`:157 [isPinned, isSpacePinned, isUnloaded, unloadTab]; `canUnloadInactiveTab`:185 [existingWebView, hasAudioContent, hasPiPActive, hasPlayingAudio, hasPlayingVideo, id, isPinned, isSpacePinned, isUnloaded]; `isCurrentTabInAnyWindow`:197 [currentTabId, id, isCurrentTab]; `tabImportanceScore`:213 [hasAudioContent, hasPlayingAudio, hasPlayingVideo, id, isPinned, isSpacePinned]; `handleMemoryPressure`:252 [allTabs, isUnloaded, unloadTab]; `handleAppDidResignActive`:303 [allTabs, unloadTab]; `enforceMaxLoadedTabs`:315 [allTabs, id, isPinned, isSpacePinned, unloadTab]; `findTab`:358 [allTabs, id]; `findTabByWebView`:363 [allTabs, webView]; `updateTabVisibility`:375 [refreshCompositor]
- `Nook/Components/WebsiteView/WebsiteView.swift`: `body`:199 [compositorVersion, currentTab, currentTabId]; `makeNSView`:504 [currentTab]; `updateNSView`:514 [compositorVersion, currentTab, id]; `updateCompositor`:574 [allTabs, currentTab, id, isUnloaded, tabsForDisplay]; `setupHoverCallbacks`:800 [onCommandHover, onLinkHover]; `webView`:818 [createWebView, id]; `shouldShowSplit`:837 [currentTab, id]
- `Nook/Components/WebsiteView/PageLoadingProgressBar.swift`: `PageLoadingProgressBar`:14 []; `body`:42 [existingWebView, id]
- `Nook/Components/WebsiteView/WebsiteLoadingIndicator.swift`: `indicatorWidth`:38 [currentTab, loadingState]

### 5.10 HistoryManager

HistoryManager stores `tabId: UUID?` only (HistoryManager.swift:11, 124, 225; HistoryEntity.swift:18); written from Tab.swift:2153 `historyManager.addVisit`. No code change beyond passing item id from PageSession. `SidebarMenuHistoryTab.openInCurrentTab` (397-400) uses `tabManager.currentTab?.loadURL` or `tabManager.createNewTab(url:)` (global current tab: must become window-scoped).

- `Nook/Managers/HistoryManager/HistoryManager.swift`: no direct model/BM/window-state member hits (see note)
- `Nook/Components/Sidebar/Menu/SidebarMenuHistoryTab.swift`: `openInCurrentTab`:397 [createNewTab, currentTab, loadURL]; `fetchFavicon`:561 [cacheFavicon, getCachedFavicon]

### 5.11 KeyboardShortcutManager + NookCommands

`executeAction` (436-509) dispatches to BrowserManager: `closeCurrentTab`, `undoCloseTab`, `selectNext/PreviousTabInActiveWindow`, `selectTabByIndexInActiveWindow`, `selectLastTabInActiveWindow`, `duplicateCurrentTab`, `selectNext/PreviousSpaceInActiveWindow`, `createNewWindow`, `currentTabForActiveWindow()?.url`. `forwardEventToWebView` (261) reads `windowState.currentTabId` + `getWebView`. NookCommands menu body: 15 `currentTabForActiveWindow` reads, `tabManager.spaces/currentSpace` for space settings enablement (190-204, 392). Website shortcut detector is invoked from Tab.swift (3 sites).

- `Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift`: `forwardEventToWebView`:261 [currentTabId, getWebView]; `executeAction`:436 [clearCurrentPageCookies, closeCurrentTab, copyCurrentURL, createNewWindow, currentTabForActiveWindow, duplicateCurrentTab, expandAllFoldersInSidebar, getWebView, hardReloadCurrentPage, id, openWebInspector, refreshCurrentTabInActiveWindow, requestPiPForCurrentTabInActiveWindow, resetZoomCurrentTab, selectLastTabInActiveWindow, selectNextSpaceInActiveWindow, selectNextTabInActiveWindow, selectPreviousSpaceInActiveWindow, selectPreviousTabInActiveWindow, selectTabByIndexInActiveWindow, showFindBar, showSpaceSettings, toggleMuteCurrentTabInActiveWindow, undoCloseTab, url, zoomInCurrentTab, zoomOutCurrentTab]
- `App/NookCommands.swift`: `body`:121 [clearCurrentPageCache, clearCurrentPageCookies, copyCurrentURL, createIncognitoWindow, createNewWindow, currentSpace, currentSpaceId, currentTabForActiveWindow, currentTabHasAudioContent, currentTabHasPiPActive, currentTabHasVideoContent, currentTabIsMuted, hardReloadCurrentPage, id, loadURL, openWebInspector, refreshCurrentTabInActiveWindow, requestPiPForCurrentTabInActiveWindow, resetZoomCurrentTab, showFindBar, showSpaceSettings, spaces, toggleMuteCurrentTabInActiveWindow, undoCloseTab, url, zoomInCurrentTab, zoomOutCurrentTab]

### 5.12 TabOrganizerManager / TabOrganizationApplier

`organizeTabs(in: Space, using: TabManager)` (71) and `undoLastOrganization(using:)` (179). Applier snapshots placement fields (`spaceId,index,isPinned,isSpacePinned,folderId,displayNameOverride`, 72) and restores them by direct field writes (undo 199-247) plus `Tab(...)` reconstruction (230) and `addTab`. Replace whole undo with `Change` values from `TabTree` (`apply(_:)`).

- `Nook/Managers/TabOrganizerManager/TabOrganizerManager.swift`: `TabOrganizerManager`:30 []; `organizeTabs`:71 [folders, id, looseTabs, name]
- `Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift`: `snapshot`:72 [displayNameOverride, folderId, id, index, isPinned, isSpacePinned, spaceId]; `apply`:101 [createRegularFolder, displayNameOverride, folderId, id, index, isPinned, isSpacePinned, moveTabToFolder, name, persistSnapshot, removeTab, spaceId, unpinTab, unpinTabFromSpace, url]; `undo`:206 [addTab, allTabs, deleteFolder, displayNameOverride, folderId, id, index, isPinned, isSpacePinned, persistSnapshot, spaceId]
- `Nook/Managers/TabOrganizerManager/TabOrganizationPrompt.swift`: `TabInput`:16 []; `buildUser`:119 [displayName, url]

### 5.13 DownloadManager

No `Tab` references in DownloadManager.swift. Coupling is inbound only: `Tab` WKDownloadDelegate (Tab.swift:2427-2493) calls `browserManager.downloadManager.addDownload` (2 sites); `FocusableWKWebView.registerDownload` reads `tab.browserManager`. Moves with PageSession+Navigation.

- `Nook/Managers/DownloadManager/DownloadManager.swift`: no direct model/BM/window-state member hits (see note)

### 5.14 FindManager

Holds `currentTab: Tab?`; `search/findNext/findPrevious/clearSearch/hideFindBar` call `tab.findInPage/findNextInPage/findPreviousInPage/clearFindInPage`. Set by `BrowserManager.updateFindManagerCurrentTab` (921) and `showFindBar` (915) from `currentTabForActiveWindow()`. FindBarView.swift:45 passes `findManager.currentTab`. Needs `PageSession` find API.

- `Nook/Managers/FindManager/FindManager.swift`: `FindManager`:19 []; `showFindBar`:21 []; `hideFindBar`:32 [clearFindInPage]; `search`:45 [findInPage]; `findNext`:78 [findNextInPage]; `findPrevious`:93 [findPreviousInPage]; `clearSearch`:108 [clearFindInPage]; `updateCurrentTab`:114 []
- `Nook/Components/FindBar/FindBarView.swift`: no direct model/BM/window-state member hits (see note)

### 5.15 ZoomManager

ZoomManager is keyed by `tabId: UUID` only (45-152). Tab coupling lives in BrowserManager.swift zoom functions (`zoomInCurrentTab` 2770, `zoomOutCurrentTab` 2784, `resetZoomCurrentTab` 2798, `applyZoomLevel` 2823 which uses `tabManager.tabs.first`, `loadZoomForTab` 2839, `cleanupZoomForTab` 2852) and Tab.swift (`loadZoomForTab`, `cleanupZoomForTab`). Zoom is keyed by host in the page; keeping item id works.

- `Nook/Managers/ZoomManager/ZoomManager.swift`: no direct model/BM/window-state member hits (see note)
- `Nook/Components/ZoomControls/ZoomPopupView.swift`: no direct model/BM/window-state member hits (see note)

### 5.16 MediaControlsManager

`findActiveMediaTab` (60) scans `allTabs()` for `hasPlayingAudio/Video`; `resolveWebViews` uses `assignedWebView` + `getWebView`; `toggleMute` uses `setMuteState(_:tabId:originatingWindowId:)`. View `.onChange(of: browserManager.tabManager.spaces)` (200) and `windowState.currentTabId`. Needs `tabs.sessions` and session media flags.

- `Nook/Managers/MediaControlsManager/MediaControlsManager.swift`: `MediaControlsManager`:21 []; `findActiveMediaTab`:46 [allTabs, hasPlayingAudio, hasPlayingVideo, url]; `refreshTitle`:78 [name, updateTitle]; `resolveWebViews`:95 [assignedWebView, getWebView, id]; `executeMediaScript`:122 []; `playPause`:162 [hasPlayingAudio, hasPlayingVideo]; `next`:217 []; `previous`:251 []; `toggleMute`:285 [id, isAudioMuted, setMuteState, setMuted]; `isPlaying`:301 []
- `Nook/Components/Sidebar/MediaControls/MediaControlsView.swift`: `MediaControlsTabTitle`:13 []; `body`:16 [currentTabId, favicon, name, spaces]; `MediaControlsView`:32 []; `isPlaying`:57 [hasPlayingAudio, hasPlayingVideo]; `isMuted`:64 [isAudioMuted]; `updateMediaState`:248 [allTabs, currentTabId, hasPlayingAudio, hasPlayingVideo, id, isAudioMuted]

### 5.17 PiPManager

`requestPiP(for: Tab)`, `stopPiP(for:)`, `isPiPActive(for:)` use `tab.assignedWebView` and `tab.hasPiPActive`. Called via BrowserManager `requestPiPForCurrentTabInActiveWindow` and `Tab.requestPictureInPicture`.

- `Nook/Managers/PiPManager.swift`: `requestPiP`:23 [assignedWebView, hasPiPActive]; `stopPiP`:82 [assignedWebView, hasPiPActive]; `isPiPActive`:127 [hasPiPActive]

### 5.18 AuthenticationManager / ContentBlockerManager / CacheManager

Live-page only. AuthenticationManager: identity flow on `Tab.finishIdentityFlow`, `activeWebView`. ContentBlockerManager: iterates `tabManager.allTabs()` for `existingWebView`, `blockedRequestCount`, `isOAuthFlow`, per-tab temporary disable keyed by `tab.id`; `tab(for webView:)` (402). CacheManager: `Tab.clearFaviconCache/getFaviconCacheStats` statics.

- `Nook/Managers/AuthenticationManager/AuthenticationManager.swift`: `message`:74 []; `beginIdentityFlow`:80 [finishIdentityFlow]; `handleAuthenticationChallenge`:110 []; `handleMiniWindowCompletion`:181 [activeWebView, finishIdentityFlow]; `cancelActiveIdentityFlow`:191 [finishIdentityFlow]; `presentBasicCredentialPrompt`:204 [activeWebView]
- `Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift`: `disableTemporarily`:62 [id]; `allowDomain`:80 [allTabs, existingWebView]; `isExempt`:92 [id, isOAuthFlow]; `shouldApplyBlocking`:96 [existingWebView]; `reconcileAndReload`:100 [existingWebView]; `setDetailedCountsEnabled`:205 [allTabs, blockedRequestCount, existingWebView]; `strippedTrackingParams`:282 []; `setupContentBlockerScripts`:291 [blockedRequestCount]; `applyToExistingWebViews`:370 [allTabs, existingWebView]; `removeFromExistingWebViews`:378 [allTabs, existingWebView]; `tab`:401 [allTabs, existingWebView]; `userContentController`:454 [blockedRequestCount]
- `Nook/Managers/CacheManager/CacheManager.swift`: `clearAllCache`:179 [clearFaviconCache]; `clearFaviconCache`:197 [clearFaviconCache]; `getFaviconCacheStats`:201 [getFaviconCacheStats]

### 5.19 ImportManager (Arc / Safari / Dia)

Importer files parse into DTOs (`ArcTab`, Dia tabs, Safari bookmarks) and reference no Nook `Tab`/`Space`/entities. All creation happens in BrowserManager.swift: `importArcData` (2245: `createSpace`, `createNewTab`, `pinTabToSpace`, `createFolder`, `moveTabToFolder`, `addToEssentials`), `importDiaData` (2299: `createNewTab`, `addToEssentials`), `importSafariData` (2320: `createNewTab`, `addToEssentials`, `createFolder`, `moveTabToFolder`). Callers: Onboarding/OnboardingView.swift:115-117, Onboarding/Stages/SafariImportFlow.swift:405.

- `Nook/Managers/ImportManager/Arc.swift`: no direct model/BM/window-state member hits (see note)
- `Nook/Managers/ImportManager/Dia.swift`: no direct model/BM/window-state member hits (see note)
- `Nook/Managers/ImportManager/Safari.swift`: no direct model/BM/window-state member hits (see note)
- `Nook/Managers/ImportManager/ImportManager.swift`: no direct model/BM/window-state member hits (see note)

### 5.20 Onboarding

Only the import calls above. TabLayoutStage.swift mentions tabs in layout-setting copy only (no model use). First-launch seeding moves to `TabStore.firstLaunch` / `DeviceState.firstLaunchCompleted`.

- `Onboarding/OnboardingView.swift`: `performImport`:115 [importArcData, importDiaData]
- `Onboarding/Stages/SafariImportFlow.swift`: `startImport`:405 [importSafariData]
- `Onboarding/Stages/TabLayoutStage.swift`: no direct model/BM/window-state member hits (see note)

### 5.21 AppDelegate

`handleSystemWake` (104) iterates `allTabs()` for crash counters; `setupMouseButtonHandling` (140-160) middle-click on hovered essential: `allTabs().first` by `hoveredPinnedTabId`, `resetToPinnedURL`, back/forward buttons via `currentTab(for:)` + `getWebView`; `applicationShouldTerminate` (189) `persistFinalSnapshotBlocking()` becomes `tabs.flushSync()`; `handleIncoming` (239-250) routes external URLs through `siteRoutingManager.applyRoute` then `presentExternalURL` (mini window).

- `App/AppDelegate.swift`: `handleSystemWake`:104 [allTabs, lastWebProcessCrashDate, webProcessCrashCount]; `setupMouseButtonHandling`:140 [allTabs, currentTab, getWebView, hoveredPinnedTabId, id, pinnedURL, resetToPinnedURL]; `applicationShouldTerminate`:189 [persistFinalSnapshotBlocking]; `handleIncoming`:250 [presentExternalURL]

### 5.22 NookApp / ContentView / WindowView

NookApp injects `.environmentObject(browserManager.tabManager)` (50, 83) and runs `setupWindowState`/`setActiveWindowState`/`closeIncognitoWindow` in `setupApplicationLifecycle` (137-184); ContentView sets `windowState.tabManager` (38). WindowView reads `tabManager.currentSpace`, zoom commands and space settings.

- `App/NookApp.swift`: `setupApplicationLifecycle`:137 [closeIncognitoWindow, isIncognito, nookSettings, setActiveWindowState, setupWindowState]
- `App/ContentView.swift`: `body`:38 [tabManager]
- `App/Window/WindowView.swift`: `body`:29 [applyZoomLevel, currentSpace, currentSpaceId, id, resetZoomCurrentTab, showSpaceSettings, showTabClosureToast, spaces, zoomInCurrentTab, zoomOutCurrentTab]

### 5.23 Settings: Profiles, General, Air Traffic Control

Profiles: space list, counts (`spacesCount`, `tabsCount` via `allTabs()`+`spaceId`, `pinnedCount` via `spacePinnedTabs`), `assign(spaceId:toProfile:)`, `removeSpace`, `tabsBySpace[space.id]?.count`, `switchToProfile`, `deleteProfile`. General: `unloadAllInactiveTabs` (46).

- `Nook/Components/Settings/Tabs/Profiles.swift`: `body`:36 [currentProfile, icon, id, name, profileId, removeSpace, spaces, switchToProfile, tabsBySpace]; `spacesCount`:100 [profileId, spaces]; `tabsCount`:106 [allTabs, id, profileId, spaceId, spaces]; `pinnedCount`:118 [id, profileId, spacePinnedTabs, spaces]; `showCreateDialog`:150 [switchToProfile]; `startDelete`:209 [deleteProfile]; `assignAllSpacesToCurrentProfile`:247 [assign, currentProfile, id, spaces]; `resetAllSpaceAssignments`:258 [assign, id, spaces]; `SpaceAssignmentRowView`:271 []; `canDelete`:275 [spaces]; `currentProfileName`:374 [profileId]; `assign`:386 [assign, id]
- `Nook/Components/Settings/Tabs/General.swift`: `body`:46 [unloadAllInactiveTabs]

### 5.24 Drag and drop

`NookDragItem { tabId, title, urlString }` + `DropZoneID { essentials, spacePinned(UUID), spaceRegular(UUID), folder(UUID) }` bridged to `TabDragManager.DragContainer` (NookDragItem.swift:26). `NookDragSessionManager.makeDragOperation` ("Bridge to TabManager", 380) builds `TabDragManager.DragOperation(tab: Tab, ...)`; drop handlers in PinnedGrid/SpaceView/TabFolderView/SpaceTitle/FallbackDrop call `tabManager.handleDragOperation`. `NookDragSourceView` and `NookDragPreviewWindow` hold `Tab?` for favicon/title. `DropZoneID` maps to `Parent`; `handleDragOperation` maps to `TabTree.dropTarget` + `move`. `.tabManagerDidLoadInitialData` is declared in TabDragManager.swift:22, posted at TabManager.swift:1980, observed nowhere.

- `Nook/Components/DragDrop/NookDragItem.swift`: no direct model/BM/window-state member hits (see note)
- `Nook/Components/DragDrop/NookDragSessionManager.swift`: `NookDragSessionManager`:35 []; `beginDrag`:188 []; `makeDragOperation`:382 []
- `Nook/Components/DragDrop/NookDragSourceView.swift`: `NookDragSourceCoordinator`:14 []; `init`:19 []; `DragSourceAnchor`:104 []; `NookDragSourceView`:136 []
- `Nook/Components/DragDrop/NookDropZoneHostView.swift`: no direct model/BM/window-state member hits (see note)
- `Nook/Components/DragDrop/NookDragPreviewWindow.swift`: `NookMorphingPreview`:158 []; `pinnedTilePreview`:223 [favicon]; `standardPreview`:255 [favicon]
- `Nook/Managers/DragManager/TabDragManager.swift`: `DragOperation`:27 []
- `Nook/Managers/DragManager/DragLockManager.swift`: no direct model/BM/window-state member hits (see note)
- `Nook/Components/Sidebar/FallbackDropBelowEssentialsModifier.swift`: `handleFallbackDrop`:19 [allTabs, handleDragOperation, id]; `currentSpacePinnedZone`:29 [currentSpaceId]

### 5.25 PinnedGrid / PinnedTabView (favorites)

PinnedGrid: `essentialTabs(for: effectiveProfileId)` (32), select via `selectTab`, `hoveredPinnedTabId`, drop via `handleDragOperation`, `PinnedTile` `@ObservedObject var tab: Tab` (253) reads `isUnloaded`. PinnedTabView takes primitives (no model coupling). EditPinnedURLDialog reads `pinnedURL/url/displayName/favicon` (becomes home URL edit: `setHomeToCurrent`/`setURL`).

- `Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift`: `body`:30 [currentProfile, currentProfileId, currentTab, essentialTabs, favicon, hoveredPinnedTabId, id, isUnloaded, selectTab, url]; `handleEssentialsDrop`:171 [allTabs, handleDragOperation, id]; `handleEssentialsReorder`:185 [handleDragOperation]; `safeTitle`:224 [displayName, url]; `PinnedTile`:253 []
- `Nook/Components/Sidebar/PinnedButtons/PinnedTabView.swift`: no direct model/BM/window-state member hits (see note)
- `Nook/Managers/DialogManager/Dialogs/EditPinnedURLDialog.swift`: `init`:21 [displayName, favicon, pinnedURL, url]

### 5.26 SpaceView / SpaceTab / TabFolderView / SplitTabRow / SpaceTitle

SpaceView is the largest consumer: computed `tabs`, `spacePinnedTabs`, `folders`, `regularFolderRows` caches, `.onReceive("TabFoldersDidChange")` (194), row closures (`forceRemoveTab`, `unloadTabMovingSelection`, `clearRegularTabs`), `addTabToFolder`, scroll/arrow indicators via `currentTabForActiveWindow`. `SpaceTab` and `SplitHalfTab` are `@ObservedObject var tab: Tab` and use rename state (`isRenaming`, `editingName`, `saveRename`) that lives on Tab. TabFolderView is `@ObservedObject var folder: TabFolder` (`isOpen`, `name`, `toggleFolder`, `renameFolder`, alphabetize via `moveTabToFolder`). Spec replaces all with `visibleRows` in a `LazyVStack`.

- `Nook/Components/Sidebar/SpaceSection/SpaceView.swift`: `FolderWithTabs`:13 []; `hash`:18 [id]; `SpaceView`:34 []; `tabs`:83 [ephemeralTabs, index, isIncognito, tabs]; `spacePinnedTabs`:90 [id, isIncognito, spacePinnedTabs]; `folders`:98 [folders, id, isIncognito, isRegular]; `rowCount`:108 [folderId, id, isOpen]; `regularFolderRows`:117 [id, isIncognito, regularFolders]; `spacePinnedItems`:149 [folderId, id, index]; `body`:178 [id]; `handlePendingDrop`:219 [allTabs, handleDragOperation, id]; `handlePendingReorder`:254 [allTabs, handleDragOperation, id]; `mainContentContainer`:296 [id]; `pinnedTabsList`:406 [id]; `updateSpacePinnedCaches`:453 [folderId, id]; `pinnedTabView`:460 [displayName, forceRemoveTab, id, unloadTabMovingSelection, url]; `newTabButtonSectionWithClear`:525 [clearRegularTabs, folderId, id]; `regularTabsContent`:563 [id]; `splitTabsView`:583 [id]; `regularTabsView`:609 [folderId, id, index, regularFolders]; `updateRegularTabsCaches`:635 [folderId, id]; `regularTabView`:641 [displayName, id, url]; `deleteFolder`:678 [deleteFolder, id]; `addTabToFolder`:682 [createNewTab, id, moveTabToFolder]; `handleUserTabActivation`:731 []; `updateActiveTabPosition`:744 [currentTabForActiveWindow, id, spaceId]; `updateArrowIndicators`:762 [currentTabForActiveWindow, id, spaceId]; `scrollToActiveTab`:786 [currentTabForActiveWindow, id, spaceId]
- `Nook/Components/Sidebar/SpaceSection/SpaceTab.swift`: `SpaceTab`:11 []; `body`:39 [cancelRename, displayName, editingName, ensureFaviconLoaded, favicon, hasAudioContent, hasPlayingAudio, isAudioMuted, isRenaming, isUnloaded, saveRename, startRenaming]; `isCurrentTab`:165 [currentTab, id]
- `Nook/Components/Sidebar/SpaceSection/TabFolderView.swift`: `TabFolderView`:13 []; `tabsInFolder`:30 [folderId, id, regularFolderTabs, spacePinnedTabs]; `isDropTargeted`:45 [id]; `body`:54 [isOpen]; `handleFolderDrop`:73 [allTabs, handleDragOperation, id]; `handleFolderReorder`:87 [handleDragOperation, id]; `folderHeader`:105 [accentColor, id, isOpen, name, toggleFolder]; `folderContent`:200 [id]; `folderTabView`:238 [displayName, forceRemoveTab, id, toggleMute, url]; `alphabetizeTabs`:276 [id, moveTabToFolder, name]; `startRenaming`:289 [name]; `cancelRename`:295 [name]; `commitRename`:301 [id, name, renameFolder]
- `Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift`: `SplitTabRow`:4 []; `SplitHalfTab`:42 []; `body`:58 [displayName, favicon, id, index, spaceId, url]; `isActive`:126 [currentTab, id]
- `Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift`: `SpaceTitle`:7 []; `body`:21 [accentColor, allTabs, handleDragOperation, icon, id, name, persistSnapshot, showSpaceSettings, spacePinnedTabs]; `isDropHovering`:148 [id, spacePinnedTabs]; `canDeleteSpace`:164 [spaces]; `startRenaming`:170 [name]; `cancelRename`:176 [name]; `commitRename`:182 [id, name, renameSpace]; `deleteSpace`:196 [id, removeSpace]; `createFolder`:200 [createFolder, id]; `assignProfile`:204 [assign, id]
- `Nook/Components/Sidebar/SpaceSection/SpaceProfileBadge.swift`: `SpaceProfileBadge`:13 []; `assignedProfile`:19 [profileId]; `isCurrentProfile`:29 [currentProfile]

### 5.27 Spaces switcher, bottom bar

Space paging over `tabManager.spaces` or `windowState.ephemeralSpaces` (incognito), `setActiveSpace(_:in:)`, `createSpace` + `assign`, `createFolder(for: currentSpace.id)`, `makeSpaceView` wires `selectTab`/`removeTab` closures (327-328).

- `Navigation/Sidebar/SpacesSideBarView.swift`: `spacesPageView`:143 [ephemeralSpaces, isIncognito, spaces]; `spacesContent`:156 [currentSpaceId, id, setActiveSpace]; `sidebarContextMenu`:236 [createFolder, currentSpace, id]; `handleSpaceIndexChange`:294 [setActiveSpace]; `makeSpaceView`:306 [currentProfile, currentSpaceId, id, isIncognito, profileId, removeTab, selectTab, toggleMute]; `showSpaceCreationDialog`:354 [assign, createSpace, id, spaces]; `resolveCurrentSpace`:378 [currentSpace, currentSpaceId, ephemeralSpaces, id, isIncognito, spaces]
- `Navigation/Sidebar/SpacesList/SpacesList.swift`: `layoutMode`:21 [ephemeralSpaces, isIncognito, spaces]; `visibleSpaces`:30 [ephemeralSpaces, isIncognito, spaces]; `body`:49 [currentSpaceId, id, name]
- `Navigation/Sidebar/SpacesList/SpacesListItem.swift`: `SpacesListItem`:16 []; `init`:27 []; `body`:44 [id, removeSpace, setActiveSpace, showSpaceSettings, spaces]; `spaceIcon`:82 [accentColor, icon]
- `Navigation/Sidebar/SidebarBottomBar.swift`: `body`:25 [isIncognito]; `newSpaceButton`:66 [createFolder, currentSpace, id]

### 5.28 Context menus

TabContextMenu (`@ObservedObject var tab: Tab`, `@EnvironmentObject tabManager`): placement (`pinTab`, `unpinTab`, `pinTabToSpace`, `unpinTabFromSpace`), add to folder, move to space, edit (rename override, reset/edit pinned URL, duplicate), state (mute, unload), close (close, close others, close below). SpaceContextMenu: `assign`, delete confirmation counts. FolderContextMenu: holds `TabFolder`, actions via closures.

- `Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift`: `TabContextMenu`:25 []; `placementSection`:48 [isPinned, pinTab, pinTabToSpace, spaceId, unpinTab, unpinTabFromSpace]; `addToFolderMenu`:89 [folders, id, moveTabToFolder, name, spaceId]; `moveToSpaceMenu`:110 [id, moveTab, spaceId, spaces]; `spaceLabel`:126 [icon, name]; `editSection`:146 [debouncedPersistSnapshot, displayNameOverride, duplicateTab, hasNavigatedAwayFromPinnedURL, loadURL, pinnedURL, resetToPinnedURL, startRenaming, url]; `stateSection`:239 [hasAudioContent, isAudioMuted, isUnloaded, toggleMute, unloadAllInactiveTabs, unloadTabMovingSelection]; `closeSection`:275 [closeAllTabsBelow, closeOtherTabs, forceRemoveTab, id, isPinned, isSpacePinned, removeTab, spaceId, tabsBySpace]
- `Nook/Components/Sidebar/ContextMenus/FolderContextMenu.swift`: `FolderContextMenu`:13 []
- `Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift`: `SpaceContextMenu`:14 []; `body`:29 [assign, id, profileId]; `showDeleteConfirmation`:85 [icon, id, name, spacePinnedTabs, spaces, tabsBySpace]; `currentProfileName`:109 [profileId]; `currentProfileIcon`:118 [profileId]

### 5.29 URL bar / top bar / nav buttons / status bar

All live-page reads from `browserManager.currentTab(for: windowState)`: `url`, `name`, `pageBackgroundColor`, `topBarBackgroundColor`, `hasVideoContent`, `hasPiPActive`, `requestPictureInPicture`, `isLoading`, `stop`, `refresh`, back/forward through `getWebView(for:in:)`. `ObservableTabWrapper` (NavButtonsView.swift:13) KVO-observes webview and `tab.$loadingState`. TopBarView.swift:560 reads global `tabManager.currentTab`. Status bar link hover is set in WebsiteView `setupHoverCallbacks`.

- `Nook/Components/Sidebar/URLBarView.swift`: `body`:20 [currentTab, hasPiPActive, hasVideoContent, requestPictureInPicture, url]; `displayURL`:133 [url]; `isSecure`:138 [url]; `displayHost`:139 [url]; `displayPath`:140 [url]
- `Nook/Components/Sidebar/TopBar/TopBarView.swift`: `body`:29 [currentTab, currentTabHasPiPActive, hasVideoContent, id, pageBackgroundColor]; `navigationControls`:174 [isLoading, stop]; `urlBar`:195 [currentTab, url]; `updateCurrentTab`:252 [currentTab]; `goBack`:257 [getWebView, goBack, id]; `goForward`:270 [getWebView, goForward, id]; `refreshCurrentTab`:282 [refresh]; `shouldAnimateColorChange`:287 [currentTab, id]; `topBarBackgroundColor`:293 [currentTab, pageBackgroundColor, topBarBackgroundColor]; `navButtonColor`:311 [currentTab, pageBackgroundColor, topBarBackgroundColor]; `urlBarBackgroundColor`:331 [currentTab, pageBackgroundColor, topBarBackgroundColor]; `urlBarTextColor`:372 [currentTab, pageBackgroundColor, topBarBackgroundColor]; `bottomBorderColor`:391 [currentTab, pageBackgroundColor, topBarBackgroundColor]; `displayURL`:442 [currentTab, name, url]; `pipButton`:501 [currentTabHasPiPActive, requestPictureInPicture]; `backgroundColor`:560 [currentTab, topBarBackgroundColor]
- `Nook/Components/Sidebar/NavButtonsView.swift`: `ObservableTabWrapper`:14 []; `canGoBack`:26 [canGoBack, getWebView, id]; `canGoForward`:36 [canGoForward, getWebView, id]; `updateTab`:42 []; `observeWebView`:63 [getWebView, id]; `observeLoadingState`:80 [loadingState]; `body`:174 [currentTab, id, isLoading, stop]; `updateCurrentTab`:208 [currentTab]; `goBack`:213 [getWebView, goBack, id]; `goForward`:222 [getWebView, goForward, id]; `refreshCurrentTab`:230 [refresh]
- `Nook/Components/Navigation/NavigationHistoryContextMenu.swift`: `body`:66 [currentTab, id]; `loadHistoryItemsFresh`:76 [assignedWebView, currentTab, getWebView, id]; `navigateToHistoryItem`:109 [assignedWebView, currentTab, getWebView, id]

### 5.30 WebContextMenu / FocusableWKWebView

`FocusableWKWebView.owningTab` (weak Tab): `activate`, `isOptionKeyDown`, `pendingContextMenuPayload`, `tab.browserManager` for downloads. `openLinkInNewTab` (WebContextMenu.swift:381-387) handles private window (`createEphemeralTab`, preserves `currentTabId`) or `createNewTab(url:in: space of owningTab)`.

- `Nook/Utils/WebKit/WebContextMenu.swift`: `performAction`:319 [url]; `openLinkInNewTab`:377 [browserManager, createEphemeralTab, createNewTab, currentTabId, ephemeralProfile, id, incognitoWindow, spaceId, spaces]
- `Nook/Utils/WebKit/FocusableWKWebView.swift`: `FocusableWKWebView`:9 []; `mouseDown`:29 [activate, isOptionKeyDown]; `rightMouseDown`:40 [activate]; `mouseUp`:52 [isOptionKeyDown]; `prepareMenu`:74 [pendingContextMenuPayload]; `resolveImageURL`:193 [url]; `initiateDownload`:233 [url]; `registerDownload`:251 [browserManager]; `applyPendingContextMenuIfPossible`:404 [pendingContextMenuPayload]; `sanitizeDefaultMenu`:420 [pendingContextMenuPayload]
- `Nook/Utils/WebKit/WebContextMenuBridge.swift`: `WebContextMenuBridge`:12 []; `init`:15 []; `userContentController`:33 [deliverContextMenuPayload]
## 6. SwiftData references

| Entity | Defined | Referenced |
|---|---|---|
| `TabEntity` | Nook/Models/Tab/TabsModel.swift:12 | Schema BrowserManager.swift:32; TabManager.swift:178, 182, 244, 260, 377, 1759 (`toRuntime`), 1834 |
| `FolderEntity` | TabsModel.swift:71 | Schema BrowserManager.swift:33; TabManager.swift:179, 183, 280, 290, 1895 |
| `TabsStateEntity` | TabsModel.swift:103 | Schema BrowserManager.swift:34; TabManager.swift:219, 221, 1933 |
| `SpaceEntity` | Nook/Models/Space/SpaceModels.swift:15 | Schema BrowserManager.swift:30; TabManager.swift:180, 184, 304, 313, 378, 1801 |
| `ProfileEntity` | Nook/Models/Profile/ProfileEntity.swift:12 (`id` unique, `name`, `icon`, `index`) | Schema BrowserManager.swift:31; ProfileManager.swift:29 (load), 51 (create), 63-64 (update), 82-92 (reconcile/persist order) |
| `HistoryEntity`, `ExtensionEntity` | stay | Schema BrowserManager.swift:35-36; HistoryManager, ExtensionManager (unchanged) |

- TabManager.swift's entity use is all inside `PersistenceActor` (12-405) and load (`toRuntime` 1759, `loadFromStore` 1797-1990). Deleting TabManager.swift removes every Tab/Folder/Space/TabsState reference except the schema list.
- Importers (Arc.swift, Dia.swift, Safari.swift, ImportManager.swift) reference no entities; they go through BrowserManager -> TabManager API (section 5).
- ProfileManager is the only non-TabManager entity consumer. The spec keeps profile ids by importing `ProfileEntity` rows once. Foundation owns ProfileManager.swift.
- Risk (moderate confidence): `Persistence.init` (BrowserManager.swift:70) classifies open failures; on `.schemaMismatch` it backs up and **deletes the whole store** (`deleteStore()` at 106), which would also drop `HistoryEntity` and `ExtensionEntity` rows. Removing four `@Model` types from `Persistence.schema` should be a lightweight (inferred) migration, but verify on a copy of a real store before shipping, and remove entities only after the one-time profile import has run.
- Stale regression scripts to delete with TabManager: scripts/tests/tab-persistence-regression.swift, tab-persistence-regression.sh, tab-persistence-restoration.swift, tab-lifecycle-regression.py, tab-transfer-regressions.py.

## 7. Proposed partition

### 7.1 Principles

1. **Foundation lands first and keeps the old types compiling.** TabManager, Tab, TabFolder, Space stay in the tree, unused by migrated code, so every track branch builds against foundation on its own. One final **Delete** task removes them. Runtime is only correct after all tracks merge (Tab and PageSession cannot both own a live webview); verify the merged branch, not the tracks.
2. **Foundation owns every shared hotspot**: Tab.swift, TabManager.swift, BrowserManager.swift, BrowserWindowState.swift, NookApp.swift, ContentView.swift, AppDelegate.swift, ProfileManager.swift, WindowRegistry.swift.
3. **BrowserManager.swift is split by foundation in its first commit** (pure moves, no behavior change) so tracks can own the pieces:
   - `BrowserManager+Import.swift` (current 2245-2371: `importArcData/importDiaData/importSafariData`) -> **T5**.
   - `BrowserManager+ActivePage.swift` (1195-1272 current-page cookies/cache, 1405-1510 window-aware commands, URL copy, inspector; 2767-2871 zoom) -> **T3**. Signatures stay (`Void`/`Bool` returns), so T5 callers in NookCommands and KeyboardShortcutManager do not change.
   - Everything else tab related (`createNewTab`, `duplicateTab`, `closeCurrentTab`, `currentTab(for:)`, `selectTab`, `setActiveSpace`, `validateWindowStates`, `setupWindowState`, `applyStartupLoadMode`, keyboard selection helpers 2372-2445, incognito windows 2488-2640, profile switch/deletion, `undoCloseTab`) stays with **Foundation**.
4. Extension notification signatures are fixed by foundation (called from TabsController), implemented by T4.
5. Hotspot view files are single-owner: SpaceView.swift, TabContextMenu.swift (T1); SpacesSideBarView.swift, WindowView.swift (T2); WebsiteView.swift, TabCompositorView.swift, TopBarView.swift (T3); NookCommands.swift, KeyboardShortcutManager.swift (T5).
6. **Name collisions must be settled in foundation before any track imports the package.** NookTabsCore exports `Profile`, `Space` and `Section`. The app already declares `class Profile` (Nook/Models/Profile/Profile.swift, 97 references) and `class Space` (Space.swift, 105 references), and SwiftUI `Section` is used in 23 files (73 references), 6 of which are track files that will also need tab types (NookCommands.swift, SidebarMenuHistoryTab.swift, TabContextMenu.swift, AirTrafficControlSettingsView.swift, General.swift, Profiles.swift). Options: rename the core types (`TabProfile`/`TabSpace`/`TreeSection`), or have foundation expose app-side typealiases in one file and forbid `import NookTabsCore` in view files. Decide once in F; otherwise every track hits ambiguity errors independently. `Row`, `Item`, `Change`, `Scope`, `Parent` have no app declarations (string hits only).

### 7.2 Foundation API (derived from call sites above)

**`TabsController`** (`@MainActor @Observable final class`, injected via environment and `browserManager.tabs`):

Reads (replace 1.4 queries and `allTabs()`):
- `tree: TabTree` (read-only), `device: DeviceState`, `isReadOnly: Bool`
- `space(_ id: UUID) -> Space?`, `orderedSpaces: [Space]`, `spaces(inProfile: UUID) -> [Space]` (replaces `spaces` 56 sites, `ephemeralSpaces`)
- `item(_ id: UUID) -> Item?` (replaces `tabById`, most `allTabs().first { $0.id == }` 30+ sites)
- `children(of: Parent) -> [Item]`, `favorites(of profileID: UUID) -> [Item]` (replaces `tabs(in:)`, `spacePinnedTabs`, `essentialTabs`, `pinnedTabs`, `folders`, `regularFolders`, `regularFolderTabs`, `looseTabs`, `tabsBySpace`)
- `rows(space: UUID) -> [Row]` (visibleRows with `device.openFolders`; replaces SpaceView caches and "TabFoldersDidChange")
- `section(of:)`, `spaceID(of:)`, `profileID(of:)` (replaces `isPinned`, `isSpacePinned`, `folderId`, `spaceId`, `isGlobalPinned`)
- `items(inProfile: UUID) -> [Item]` (SearchManager `allTabsForCurrentProfile`, Profiles counts)
- `session(for itemID: UUID) -> PageSession?`, `sessions: [PageSession]` (all live incl. private), `session(for webView: WKWebView) -> PageSession?` (ContentBlockerManager.tab(for:), TabCompositorManager.findTabByWebView)
- `selectedItemID(in: BrowserWindowState) -> UUID?`, `selectedSession(in:) -> PageSession?`, `activeWindowSession: PageSession?` (replaces `currentTab(for:)` 61, `currentTabForActiveWindow()` 46, `tabManager.currentTab` 9)
- `displayOrder(in: BrowserWindowState) -> [UUID]` (replaces `tabsForDisplay(in:)` for compositor and Cmd+1..9)
- `isVisibleInAnyWindow(_ itemID: UUID) -> Bool` (compositor unload predicate)
- `isOpen(folder: UUID) -> Bool`, `hasLeftHome(_ itemID: UUID) -> Bool` (dot; replaces `hasNavigatedAwayFromPinnedURL`)
- `canReopenClosed: Bool`

Intents:
- `open(url: URL, in window: BrowserWindowState, placement: Placement) -> UUID?` with `.newTab / .background / .replaceCurrent`; optional `space: UUID?` or `parent: Parent?` override for routing, extensions, context-menu "open in space" (replaces `createNewTab` 23+6, `createEphemeralTab` 8, `BrowserManager.createNewTab(in:url:)`)
- `adopt(webView: WKWebView, url: URL, title: String, in window: BrowserWindowState, placement: Placement) -> UUID?` (Peek, mini window, popups; replaces `createNewTabWithWebView` 3, `createPopupTab` 1)
- `select(_ itemID: UUID, in: BrowserWindowState)`, `selectNext(in:)`, `selectPrevious(in:)`, `select(index: Int, in:)`, `selectLast(in:)` (replaces `selectTab` 27, `setActiveTab` 9)
- `setSpace(_ spaceID: UUID, in: BrowserWindowState)`, `selectNextSpace(in:)`, `selectPreviousSpace(in:)` (replaces `setActiveSpace` both layers)
- `close(_ itemID: UUID)`, `close(_ ids: [UUID])`, `closeSelected(in:)`, `reopenLastClosed(in:)` (replaces `removeTab`, `forceRemoveTab`, `closeActiveTab`, `closeOtherTabs`, `closeAllTabsBelow`, `clearRegularTabs`, `undoCloseTab`, `closeCurrentTab`)
- `move(_ itemID: UUID, to: Parent, after: UUID?)`, `drop(_ itemID: UUID, section: Parent, rows: [Row], index: Int, intoFolder: Bool)` (replaces `handleDragOperation` 8, `moveTabToFolder` 6, `moveTab`, `reorderRegular`)
- `pin(_:to: Parent)`, `unpin(_:)`, `rename(_:_ customTitle: String?)`, `duplicate(_:in: BrowserWindowState)`
- `resetToHome(_:)`, `setHomeToCurrent(_:)`, `setHome(_:url:)` (EditPinnedURLDialog)
- `createFolder(title: String, in: Parent, after: UUID?) -> UUID`, `toggleFolder(_:)`, `setAllFolders(open: Bool, space:)`
- `createSpace(profileID:name:icon:accentHex:after:) -> UUID`, `updateSpace(_:name:icon:accentHex:)`, `moveSpace(_:toProfile:after:)`, `deleteSpace(_:)`
- `createProfile(name:icon:) -> UUID`, `updateProfile(_:name:icon:)`, `deleteProfile(_:heir:)`
- `unload(_ itemID: UUID)`, `unloadAllHidden()`
- `apply(_ change: Change)` (TabOrganizationApplier undo)
- `flushSync()` (AppDelegate.applicationShouldTerminate)

**`PageSession`** (`@MainActor @Observable final class`, one per open item, split from Tab.swift):
- Identity: `itemID: UUID`, `isPrivate: Bool`, `profile: Profile?` (was `resolveProfile()`)
- Webview lifecycle: `webView: WKWebView?` (was `existingWebView`/`webView`), `activeWebView`, `assignedWebView`, `loadWebViewIfNeeded()`, `unload()`, `isUnloaded`, `assignWebView(_:toWindow:)`, `cleanupClone(_:)`, `tearDown()` (was `performComprehensiveWebViewCleanup`), `configure(_ webView:)`, `applyConfigurationOverride(_:)`, `static load(_ url: URL, in: WKWebView)`, `webProcessCrashCount`, `lastWebProcessCrashDate`
- Navigation: `url`, `title`, `favicon`, `load(_ url: URL)`, `navigate(to input: String)`, `refresh()`, `stop()`, `goBack()`, `goForward()`, `canGoBack`, `canGoForward`, `loadingState`, `isLoading`
- Media: `hasPlayingAudio`, `hasPlayingVideo`, `hasAudioContent`, `hasVideoContent`, `isAudioMuted`, `toggleMute()`, `setMuted(_:)`, `hasPiPActive`, `requestPictureInPicture()`, `checkMediaState()`, `updateTitle(_:)`
- Chrome: `pageBackgroundColor`, `topBarBackgroundColor`, `blockedRequestCount`, `isOAuthFlow`, `onLinkHover`, `onCommandHover`, `pendingContextMenuPayload`, `deliverContextMenuPayload(_:)`, `isOptionKeyDown`, `activate()`
- Find: `find(_:completion:)`, `findNext(completion:)`, `findPrevious(completion:)`, `clearFind()`
- Auth: `finishIdentityFlow(...)`
- Combine consumers (`tab.$loadingState` NavButtonsView.swift:80, `tab.objectWillChange` PageLoadingProgressBar.swift:49, 6 `@ObservedObject var tab`) must move to Observation.

**`FaviconCache`** (extracted from Tab statics): `image(for key:)`, `store(_:for:)`, `clear()`, `stats()`. Callers: CommandPaletteSuggestionView, HistorySuggestionItem, SidebarMenuHistoryTab (T5), CacheManager (T3).

**`BrowserWindowState`**: `spaceID: UUID?` (was `currentSpaceId`, 37 sites), `selectedItemBySpace: [UUID: UUID]` (was `activeTabForSpace`), computed `selectedItemID` (was `currentTabId`, 36 sites), `split: SplitRecord?` + `activeSplitSide`, `profileID` (was `currentProfileId`), `isIncognito`, private-window item storage (was `ephemeralTabs/ephemeralSpaces/ephemeralProfile`, 34 sites), `compositorVersion`/`refreshCompositor()` unchanged. Remove `tabManager` and computed `currentSpace`.

**BrowserManager facade kept by foundation** (so T3/T5 need no hotspot edits): `tabs: TabsController`, `getWebView(for itemID:in:)`, `createWebView(for:in:)`, `refreshCompositor(for:)`, `setMuteState(_:tabId:originatingWindowId:)`, `syncTabAcrossWindows(_:)`, `presentExternalURL(_:)`, `createNewWindow()`, `createIncognitoWindow()`, `closeIncognitoWindow(_:)`, `switchToProfile(_:context:in:)`, `deleteProfile(_:)`, `showSpaceSettings(for:)`, `refreshGradientsForSpace(_:animate:)` retyped to space id. Old `currentTab(for:)` and `currentTabForActiveWindow()` are removed, not aliased, so leftover callers fail to compile.

**Extension hooks** (foundation calls, T4 implements): `ExtensionManager.shared.notifyTabOpened(_ session: PageSession)`, `notifyTabActivated(new: PageSession, previous: PageSession?)`, `notifyTabClosed(itemID: UUID)`, `notifyTabPropertiesChanged(_ session: PageSession, properties:)`, `wakeBackgroundWorkers()`.

### 7.3 Tracks

| Track | Files | Lines in files | Coupled lines | Est. lines touched | Needs from foundation |
|---|---|---|---|---|---|
| **F Foundation** | 14 + new `Packages` wiring, `TabsController.swift`, `PageSession*.swift`, `FaviconCache.swift`, BrowserManager split files | 10,465 | 336 | 4,500-6,000 (PageSession split moves ~3,000 lines of Tab.swift; TabsController ~900 new; BrowserManager tab section ~900 rewritten; one-time ProfileEntity import ~80; final Delete removes ~6,000) | n/a |
| **T1 Sidebar outline, favorites, drag** | 16 | 3,396 | 243 | 1,800-2,300 (SpaceView rewrite to `rows(space:)` in LazyVStack; row views to Item + PageSession; DropZoneID -> Parent; delete DragManager/) | `rows(space:)`, `favorites(of:)`, `drop(...)`, `move`, `pin/unpin`, `rename`, `close`, `duplicate`, `unload`, `toggleFolder`, `createFolder`, `resetToHome/setHome`, `select`, `selectedItemID(in:)`, `session(for:)` media flags, `hasLeftHome`, `FaviconCache` |
| **T2 Spaces, profiles, settings chrome** | 13 | 2,991 | 164 | 450-650 | `orderedSpaces`, `spaces(inProfile:)`, `space(_:)`, `setSpace(_:in:)`, `createSpace/updateSpace/moveSpace/deleteSpace`, `createFolder`, `children(of:)` counts, `items(inProfile:)`, `unloadAllHidden`, window `spaceID`, private-window spaces |
| **T3 Page chrome and webview plumbing** (+ `BrowserManager+ActivePage.swift`) | 21 + 1 | 6,305 | 348 | 1,100-1,500 | `selectedSession(in:)`, `activeWindowSession`, `sessions`, `session(for webView:)`, `isVisibleInAnyWindow`, `displayOrder(in:)`, `unload`, full PageSession surface, `BrowserWindowState.split/selectedItemID`, `FaviconCache` |
| **T4 Extensions** | 9 | 3,791 | 101 | 400-600 (per-window `ExtensionWindowAdapter`, adapter keyed by item id) | `selectedSession(in:)`, `activeWindowSession`, `children(of:)`/`favorites(of:)` for window tab lists, `open(url:in:placement:)` with space override, `createSpace`, `setSpace`, `select`, `close`, `pin`, extension hook signatures |
| **T5 Intent callers** (+ `BrowserManager+Import.swift`) | 19 + 1 | 5,909 | 238 | 700-1,000 (organizer undo becomes `Change`) | `open`, `adopt(webView:...)`, `select*`, `setSpace`/next/prev, `closeSelected`, `reopenLastClosed`, `duplicate`, `move`, `createFolder`, `apply(_ change:)`, `items(inProfile:)`, `children(of:)`, `selectedSession(in:)`, `activeWindowSession`, tree-level create for imports, `FaviconCache` |
| **Delete** (after merge) | TabManager.swift (2,674), Tab.swift remnant, TabFolder.swift, TabsModel.swift, SpaceModels.swift, Space.swift, ProfileEntity.swift (270 together), Nook/Managers/DragManager/ (119), scripts/tests/tab-*, 4 schema entries | ~3,100 removed plus Tab.swift remnant | | | all tracks merged |

Totals check: 79 coupled files, all assigned, none shared (verified by script `tracks.py`, which asserts disjoint ownership).

### 7.4 Shared hotspots and ownership

| File | Coupled lines | Why hot | Owner |
|---|---|---|---|
| Nook/Managers/BrowserManager/BrowserManager.swift | 310 in 62 functions | global current tab, window selection, private windows, imports, zoom, all commands | F (splits off Import -> T5, ActivePage -> T3 in commit 1) |
| Nook/Models/Tab/Tab.swift | 3,524 lines | model + live page; 79 `browserManager`/`bm` accesses and 16 `ExtensionManager.shared` calls outbound | F (becomes PageSession files) |
| Nook/Managers/TabManager/TabManager.swift | 2,674 lines | everything | F, deleted in Delete |
| Nook/Models/BrowserWindowState.swift | 6 + 163 external field accesses (4.4) | selection model | F |
| Nook/Components/Sidebar/SpaceSection/SpaceView.swift | 82 | biggest sidebar consumer | T1 |
| Nook/Components/Browser/Window/TabCompositorView.swift | 49 | unload policy | T3 |
| Nook/Components/Sidebar/TopBar/TopBarView.swift | 49 | 20 `currentTab(for:)` reads | T3 |
| Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift | 47 | all placement intents | T1 |
| Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift | 47 | direct placement writes, undo | T5 |
| App/NookCommands.swift | 42 | 36 BrowserManager command calls | T5 |
| Nook/Components/Sidebar/SpaceSection/TabFolderView.swift | 40 | TabFolder observable | T1 |
| Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift | 35 | webview pool by tab x window | T3 |
| Navigation/Sidebar/SpacesSideBarView.swift | 32 | space paging + row closures | T2 |

Cross-track seams to watch:
- `SplitTabRow.swift` (T1) renders the split pair that `SplitViewManager.swift` (T3) manages; both read `BrowserWindowState.split` from F.
- `SpaceTitle.swift` (T2) handles empty pinned-section drops; it must call the same `drop(...)` intent T1 uses.
- `WindowView.swift` (T2) calls `TabOrganizerManager.organizeTabs` (T5) at 153; keep that signature `organizeTabs(in spaceID: UUID, using: TabsController)` fixed in F's API doc.
- `ExtensionManager+TabNotifications.swift` (T4) signatures are called by F.
- `CommandPaletteView.swift` (T5) and `SidebarMenuHistoryTab.swift` (T5) both use `FaviconCache` (F).
**F Foundation files** (file: total lines / coupled lines)

- `Nook/Models/Tab/Tab.swift`: 3524 / 0
- `Nook/Managers/TabManager/TabManager.swift`: 2674 / 0
- `Nook/Models/Tab/TabFolder.swift`: 41 / 0
- `Nook/Models/Tab/TabsModel.swift`: 111 / 0
- `Nook/Models/Space/Space.swift`: 52 / 0
- `Nook/Models/Space/SpaceModels.swift`: 36 / 0
- `Nook/Models/Profile/ProfileEntity.swift`: 29 / 0
- `Nook/Models/BrowserWindowState.swift`: 160 / 6
- `Nook/Managers/BrowserManager/BrowserManager.swift`: 2889 / 310
- `App/NookApp.swift`: 272 / 6
- `App/ContentView.swift`: 130 / 1
- `App/AppDelegate.swift`: 310 / 13
- `Nook/Managers/ProfileManager/ProfileManager.swift`: 162 / 0
- `Nook/Managers/WindowRegistry/WindowRegistry.swift`: 75 / 0

**T1 Sidebar outline, favorites, drag files** (file: total lines / coupled lines)

- `Nook/Components/Sidebar/SpaceSection/SpaceView.swift`: 816 / 82
- `Nook/Components/Sidebar/SpaceSection/SpaceTab.swift`: 180 / 22
- `Nook/Components/Sidebar/SpaceSection/TabFolderView.swift`: 307 / 40
- `Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift`: 142 / 10
- `Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift`: 277 / 21
- `Nook/Components/Sidebar/FallbackDropBelowEssentialsModifier.swift`: 34 / 4
- `Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift`: 305 / 47
- `Nook/Components/Sidebar/ContextMenus/FolderContextMenu.swift`: 37 / 1
- `Nook/Components/DragDrop/NookDragItem.swift`: 75 / 0
- `Nook/Components/DragDrop/NookDragSessionManager.swift`: 403 / 4
- `Nook/Components/DragDrop/NookDragSourceView.swift`: 154 / 4
- `Nook/Components/DragDrop/NookDropZoneHostView.swift`: 144 / 0
- `Nook/Components/DragDrop/NookDragPreviewWindow.swift`: 291 / 3
- `Nook/Managers/DragManager/TabDragManager.swift`: 41 / 1
- `Nook/Managers/DragManager/DragLockManager.swift`: 77 / 0
- `Nook/Managers/DialogManager/Dialogs/EditPinnedURLDialog.swift`: 113 / 4

**T2 Spaces, profiles, settings chrome files** (file: total lines / coupled lines)

- `Navigation/Sidebar/SpacesSideBarView.swift`: 402 / 32
- `Navigation/Sidebar/SpacesList/SpacesList.swift`: 132 / 16
- `Navigation/Sidebar/SpacesList/SpacesListItem.swift`: 85 / 7
- `Navigation/Sidebar/SidebarBottomBar.swift`: 84 / 4
- `Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift`: 212 / 25
- `Nook/Components/Sidebar/SpaceSection/SpaceProfileBadge.swift`: 64 / 3
- `Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift`: 125 / 10
- `Nook/Managers/DialogManager/Dialogs/SpaceEditDialog.swift`: 215 / 5
- `Nook/Components/Settings/Tabs/Profiles.swift`: 510 / 37
- `Nook/Components/Settings/Tabs/AirTrafficControlSettingsView.swift`: 258 / 10
- `Nook/Components/Settings/Tabs/General.swift`: 201 / 1
- `Nook/Components/Peek/PeekOverlayView.swift`: 344 / 3
- `App/Window/WindowView.swift`: 359 / 11

**T3 Page chrome and webview plumbing files** (file: total lines / coupled lines)

- `Nook/Components/Browser/Window/TabCompositorView.swift`: 385 / 49
- `Nook/Managers/WebViewCoordinator/WebViewCoordinator.swift`: 370 / 35
- `Nook/Components/WebsiteView/WebsiteView.swift`: 894 / 25
- `Nook/Components/WebsiteView/PageLoadingProgressBar.swift`: 116 / 5
- `Nook/Components/WebsiteView/WebsiteLoadingIndicator.swift`: 55 / 1
- `Nook/Components/Sidebar/TopBar/TopBarView.swift`: 568 / 49
- `Nook/Components/Sidebar/URLBarView.swift`: 181 / 14
- `Nook/Components/Sidebar/NavButtonsView.swift`: 274 / 18
- `Nook/Components/Navigation/NavigationHistoryContextMenu.swift`: 148 / 5
- `Nook/Managers/SplitViewManager/SplitViewManager.swift`: 446 / 25
- `Nook/Components/Browser/Window/SplitDropCaptureView.swift`: 178 / 2
- `Nook/Managers/FindManager/FindManager.swift`: 121 / 9
- `Nook/Components/FindBar/FindBarView.swift`: 170 / 0
- `Nook/Managers/PiPManager.swift`: 130 / 10
- `Nook/Managers/MediaControlsManager/MediaControlsManager.swift`: 337 / 30
- `Nook/Components/Sidebar/MediaControls/MediaControlsView.swift`: 296 / 15
- `Nook/Managers/AuthenticationManager/AuthenticationManager.swift`: 265 / 11
- `Nook/Managers/ContentBlockerManager/ContentBlockerManager.swift`: 459 / 25
- `Nook/Managers/CacheManager/CacheManager.swift`: 364 / 3
- `Nook/Utils/WebKit/FocusableWKWebView.swift`: 422 / 13
- `Nook/Utils/WebKit/WebContextMenuBridge.swift`: 126 / 4

**T4 Extensions files** (file: total lines / coupled lines)

- `Nook/Managers/ExtensionManager/ExtensionBridge.swift`: 292 / 24
- `Nook/Managers/ExtensionManager/ExtensionManager+Delegate.swift`: 1062 / 24
- `Nook/Managers/ExtensionManager/ExtensionManager+Installation.swift`: 900 / 2
- `Nook/Managers/ExtensionManager/ExtensionManager+TabNotifications.swift`: 203 / 17
- `Nook/Managers/ExtensionManager/ExtensionManager.swift`: 236 / 5
- `Nook/Components/Extensions/ExtensionActionView.swift`: 180 / 7
- `Nook/Components/Extensions/ExtensionLibraryButton.swift`: 103 / 1
- `Nook/Components/Extensions/ExtensionLibraryMoreMenu.swift`: 303 / 3
- `Nook/Components/Extensions/ExtensionLibraryView.swift`: 512 / 18

**T5 Intent callers (commands, palette, AI, routing, peek, organizer) files** (file: total lines / coupled lines)

- `App/NookCommands.swift`: 412 / 42
- `Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift`: 578 / 31
- `CommandPalette/CommandPaletteView.swift`: 604 / 13
- `CommandPalette/CommandPalette Accessories/TabSuggestionItem.swift`: 62 / 3
- `CommandPalette/CommandPalette Accessories/CommandPaletteSuggestionView.swift`: 128 / 2
- `CommandPalette/CommandPalette Accessories/HistorySuggestionItem.swift`: 129 / 2
- `Nook/Managers/SearchManager/SearchManager.swift`: 245 / 12
- `Nook/Managers/AIManager/Tools/BrowserToolExecutor.swift`: 497 / 15
- `Nook/Managers/AIManager/AIService.swift`: 417 / 2
- `Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift`: 103 / 10
- `Nook/Managers/PeekManager/PeekManager.swift`: 181 / 21
- `Nook/Managers/ExternalMiniWindowManager/ExternalMiniWindowManager.swift`: 302 / 9
- `Nook/Managers/TabOrganizerManager/TabOrganizerManager.swift`: 207 / 9
- `Nook/Managers/TabOrganizerManager/TabOrganizationApplier.swift`: 250 / 47
- `Nook/Managers/TabOrganizerManager/TabOrganizationPrompt.swift`: 144 / 3
- `Nook/Components/Sidebar/Menu/SidebarMenuHistoryTab.swift`: 690 / 5
- `Nook/Utils/WebKit/WebContextMenu.swift`: 399 / 9
- `Onboarding/OnboardingView.swift`: 140 / 2
- `Onboarding/Stages/SafariImportFlow.swift`: 421 / 1
