# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

Nook is a fast, minimal macOS browser with sidebar-first design. Built with Swift 5, SwiftUI, and WKWebView. Licensed GPL-3.0.

**Repo status**: `nook-browser/Nook` is the canonical repo and `origin`; Bain Gurley is the maintainer since September 2026. The project ran as the fork `l984-451/Nook` from March to September 2026 and that fork is archived. The 24 upstream commits from March 2026 that the fork never took (sidebar animation work) were superseded by the September remodel. Treat this repo as the only source of truth.

- **Minimum macOS**: 26.0 (Tahoe), Apple Silicon. Raised from 15.5 in September 2026; every `@available` / `#available` guard below 26 was removed at the same time. Do not add guards for versions below the deployment target.
- **Local toolchain**: Xcode 27.0 (27A266a, SDK 27.0) at `/Applications/Xcode.app`, installed September 2026; Xcode 16.4 stays at `/Applications/Xcode-16.4.0.app`. Xcode 27 ships without the Metal Toolchain (see Metal below). The deployment target is still 26.0, so macOS 27 APIs need the wrapper pattern in Key Patterns.
- **Swift language mode**: 5 (`SWIFT_VERSION = 5.0`). Swift 6 strict concurrency is not enabled; see `ASSESSMENT.md` for the warning inventory that would become errors.
- **Bundle ID**: `com.gstudios.nook`
- **Current Version**: 1.1.0 (build 110), released 2026-09-18 as the first release on `nook-browser/Nook` after upstream's 1.0.7 (notarized DMG, appcast item scoped so 1.0.x hosts see a link rather than an install).
- **NOT sandboxed** — runs with hardened runtime but no App Sandbox.
- **Passkeys are not supported.** Apple declined the `com.apple.developer.web-browser.public-key-credential` entitlement. It has been removed from the entitlements file. Do not add WebAuthn/passkey code paths that depend on it.

## Priorities

Use these to settle tradeoffs when a choice is not otherwise specified:

1. **macOS speed**: startup, tab switch, scroll, and sidebar interaction latency.
2. **Built-in ad blocking**: the content blocker pipeline is a core feature, not an add-on.
3. **Battery and CPU balance**: no polling timers, no busy observers, prefer notifications and WebKit callbacks. Heavy work (filter list compile, MLX inference) runs off the main actor, is cancellable, and unloads when idle. Extra processing is acceptable when it serves priority 1 or 2.

An iOS companion browser is under consideration. Nothing in the project targets iOS today (`SDKROOT = macosx`, AppKit throughout the drag system, windows, pasteboard, and haptics). Keep new model and manager code free of AppKit imports where that costs nothing, and put AppKit-only code in views or clearly named platform files.

## Build & Run

```bash
# Open in Xcode (single scheme: "Nook", single app target)
open Nook.xcodeproj

# Debug build, signed with your team
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build

# Debug build without signing (fresh machine, no team configured)
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO

# Release build (Apple Silicon only; MLX has no x86_64 slice)
xcodebuild -scheme Nook -configuration Release -arch arm64 -derivedDataPath build
```

**There is no test target.** `xcodebuild test -scheme Nook` fails. Verification is a build plus manual run. If the working tree holds someone else's uncommitted edits, verify committed work in a detached worktree (`git worktree add --detach /tmp/x HEAD`) with its own `-derivedDataPath` instead of building the dirty tree.

**Signing**: Set your Development Team in Xcode Signing settings. Team IDs in the project: `ZHB786H6YN` (Bain Gurley, local) and `96M8ZZRJK6` (CI). `Nook/Nook-CI.entitlements` is a reduced entitlements file used for the CI build step because push and autofill require provisioning profiles. The workflow's final re-sign also uses `Nook-CI.entitlements`. Release DMGs therefore lack push and autofill entitlements, and no provisioning profile is embedded. A local **signed** Debug build needs a Mac Team Provisioning Profile for `com.gstudios.nook`, which the September bundle-id change left uncreated; `xcodebuild ... -allowProvisioningUpdates` makes it, once. Without it the build fails at `GatherProvisioningInputs` with "No profiles for 'com.gstudios.nook' were found"; the unsigned invocation above sidesteps it.

**Metal**: One shader (`Onboarding/Components/ViewTransition.metal`). Xcode 26+ needs the Metal Toolchain component: `xcodebuild -downloadComponent MetalToolchain`.

**No SPM resolve needed**: Xcode resolves packages automatically on open. The `build/` directory holds package checkouts and is large (MLX).

**No bridging header.** The one ObjC dependency that needed one, `MuteableWKWebView`, is now a C target (`Sources/MuteableWKWebView`) inside the `NookWeb` package, re-exported as part of the `NookWeb` product. Packages cannot declare a bridging header, so this was the forcing function that removed it.

## Git Workflow

- **`develop`** is the development branch and the GitHub default branch. Commit and branch from here.
- **`main`** holds the last official release. Fast-forward it from `develop` when promoting a beta.
- **Releases are tags.** A push of `vX.Y.Z-beta.N` runs the notarize workflow as a beta: the app's marketing version becomes `X.Y.Z-beta.N`, the GitHub release is a prerelease titled "Nook X.Y.Z beta N" with a beta notice, and the appcast item is titled the same. A push of `vX.Y.Z` is the official release. Every tag needs its own `CURRENT_PROJECT_VERSION` bump first, since Sparkle orders by build number. Betas and official releases share the default Sparkle channel for now; a beta channel behind a Settings toggle comes with the first official release under the new bundle id.
- **Gitflow naming.** Short-lived work goes on `feature/<name>` or `hotfix/<name>` branched from `develop` (hotfixes from `main`), merged back and deleted. Only `main`, `develop` and `gh-pages` are long-lived and protected (deletion and force-push blocked, org admins bypass). The `release` branch was retired 2026-09-18 when tags took over.
- `feature/ios-chrome` holds the iOS visible chrome (bar, tab sheet, settings, dialogs, downloads, memory pressure, touch drag, iPad) as an iOS-only lineage branched from `0f2745c`. The same content also reached `develop` through unrelated PR merges, so a PR from it shows no diff; it is a readable record, not something to merge.
- `feature/download-memory` (local only, formerly `fix/download-memory`) is an unfinished WIP branch: URLSession-streamed downloads, based on an old commit; rebase onto `develop` before finishing.
- AI assistance must be disclosed per CONTRIBUTING.md.

## Architecture

### Manager-Based Pattern

The app uses ~30 specialized **Managers**, one per feature domain, coordinated through environment injection. All managers are `@MainActor` confined.

**Core managers:**

| Manager | Location | Responsibility |
|---------|----------|----------------|
| **BrowserManager** | `Nook/Managers/BrowserManager/` | Central coordinator (~1700 lines). Aggregates all other managers, window setup and startup loading, the active window's space. Being refactored toward independent injection. |
| **TabsController** | `Packages/NookWeb/Sources/NookWeb/TabsController*.swift` | The tab model (see Tab Model below): tree, device state, window selection, live `PageSession`s, every tab/folder/space intent, and one `Profile` (website data store) per space. `browserManager.tabs`, also injected with `.environment(tabs)`. macOS-only members (sidebar helpers) stay in `Nook/Browser/TabsController+macOS.swift`. |
| **ExtensionManager** | `Nook/Managers/ExtensionManager/` | WKWebExtension integration (12 files). Singleton, global across spaces, disabled in private tabs. See [Extension CLAUDE.md](Nook/Managers/ExtensionManager/CLAUDE.md) |
| **ContentBlockerManager** | `Packages/NookBlocker/Sources/NookBlocker/ContentBlockerManager.swift` | Ad/tracker blocking. See Content Blocker System below and `docs/adblocker-architecture.md` |
| **WindowRegistry** | `Packages/NookWeb/Sources/NookWeb/WindowRegistry.swift` | Multi-window state tracking. Single source of truth for all open windows |
| **WebViewCoordinator** | `Nook/Managers/WebViewCoordinator/` | WebView pool for multi-window tab display |

**Feature managers:**

| Manager | Purpose |
|---------|---------|
| **AIManager/** | AI chat: providers (Gemini, OpenRouter, Ollama, OpenAI-compatible), MCP client (Nook calls external servers), browser tool execution |
| **DevMCPServer/** | MCP server on `127.0.0.1:47823/mcp` so a coding agent can drive the running app. Built into every configuration, Debug and Release, but **off unless the user turns it on** in Settings > AI > Browser Control (`NookSettingsService.browserControlServerEnabled`, default false). See Key Patterns. |
| **SiteRoutingManager** | "Air Traffic Control": rules (domain + optional path prefix → target space) stored in `NookSettingsService.siteRoutingRules`. Guards run in `decidePolicyFor`, `createWebViewWith` (popups), and `AppDelegate` external URL handling. Longest path-prefix wins. Lives in `Packages/NookTweaks/Sources/NookTweaks/`, behind the `SiteRoutingHost` seam `BrowserManager` conforms to. |
| **SponsorBlockManager** | Built-in SponsorBlock: queries `sponsor.ajay.app` by hashed video ID, skips segments via `youtube-sponsorblock.js`. Lives in `Packages/NookTweaks/Sources/NookTweaks/`. |
| **YouTubeTweaks** | Stateless `YouTubeTweaks.apply` in `decidePolicyFor`: one document-start script in its own content world carrying CSS (hide Shorts, hide home shelves, `--ytd-rich-grid-items-per-row` override) and frame thumbnails (swaps `i.ytimg.com` thumbnails for the video's `hq1-3.jpg` stills). Settings live under Tweaks > YouTube (`SettingsTabs.youTube`, `Packages/NookUI/Sources/NookUI/Settings/YouTube.swift`). Lives in `Packages/NookTweaks/Sources/NookTweaks/`. |
| **FacebookTweaks** | Tweaks > Social Media > Facebook: hide the Reels carousel and suggested posts. Injects `facebook-feed-prune.js` (page world) with `reels`/`suggested` flags; see Content Blocker System. Lives in `Packages/NookTweaks/Sources/NookTweaks/`. |
| **SocialImageTweaks** | Download button on photos and videos on any site the user lists in Tweaks > Social Media (`settings.mediaDownloadSites`, seeded from the old per-site toggles and before them the single `settings.socialImageDownload`). Installed on the first visit to a listed site and rebuilt only when the list changes; the script gets the domains as `NOOK_DOWNLOAD_SITES` and suffix-matches the hostname. `social-image-download.js` (isolated world) finds media under the pointer, taking any https image or video, since a listed site may serve from any CDN; `social-video-source.js` (page world) reads MP4 URLs from React data because Facebook and Instagram play blob: URLs. Saves through the `MediaDownloading` seam (`FocusableWKWebView.downloadImage` on the app side). Lives in `Packages/NookTweaks/Sources/NookTweaks/`. |
| **TabOrganizerManager/** | On-device LLM tab grouping via MLX. `LocalLLMEngine` owns model download, load, idle unload, and memory-pressure response. Apple Silicon only. Stays in `Nook/Managers/TabOrganizerManager/`. |
| **DialogManager/** | Modal dialogs: space creation and editing, basic auth, settings, import, confirmations |
| **DownloadManager/** | File downloads via `WKDownloadDelegate`. Stays in `Nook/Managers/DownloadManager/`, unchanged by the phase 2 package split; see the ios-port design doc for the planned rewrite on `fix/download-memory`. |
| **FindManager/** | In-page find/search |
| **HistoryManager** | Browsing history, SwiftData persistence. Lives in `Packages/NookWeb/Sources/NookWeb/` (`HistoryManager.swift`, `HistoryEntity.swift`). |
| **ImportManager/** | Browser import from Safari, Arc, and Dia |
| **KeyboardShortcutManager/** | Global + website-specific keyboard shortcuts |
| **PeekManager/** | Quick-preview overlay for links (PeekSession + PeekWebView) |
| **PrivacyManager/** | `OAuthDetector` (OAuth flows get ad-block exemptions). `OAuthDetector` itself lives in `Packages/NookBlocker/Sources/NookBlocker/`. |
| **SearchManager** | Search engine integration. Lives in `Packages/NookWeb/Sources/NookWeb/`. |
| **SplitViewManager/** | Split-screen tab viewing |
| **ZoomManager/** | Page zoom controls |
| **PiPManager** | Picture-in-Picture mode |
| **CacheManager**, **CookieManager** | Web cache and cookie storage/clearing |
| **AuthenticationManager** | HTTP Basic auth dialogs |
| **MediaControlsManager** | Audio/media integration |
| **GradientColorManager** | Publishes the active space's `accentColor` / `accentNSColor` (name predates the September 2026 remodel; there is no gradient any more) |
| **HoverSidebarManager** | Sidebar hover interactions (NSTrackingArea-based, not SwiftUI `.onHover`) |
| **ExternalMiniWindowManager** | Mini browser windows |

### State Management

- **`@Observable`** (Swift Observation): `TabsController`, `PageSession`, `Profile`, `BrowserWindowState`, `WebViewCoordinator`, `WindowRegistry`, `AIService`
- **`@Published` / `ObservableObject`** (Combine): `BrowserManager`, `ExtensionManager`, `NookDragSessionManager`, `PeekManager`
- **JSON files**: tabs, folders, spaces and window state (`TabStore`, see Tab Model)
- **SwiftData**: `HistoryEntity`, `ExtensionEntity`. `ProfileEntity` is read once, only to seed spaces on a first launch that has no tab files but does have data stores worth keeping. `SpaceEntity`, `TabEntity`, `FolderEntity`, `TabsStateEntity` in `Nook/Models/Legacy/LegacyTabEntities.swift` are unused tables that stay in `Persistence.schema`: removing a model would change the schema of the store that also holds history and extensions.
- **UserDefaults**: `NookSettingsService` (all app settings)
- All state is `@MainActor` confined.

### App Entry & Window Hierarchy

```
NookApp.swift          — @main entry, WindowGroup scene, environment injection
  └─ ContentView.swift — Per-window container, registers with WindowRegistry
       └─ WindowView   — Main browser: Sidebar + WebsiteView + TopBar + StatusBar
```

**Environment injection**: `NookApp` creates `BrowserManager`, `WindowRegistry`, `WebViewCoordinator`, `NookSettingsService`, `KeyboardShortcutManager`, `AIConfigService`, `MCPManager`, `AIService` and injects them as `@EnvironmentObject` / `@Environment`. Each window gets its own `BrowserWindowState`.

### Packages

Seven local SPM packages under `Packages/`, wired into `Nook.xcodeproj` as local package dependencies, added in the September 2026 phase 2 port work. Each has its own `Package.swift`; read those for exact dependency products.

| Package | Depends on | Holds |
|---------|-----------|-------|
| `NookTabsCore` | none (Foundation only) | The tab tree model: `SpaceRecord`, `Item`, `OrderKey`, `TabTree`, `DeviceState`, `TabStore`. Unchanged by phase 2; see Tab Model below. |
| `NookSettings` | none (Foundation only) | `NookSettingsService` plus every persisted value type it stores (`SiteRoutingRule`, `SponsorBlockCategory`/`SkipOption`, AI provider and MCP config structs, `SearchProvider`, appearance/tab/startup enums). Window-navigation state (`currentSettingsTab`) stayed in the app. |
| `NookDesign` | none | `NookDesign.swift` (design tokens), `View+GlassEffect.swift`, `Color+Hex.swift`. The one file allowed a platform conditional on a token value (`Size.row`: 32 macOS, 44 iOS). |
| `NookBlocker` | `NookSettings` | The content blocker: `ContentBlockerManager`, `FilterListManager`, `ContentRuleListCompiler`, `RustContentBlockingConverter`, `AdvancedRulesEngine`, `BlockerEngine`, `TrackingParamStripper`, `OAuthDetector`, `WKUserScript+NookOwned.swift`, the JS in `Resources/`, and the Rust FFI as a `binaryTarget` over `Nook/ThirdParty/AdblockRustFFI/NookAdblock.xcframework`. |
| `NookTweaks` | `NookSettings`, `NookBlocker` | Site tweak managers: YouTube, Facebook, SocialImage, SponsorBlock, SiteRouting, plus their JS in `Resources/`. |
| `NookWeb` | `NookTabsCore`, `NookSettings`, `NookDesign`, `NookBlocker`, `NookTweaks`, FaviconFinder | `TabsController`, `PageSession`, `BrowserWindowState`, `WindowRegistry`, `SearchManager`, `FaviconCache`, `HistoryManager`, `Profile`, `BrowserConfig`, and the ObjC `MuteableWKWebView` as a C target. |
| `NookUI` | `NookBlocker`, `NookDesign`, `NookSettings`, `NookTabsCore`, `NookTweaks`, `NookWeb` | Shared SwiftUI: the tab/folder/space rows, `SpacesList`, the three context-menu builders, `EmptyWebsiteView`, the toasts, the settings tab bodies for General, Appearance, Spaces, Ad Blocker, Air Traffic Control, YouTube and Social Media, and `NookSettingsEnvironment.swift`, the `\.nookSettings` environment key both app targets inject. |

Platform differences are resolved in `NookDesign.swift` or in the thin wrapper files (`Platform.swift` in `NookWeb`, `Haptics.swift` and `HoverTracking.swift` in `NookUI`), never in view bodies; a file that would need more than one `#if os` gets a `+macOS.swift` sibling instead (e.g. `Nook/Browser/TabsController+macOS.swift`, `BrowserWindowState+macOS.swift`).

Every package targets `.macOS("26.0"), .iOS("26.0")` and Swift language mode 5 as groundwork for the eventual iOS port; only macOS ships today.

### Top-Level Modules

| Directory | Purpose |
|-----------|---------|
| `App/` | Entry point (`NookApp.swift`), `AppDelegate`, `ContentView`, window management, `NookCommands` |
| `Packages/` | The seven local packages described above. These are SPM packages, resolved by Xcode on open; adding a file inside one needs no project.pbxproj edit, but adding a new package still means wiring it in as a dependency through Xcode's Package Dependencies UI. |
| `Nook/Managers/` | ~30 feature managers (business logic) |
| `Nook/Models/` | Data models and SwiftData entities |
| `Nook/Components/` | SwiftUI views. `Settings/` holds `SettingsWindow` (NavigationSplitView sidebar) and the `SettingsTabs` enum in `SettingsUtils.swift` (12 tabs: general, appearance, ai, privacy, adBlocker, airTrafficControl, spaces, shortcuts, extensions, advanced, plus youTube and socialMedia under the sidebar's "Tweaks" section, which holds per-site tweaks and SponsorBlock) |
| `Nook/Extensions/` | Swift extensions; one file left, `NSUserInterfaceItemIdentifier+WebKit.swift` (`View+GlassEffect.swift` and `Color+Hex.swift` moved into `Packages/NookDesign`) |
| `Nook/Utils/` | Utilities, WebKit extensions (`FocusableWKWebView.swift`, `WebContextMenu.swift`), `WebStoreInjector.js` (Chrome Web Store install button) |
| `Nook/ThirdParty/` | Embedded dependencies, including the Rust FFI crate whose `NookAdblock.xcframework` output is consumed by `Packages/NookBlocker` |
| `Nook/Browser/` | One file, `TabsController+macOS.swift`: the macOS-only slice of the tab model that stayed out of `Packages/NookWeb` (see Tab Model below) |
| `CommandPalette/` | Command palette UI |
| `UI/` | Shared UI components |
| `Navigation/` | Sidebar structure (header, bottom bar, spaces list, context menus) |
| `Onboarding/` | 4 stages: Hello → TabLayout → Import (`SafariImportFlow`) → Final. Metal-shader transitions. |
| `docs/` | `adblocker-architecture.md`. Design specs, implementation plans and handoff notes are kept locally under `docs/superpowers/` and are gitignored; they are never committed. |
| `ASSESSMENT.md` | Build and warning audit snapshot from 2026-03-20. Numbers are stale; the category breakdown is still useful. |

## Design System

The September 2026 remodel (spec: `docs/superpowers/specs/2026-09-14-gui-remodel-design.md`) put every visual value in one file, `NookDesign.swift`. The phase 2 package split moved that file, along with `View+GlassEffect.swift` and `Color+Hex.swift`, into `Packages/NookDesign/Sources/NookDesign/`. Rules:

- **No literals in the UI layer.** Radii, spacing, sizes, fonts, animation curves, shadows, and fills come from `NookDesign.Radius / Spacing / Size / Font / Motion / Surface / Elevation`. Text colors are `.primary / .secondary / .tertiary`. When nothing fits, add a token with a comment saying what it is for; do not mint a token just to hide a number from a grep (a window's fixed size belongs in a `private let` in its view). `spacing: 0` and `lineWidth: 1` may stay literal.
- **Corners are continuous.** Build shapes with `NookDesign.Radius.shape(_:)`; CALayer corners get `cornerCurve = .continuous`.
- **Elevation, not shadows.** `.nookElevation(.flat / .raised / .floating)`. The modifier is branch-free so view identity is stable and shadows animate; use `isActive ? .raised : .flat` for conditional elevation.
- **Glass only on layers that float over content**: command palette, toasts, hover sidebar overlay, find bar, dialog cards, extension panels, split drop card. `nookGlassEffect(in:)` in `Packages/NookDesign/Sources/NookDesign/View+GlassEffect.swift` is the only entry point and already includes `.floating` elevation. The sidebar itself is `BlurEffectView(material: .sidebar)` in `WindowView`, and rows are `Surface` fills; never glass on glass.
- **Space color tints; spaces have no icon.** `SpacesList`/`SpacesListItem`, now in `Packages/NookUI/Sources/NookUI/Spaces/`, switch spaces with a row of dots (`NookDesign.Spacing.md` for the active dot, filled with `space.accentColor`; `NookDesign.Spacing.sm` and `.tertiary` for the rest), and every other space picker (`TabContextMenu`'s "Move to Space", `AirTrafficControlSettingsView`'s destination picker) shows plain text. `SpaceRecord.icon` still exists in `NookTabsCore` for on-disk/import compatibility (Arc import still writes one) but nothing reads it for display; `SpaceIconView`/`SpaceIconPicker` were deleted. `space.accentColor` also tints folder icons and drives `NookDesign.Surface.containerGradient`: the accent fading to `.windowBackgroundColor`, top to bottom, behind the sidebar and in `EmptyWebsiteView` ("Ah, peace."). The gradient's top stop is a blend toward `.windowBackgroundColor` (0.55 active / 0.8 inactive), not the raw accent, so it reads as a light tint rather than a solid color band. No blur or transparency: it's a static two-stop `LinearGradient`, cheaper than the `BlurEffectView` it replaced since nothing samples the backdrop per frame. Inactive windows blend further toward `.windowBackgroundColor` (`isActive` from `WindowRegistry.activeWindowId`), approximating the dimming `.followsWindowActiveState` used to give for free. Incognito windows use `SpaceGradient.incognito`'s neutral gray instead of the space's accent, under the existing purple `privateTint` overlay. Persisted as a one-node `SpaceGradient`; old multi-node data still decodes.
- **Space editing lives inline in Settings.** Renaming a space or changing its accent happens in Settings > Spaces (`SpacesSettingsView` in `Packages/NookUI/Sources/NookUI/Settings/Spaces.swift`): a `TextField` writes through `TabsController.updateSpace` on every keystroke, and an accent swatch opens `SpaceAccentPicker` in a popover. Every "Space Settings" entry point (window background context menu, the space switcher's title menu, the `SpaceContextMenu` builder, `BrowserManager.showSpaceSettings()`) sets `nookSettings.currentSettingsTab = .spaces` and opens the `Settings` scene, rather than presenting a dialog; from a non-View context (`BrowserManager`) that means `NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)` since there's no `\.openSettings` environment action outside a View. `SpaceCreationDialog` (New Space…) is the one remaining space-specific floating dialog, kept because creation is a distinct flow, not settings; it only asks for name and accent. `SpaceDeleteConfirmationDialog` (destructive confirmation) is also unchanged in kind, just icon-free.
- **Row geometry**: `Size.row` (32) tall, `Radius.md`, `Spacing.rowPadding` sides, `Spacing.rowGap` between rows. The drag session's `itemCellSize` / `itemCellSpacing` caches must equal these.
- **Context menus** are the three shared builders in `Packages/NookUI/Sources/NookUI/ContextMenus/` (`TabContextMenu(itemID:context:)`, `FolderContextMenu`, `SpaceContextMenu`). Do not add inline `.contextMenu` bodies to rows.
- **Settings** are a `Settings` scene laid out like System Settings: the sidebar is pinned open (`columnVisibility: .constant(.all)`, no sidebar toggle) and the selected tab's name is the window title. One file per tab, every tab a grouped `Form`; tweak footers do not add "applies on next load" notes; large entry lists (cache, cookies) stay in a virtualized `List` under the Form. General, Appearance, Spaces, Ad Blocker, Air Traffic Control, YouTube and Social Media live in `Packages/NookUI/Sources/NookUI/Settings/`; AI, Advanced, Extensions and Shortcuts stay app-side in `Nook/Components/Settings/Tabs/`.

## Tab Model

Spec: `docs/superpowers/specs/2026-09-15-tab-model-rebuild-design.md`. Replaced `TabManager`, `Tab`, `TabFolder` and `Space` in September 2026.

- **`NookTabsCore`** (`Packages/NookTabsCore`, Foundation only, `swift test` there): `SpaceRecord` (a space owns its data store, favorites, pinned section and tabs section; there is no profile record), `Item` (tab or folder) with one `Parent` (`.favorites(spaceID)`, `.pinned(spaceID)`, `.tabs(spaceID)`, `.folder(itemID)`), `OrderKey` string ordering, `TabTree` (every edit returns an undo `Change`; rules: parent exists, no cycles, folder depth 5, favorites hold tabs only; the loader repairs instead of throwing), `visibleRows` / `dropTarget`, `DeviceState` (open folders, open pages of pinned tabs, window records, reopen history capped at 50), `TabStore`.
- **Scope rule**: an item's scope comes from its section, and every section belongs to one space. Favorites and pinned (with their folders) are `.synced`: `url` is the home URL, the live page's URL goes to `DeviceState.openPages`, closing ends the page but keeps the item, and a row shows a dot when the page left home. The tabs section is `.device`: `url` is the last committed URL and closing removes the item. `TabsController.remove(_:)` deletes any item outright. Moving between sections moves the whole subtree across scopes.
- **Storage**: `~/Library/Application Support/com.gstudios.nook/Tabs/structure.json` (spaces and synced items with 30-day tombstones) and `device.json` (tabs-section items and `DeviceState`), each with `formatVersion`. Saves coalesce for 500 ms and write atomically; `flushSync()` runs in `applicationShouldTerminate`. After a good load both files are copied to `Tabs/Backups/<yyyy-MM-dd>/` (7 days kept). A file that fails to decode loads the newest backup; with no usable backup the app runs **read-only** (`TabsController.isReadOnly`, an alert names the reason, nothing is written that session). Missing files mean first launch: one space per existing `ProfileEntity` (same UUID, so data stores keep cookies) with one tab each, else a single space. `formatVersion` 1 files (profiles above spaces) migrate on load in `ProfileMerge`: each profile's first space takes the profile's id so its cookies and logins survive, later spaces keep their own id and start logged out, and the untouched files are copied to `Tabs/Backups/<date>-pre-merge/` first.
- **`TabsController`** (`Packages/NookWeb/Sources/NookWeb/TabsController*.swift`, with macOS-only slices left in the app at `Nook/Browser/TabsController+macOS.swift` and `Nook/Components/Sidebar/Outline/TabsController+Sidebar.swift`): `@MainActor @Observable`. It is constructed with settings, `windowRegistry`, blocker, sponsor block, site routing, history and `webViews` dependencies, and holds weak `sessionDelegate` / `tabEvents` / `alerts` references; `BrowserManager` supplies the concrete types and conforms to the delegate protocols in `BrowserManager+NookWeb.swift`. Views and managers call its intents (`open`, `select`, `close`, `remove`, `move`, `drop`, `pin`, `unpin`, `setSpace`, `reopenLastClosed`, space and folder intents, `apply(_:)` for the tab organizer's undo); tree errors are logged under the `Tabs` category and change nothing. There is no global current tab: read `window.selectedItemID` / `tabs.selectedSession(in:)`, or `tabs.activeWindowSession` for the focused window.
- **`PageSession`** (`Packages/NookWeb/Sources/NookWeb/PageSession*.swift`): one live page per open item (web view, navigation, media, find, scripts, UI delegate). Sessions exist only for items something opened (selection, split panes, startup warming, adopted Peek or popup views, extensions); `unload()` releases views and keeps the session, `tearDown()` ends it. It reports back through `pageCommitted` / `pageTitleChanged`. `FocusableWKWebView` stayed in the app (`Nook/Utils/WebKit/FocusableWKWebView.swift`) since it is an `NSView` subclass; it reaches its session through the `SessionWebView` seam, and its `owningSession` still points back to the `PageSession`.
- **Windows**: `BrowserWindowState` holds `spaceID`, `selectedItemBySpace` and `split`, mirrored into `DeviceState.windows`. `BrowserManager.setupWindowState` calls `tabs.attach(window:)` (claims an unclaimed saved record), loads only the selected page (with "Last Tab, Favorites & Space" the space's tabs-section pages then warm one at a time), and the first window reopens the other saved windows. Window close calls `tabs.detach(window:)`; quit keeps every record. A space change in the active window switches the app's cookie, cache and history context to that space's data store (`BrowserManager.windowSpaceChanged`).
- **Private windows** keep their own in-memory `privateTree`, `privateSessions` and `privateClosed` on `BrowserWindowState`. Nothing from them reaches the JSON files or extensions.
- **Unloading**: `TabCompositorManager` unloads pages no window shows (idle timeout, loaded-page budget, memory pressure, backgrounding). `TabsController.isVisibleInAnyWindow(_:)` covers every window's selection and both split panes.

## Drag-and-Drop System

`Nook/Components/DragDrop/`. Drag sources carry item ids; drop zones call `TabsController.drop(...)` with the section's displayed rows.

| File | Purpose |
|------|---------|
| `NookDragSessionManager.swift` | Singleton coordinator: active drag state, cursor position, zone geometry, insertion indices, preview window |
| `NookDragItem.swift` | Draggable item model + `DropZoneID` enum (`.favorites(spaceID:)`, `.section(Parent)`, `.target(Parent)`) |
| `DragLockManager.swift` | Keeps one drag at a time |
| `NookDragSourceView.swift` | `NSView`-based drag source, weak-registered with manager |
| `NookDropZoneHostView.swift` | Drop zone target management |
| `NookDragPreviewWindow.swift` | Floating preview window following cursor during drag |

Custom UTType: `com.nook.tab-drag-item` (registered in Info.plist). Items encode to pasteboard as JSON via `NookDragItem.writeToPasteboard()`.

## AI System

Located in `Nook/Managers/AIManager/`:

- **AIService**: Central orchestrator: providers, conversations, streaming, tool execution (max 20 iterations)
- **AIConfigService**: Provider configuration and API key management
- **AIProvider**: Protocol + factory for provider implementations
- **Providers/**: `GeminiProvider`, `OpenRouterProvider`, `OllamaProvider`, `OpenAICompatibleProvider`
- **MCP/**: `MCPManager` (server lifecycle), `MCPClient` (JSON-RPC), `MCPTransport` (stdio/SSE)
- **Tools/**: `BrowserTools` (tool definitions), `BrowserToolExecutor` (executes browser actions from AI)

Settings stored in `NookSettingsService`: `aiProvider`, API keys per provider, model selection, web search config.

## Content Blocker System

Located in `Packages/NookBlocker/Sources/NookBlocker/`. Full description in `docs/adblocker-architecture.md`. Foundation + WebKit only, no AppKit, so it ports to iOS unchanged; that constraint is what made it a natural first package to extract.

- **ContentBlockerManager**: enable/disable, whitelist (domain suffix match), per-tab temporary disable, OAuth exemption, per-navigation main-frame config, subframe lookups via the `nookAdvancedBlocking` reply handler.
- **FilterListManager**: downloads, caches, validates filter lists (conditional GET, daily). Snapshots of every default list ship in `Resources/`, so first run is protected before any network.
- **ContentRuleListCompiler** + **RustContentBlockingConverter**: adblock-rust conversion (`content_blocking`), 30K-entry chunks, `WKContentRuleListStore` compile, SHA-256 cache plus a `converter-adblock-rust` stamp file that invalidates caches written by the old converter.
- **AdvancedRulesEngine** + **BlockerEngine**: per-URL cosmetic lookup via adblock-rust's `Engine::url_cosmetic_resources`. `BlockerEngine` owns the one `adblock::Engine` in the app and is `@MainActor` with a synchronous lookup, because the main-frame config script must be installed before navigation commits; only `build` steps off-actor. Plain cosmetic filters never reach it: the converter turns them into `css-display-none` entries WebKit applies itself. **Scriptlets are not executed** (no resources are given to the engine) and true procedural operators (`:has-text`, `:upward`, `:matches-css`) are skipped.
- **Resources/nook-cosmetic.js**: Nook's own script, no build step. Reads `window.__nookCosmeticConfig` (main frame, set synchronously before it runs) or asks the `nookAdvancedBlocking` handler (subframes), and injects one stylesheet. Injected in all frames at document start.
- **Resources/*-blocker.js**: site-specific scripts (YouTube, Facebook, X), static, main frame only, hostname-guarded.
- **Resources/facebook-feed-prune.js**, **instagram-feed-prune.js**: remove Meta ads from data before the page renders them, so nothing reflows. Both patch the page's `JSON.parse`. Meta reads XHR bodies through clean iframe built-ins, so XHR and getter hooks never see them. Facebook ads are `Story` nodes with a child `__typename: "SponsoredData"`, removed from the streamed feed with index renumbering; setting the node to null broke the feed. Right-column ads are `AdsSideFeedUnit`. Instagram ads are timeline edges with `node.ad` and `xdt_injected_story_units.ad_media_items`. They go first in the site-script list. `facebook-feed-prune.js` is also injected by `FacebookTweaks` (Tweaks > Social Media: hide the Reels carousel `ShowcaseFeedUnit`, hide suggested posts marked by a non-null `recommendation_context` / `if_viewer_can_join_group` plus "People you may know"); each copy sets its flags on `window.__nookFBFilter` and only the first installs the hook. The DOM blockers are fallbacks. Hiding posts in Instagram's virtualized feed blanked it, and Facebook's `data-ad-rendering-role` and `data-ad-preview` attributes also appear on organic posts.
- **Resources/nook-stealth-redirects.js**: answers a small table of known ad URLs with an inert stub (empty script, 1x1 GIF, as `data:` URLs) so a blocked request does not read as a failure to anti-adblock scripts. Covers what JavaScript starts (`fetch`, `XMLHttpRequest`, `src` on script and image elements built in code); a `<script src>` in the page's own HTML cannot be covered, since WebKit starts that load as the parser reaches the tag. Ships as a static blocker script, so the allowlist and per-tab disable already govern it. Spec: `docs/superpowers/specs/2026-09-16-stealth-redirects-design.md`.
- **TrackingParamStripper**: `$removeparam` for main-frame navigations (parsed from raw filter lines, applied in `PageSession.decidePolicyFor`).
- **`Nook/ThirdParty/AdblockRustFFI`**: C ABI over Brave's adblock-rust (MPL-2.0); rebuild with `build.sh`, needs Rust. `build.sh` wraps the static lib in `NookAdblock.xcframework` (macos-arm64 today; iOS slices are phase 3 of the ios-port work), committed to the repo and declared as a `binaryTarget` (`NookAdblockFFI`) that `Packages/NookBlocker`'s `Package.swift` depends on; there is no `HEADER_SEARCH_PATHS`/`LIBRARY_SEARCH_PATHS` entry in the Xcode project any more. Features `content-blocking` and `css-validation` are both required; without the latter the crate's selector validator is a stub that never classifies procedural filters, so they arrive as raw text and inject invalid CSS. Blocked-request counting was removed in September 2026 along with `RequestStatsEngine` and `nook-request-stats.js`.
- **Never convert a rule that cancels another rule.** A cosmetic exception (`#@#`) and `$badfilter` both describe the absence of a rule, and neither has a standalone content-blocking form. The crate inverts an `UNHIDE` filter's domains into `unless_domain`, so `redtube.com#@#svg` converts to "hide every svg on the web except redtube.com"; left in, that hid 46 of 46 SVGs on facebook.com. `content_blocking_ffi::cancels_another_rule` skips both, and `tests/no_overbroad_rules.rs` fails the build if one escapes. Cosmetic exceptions are the lookup engine's job, and WebKit could not honour them in a rule list anyway.
- Filter lists refresh on their own `! Expires:` interval; `scripts/refresh-filter-lists.sh` updates the bundled snapshots and runs in CI before each release build.

**Rules for changes:**
- Every blocker-owned user script starts with `// Nook Content Blocker` or `// Nook Content Blocker Config`; removal filters on those prefixes.
- Do not re-inject scripts after load. Scriptlets are not idempotent.
- Do not rewrite `:has()` rules out of the content rule list; WebKit supports them natively.
- **Never stub a vendor that validates its payload** (`nook-stealth-redirects.js`). Ad-Shield (`html-load.*`, `ad-shield` mirrors) compares the script it fetches against an `X-Length` header; a `data:` URL has no headers, so an empty stub reads as malformed and it replaces the whole document with an `error-report.com` modal. Blocking is the milder failure. A stub only suits detectors that check whether a load succeeded.
- **An `@@` exception cannot override a block in another list.** WebKit evaluates each compiled `WKContentRuleList` on its own, so an exception in `nook-filters-default.txt` cannot unblock what EasyList blocks. Use a scriptlet or the stub table instead.
- Site-specific scripts: `MutationObserver` on `childList` only, validate content (e.g. "Sponsored" text), `display: none`, guard with `window.__nook<Name>Loaded`.

## Entitlements & Security

**NOT sandboxed.** Current entitlements in `Nook/Nook.entitlements`:

| Entitlement | Purpose |
|-------------|---------|
| `aps-environment: development` | Push notifications (dev) |
| `autofill-credential-provider` | Password autofill integration |
| `automation.apple-events` | AppleScript support |
| `mach-lookup: com.apple.PIPAgent` | Picture-in-Picture |

The passkey entitlement (`web-browser.public-key-credential`) was requested and declined by Apple; it is not in the file and nothing in the code references WebAuthn.

**Info.plist**: Registers as URL handler for `http`/`https` (LSHandlerRank: Owner) with `CFBundleDocumentTypes` so Nook appears in the default-browser picker. Allows arbitrary loads in web content and local networking. Sparkle: daily check, feed `https://nook-browser.github.io/Nook/appcast.xml`, `SUPublicEDKey` must match the `SPARKLE_SIGNING_KEY` repo secret.

## Key Patterns

- **Pages load on selection**: items have no page until `TabsController.select` (or warming, split panes, an extension) creates a `PageSession` and calls `loadWebViewIfNeeded()`. Go through the intents; do not create sessions or web views directly.
- **Multi-window webviews**: `WebViewCoordinator` pools views by item id and window id. The first window to show a page holds the session's primary view; other windows get clones, and a primary passes to a clone when its window closes.
- **Space data isolation**: Each space owns a unique `WKWebsiteDataStore`, keyed by the space's UUID and vended as a `Profile` by `TabsController.profile(forSpace:)`. Two spaces cannot share a login. A private window's ephemeral `Profile` uses a `.nonPersistent()` store destroyed on window close.
- **Startup tab loading**: `setupWindowState()` → `applyStartupLoadMode()` runs when each window registers via `onWindowRegister`, after waiting up to 2 s for the content blocker. Windows that registered before `NookApp` set the callback are set up retroactively.
- **Favicon cache**: `FaviconCache.shared` (`Packages/NookWeb/Sources/NookWeb/FaviconCache.swift`): LRU memory cache (200) plus a disk cache at `~/Library/Caches/FaviconCache/{host}.png`, disk I/O on a background queue. Rows show a cached favicon by host without a page; network fetches wait for `ensureFaviconLoaded()` on a live session.
- **New-OS API wrappers**: When adopting a macOS 27 API before the deployment target moves to 27, gate it behind a small `View` extension or helper with an `#available(macOS 27, *)` fallback (`Packages/NookDesign/Sources/NookDesign/View+GlassEffect.swift` is the shape; its own guards were removed once 26 became the minimum). Remove the guards when the target is raised.
- **Hover detection**: Use NSTrackingArea-based hover (see `HoverSidebarManager`), not SwiftUI `.onHover`, which misfires with overlapping AppKit-hosted views.
- **File-system-synced groups**: Xcode uses filesystem-synchronized groups; new files in a directory are automatically included in the build. Exception: `Navigation/` compiles only the files listed in its membership exception set in `project.pbxproj`, so put new sidebar files under `Nook/Components/` or add them to that list. This does not apply inside `Packages/`: those are SPM targets, and SPM already builds every file under a target's source directory, so no project.pbxproj entry is needed there either.
- **WebContent sandbox**: WKWebView's WebContent processes are sandboxed by Apple. They cannot access the system pasteboard, launchservicesd, or RunningBoard. Clipboard operations must route through the app process. `WebContent[PID]` sandbox log messages are normal.
- **WKWebView.configuration returns a copy**: `webView.configuration.preferences.setValue(...)` modifies a discarded copy. Use the base config before webview creation, or access `userContentController` (which IS shared).
- **`WKUserContentController.userScripts` is lazily bridged**: it is a proxy over WebKit's NSArray. Evaluate everything you need from it (filter, count) before calling `removeAllUserScripts()`; touching the old array afterwards traps in Release builds only (`WKNSArray objectAtIndex:` SIGTRAP). Debug builds hide this.
- **Never re-add a user script Nook does not own.** There is no remove-one API, so changing one script means `removeAllUserScripts()` plus re-adding the survivors, and that controller is shared with `WKWebExtensionController`, which injects its own content scripts and is never told they were cleared. Re-adding one leaves two: ours and the copy the extension controller re-injects. Toggling the blocker used to quadruple the list per cycle (28, 76, 268, 1036, 4108, 16396) until WebKit died in `WTF::Vector<WebUserScriptData, CrashOnOverflow>` inside `parametersForProcess`. Every injected script starts with `// Nook`; filter with `.nookOwned` (`Packages/NookBlocker/Sources/NookBlocker/WKUserScript+NookOwned.swift`) before re-adding, and let the extension controller look after its own.
- **Prefer install-once, self-gating scripts.** The site blockers already wrap themselves in a hostname test and never need rewriting. A script that changes per navigation forces the rewrite above, so put changing state behind the `nookAdvancedBlocking` message handler instead of baking it into the script source.
- **Verifying a build**: there is no test target. Build unsigned Debug, launch `build/Build/Products/Debug/Nook.app`, and stream logs with `/usr/bin/log stream --level info --predicate 'subsystem == "com.gstudios.nook"'` (`log` alone is a zsh builtin). Always also run the Release configuration before installing or shipping; optimizer-only crashes exist (see above).
- **Hands-off verification**: when driving a running build without taking the user's screen (an agent working alongside the user at the keyboard), never send `osascript`/System Events keystrokes or clicks. Launch in the background with `open -g build/Build/Products/Debug/Nook.app`, quit with `osascript -e 'quit app "Nook"'` (this quits without activating it), and drive the app through the DevMCP server over `curl` (Settings > AI > Browser Control must already be on) rather than the `nook` MCP tools, which do take focus. Read state back with `/usr/bin/log show --predicate 'subsystem == "com.gstudios.nook"'`, `defaults read com.gstudios.nook`, and the `Tabs/*.json` files rather than a screenshot. Native dialogs, context menus, drag, Peek and PiP cannot be checked this way; call those out as needing a human rather than faking a pass. Full recipe: `.superpowers/sdd/2026-09-17-ios-port-phase2-packages/verify-protocol.md`.
- **Site tweaks on obfuscated sites** (Facebook, Instagram): do not guess markup. Add a temporary right-click listener that posts `elementsFromPoint`, computed `pointer-events`, and React expando keys to the tweak's message handler, log them with `Logger.notice` (`.debug` never reaches `log show`), have the user right-click signed in, read `log show`, then remove the probe.
- **Driving the app from Claude Code**: every build ships `DevMCPServer`, started only when Settings > AI > Browser Control is on (default off; the toggle starts and stops it without a relaunch) (Streamable HTTP, JSON responses, bearer token in `~/Library/Application Support/com.gstudios.nook/dev-mcp-token`, mode 0600, requests with a non-localhost `Origin` refused). Register once with `claude mcp add --transport http nook http://127.0.0.1:47823/mcp --header "Authorization: Bearer $(cat ~/Library/Application\ Support/com.gstudios.nook/dev-mcp-token)"`. Tools: the `BrowserTools` set minus `executeJavaScript`, which is not advertised because over this server it is only an old name for `evaluate`; the alias still answers. Plus `evaluate` (runs the code as an async function body, so it needs `return`; no approval prompt, the token is the approval), `screenshot`, `console` (console, uncaught errors, failed resource loads; tabs loaded before startup need a reload), `reload`, `wait_for_load`, `blocker_status`, `set_blocking` (edits the persisted allowlist), `check_urls` (adblock-rust), `user_scripts`. All act on the active window's selected tab. Anything that can read the token file can drive the browser, including shipped Release builds.
- **External link testing**: `open <url>` goes to whichever Nook LaunchServices picks (usually `/Applications/Nook.app`, launched alongside a running Debug build), and two copies share the `Tabs/` JSON files and the SwiftData store. Quit the installed app first and target the build: `open -a "$PWD/build/Build/Products/Debug/Nook.app" <url>`. System Events keystrokes go to the frontmost app, so set Nook `frontmost` before sending one.
- **"I don't see my change"**: before assuming a build or cache problem, check which binary is actually running. `ps aux | grep Nook.app` shows the path, and `stat -f "%Sm" <path>/Contents/MacOS/Nook` shows when it was built. `/Applications/Nook.app` is a separate install from anything under `build/` or `build-release/`; it only has your change if you copied a fresh build there (`rm -rf /Applications/Nook.app && cp -R build-release/Build/Products/Release/Nook.app /Applications/ && xattr -dr com.apple.quarantine /Applications/Nook.app`, ad-hoc signed builds need the quarantine flag cleared or Gatekeeper blocks the first launch), not because it auto-updates from your working tree.
- **One `@NSApplicationDelegateAdaptor`**: only `NookApp` declares it. A second declaration (a `Commands` struct had one until September 2026) makes SwiftUI create a second `AppDelegate`: AppKit calls the first, `NookApp` wires `browserManager` into the second, and external links, quit persistence, MCP shutdown and Sparkle callbacks break without an error. Elsewhere, reach the delegate through `browserManager.appDelegate`.
- **MV3 service workers die after ~5 min idle**: extension badge/tab state can vanish. `ExtensionManager.wakeBackgroundWorkers()` is called on tab activation and on `NSApplication.didBecomeActiveNotification`. Do not add a polling timer for this.

## Dependencies

**SPM packages (4 direct, resolved automatically):**

| Package | Product | Purpose | Used by |
|---------|---------|---------|--------|
| **Sparkle** | Sparkle | Auto-updates (notarized DMG distribution) | AppDelegate, BrowserManager |
| **Garnish** | Garnish | Color contrast/mixing utilities | CommandPalette, NookButtonStyle, SidebarAIChat, SidebarMenuHistoryTab |
| **FaviconFinder** | FaviconFinder | Fetches favicon URLs | PageSession, CommandPalette suggestions, SidebarMenuHistoryTab |
| **mlx-swift-lm** | MLXLLM | On-device LLM inference (Apple Silicon only) | LocalLLMEngine → TabOrganizerManager |

Transitive: swift-atomics, swift-numerics, swift-collections, swift-transformers, swift-jinja, swift-asn1, swift-crypto, swift-log, SwiftSoup, LRUCache, Chronicle, yyjson, mlx-swift.

**Nook links no GPL-3.0 code it does not own.** SafariConverterLib (AdGuard, GPL-3.0) was removed in September 2026 because a §7 App Store exception can only be granted by a copyright holder. See `LICENSE-EXCEPTION.md`.

**Embedded in ThirdParty/:** BigUIPaging (paged views; the macOS `PlatformPageView` is locally modified for swipe haptics). MuteableWKWebView (audio muting, ObjC) moved out of `Nook/ThirdParty/` in the phase 2 package split; it is now the `MuteableWKWebView` C target inside `Packages/NookWeb`.

## CI/CD

One GitHub Actions workflow, `.github/workflows/macos-notarize.yml`: on push of a `v*` tag, builds Release for arm64, re-signs the Sparkle framework and XPC services, notarizes, creates and signs a DMG, uploads to the GitHub release, appends an entry to `appcast.xml` on `gh-pages`.

**Known state**: runner is `macos-26` (restored 2026-09-14; the SDK 26 deployment target requires it). The workflow uses the runner's default Xcode and does not pin a version. The restored pipeline works: the 2026-09-14 run (workflow_dispatch, 7m33s) published `v1.2.1` with a notarized DMG. Local tags `v1.1.x`/`v1.2.0` were never published.

## Code Style

- No SwiftLint or SwiftFormat enforced; follow existing patterns
- `@MainActor` on all stateful classes
- `// MARK: -` sections to organize code
- PascalCase for types, camelCase for properties/methods
- System imports first, then external packages, then local imports
- OSLog with privacy annotations for logging (`Logger(subsystem:category:)`)
- Standard Xcode file headers with author/date

## Extension System

The web extension system (WKWebExtension, macOS 15.4+) is the most complex subsystem. Full documentation is in [Nook/Managers/ExtensionManager/CLAUDE.md](Nook/Managers/ExtensionManager/CLAUDE.md).

**Quick reference**: Tab webview configs **MUST** derive from the same `WKWebViewConfiguration` that the `WKWebExtensionController` was configured with (via `.copy()`); see `BrowserConfig.swift`.
