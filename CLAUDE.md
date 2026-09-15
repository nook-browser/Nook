# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## Project Overview

Nook is a fast, minimal macOS browser with sidebar-first design. Built with Swift 5, SwiftUI, and WKWebView. Licensed GPL-3.0.

**Fork status**: This repo (`origin` = `l984-451/Nook`) started as a fork of `nook-browser/Nook`, which went dormant in March 2026. As of September 2026 it is a standalone solo project: the `upstream` remote is removed, upstream's PR-base workflow is deleted, and nothing is merged back. Treat this repo as the only source of truth.

- **Minimum macOS**: 26.0 (Tahoe), Apple Silicon. Raised from 15.5 in September 2026; every `@available` / `#available` guard below 26 was removed at the same time. Do not add guards for versions below the deployment target.
- **Local toolchain**: Xcode 26.6 (SDK 26.5) at `/Applications/Xcode.app`. Xcode 27 is not installed yet; install it before starting macOS 27 API work.
- **Swift language mode**: 5 (`SWIFT_VERSION = 5.0`). Swift 6 strict concurrency is not enabled; see `ASSESSMENT.md` for the warning inventory that would become errors.
- **Bundle ID**: `com.baingurley.nook`
- **Current Version**: 1.2.1 (build 121). Tags up to `v1.2.0` exist locally; the last published GitHub release is `v1.0.7`.
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

**Signing**: Set your Development Team in Xcode Signing settings. Team IDs in the project: `ZHB786H6YN` (Bain Gurley, local) and `96M8ZZRJK6` (CI). `Nook/Nook-CI.entitlements` is a reduced entitlements file used for the CI build step because push and autofill require provisioning profiles; the full `Nook/Nook.entitlements` is applied during re-signing.

**Metal**: One shader (`Onboarding/Components/ViewTransition.metal`). Xcode 26+ needs the Metal Toolchain component: `xcodebuild -downloadComponent MetalToolchain`.

**No SPM resolve needed**: Xcode resolves packages automatically on open. The `build/` directory holds package checkouts and is large (MLX).

**Bridging Header**: `Nook/Supporting Files/Nook-Bridging-Header.h` imports `MuteableWKWebView.h` and `HTSymbolHook.h` for ObjC interop.

## Git Workflow

- **`main`** is the development branch. Commit and branch from here.
- **`release`** is the ship branch. A push to `release` triggers the notarize workflow, which builds, signs, notarizes, uploads a DMG to a GitHub release named after the marketing version, and updates the Sparkle appcast. Ship by fast-forwarding `release` to `main` and pushing.
- `dev` and upstream-era branches were deleted in September 2026. `fix/download-memory` survives as an unfinished WIP branch (URLSession-streamed downloads, based on an old commit; rebase before finishing).
- AI assistance must be disclosed per CONTRIBUTING.md.

## Architecture

### Manager-Based Pattern

The app uses ~30 specialized **Managers**, one per feature domain, coordinated through environment injection. All managers are `@MainActor` confined.

**Core managers:**

| Manager | Location | Responsibility |
|---------|----------|----------------|
| **BrowserManager** | `Nook/Managers/BrowserManager/` | Central coordinator (~2900 lines). Aggregates all other managers. Being refactored toward independent injection. |
| **TabManager** | `Nook/Managers/TabManager/` | Tab lifecycle (~3000 lines), persistence via `PersistenceActor`, spaces, folders, pins. `Tab` itself is ~3950 lines in `Nook/Models/Tab/Tab.swift`. |
| **ProfileManager** | `Nook/Managers/ProfileManager/` | Profile lifecycle, ephemeral/incognito profiles with non-persistent `WKWebsiteDataStore` |
| **ExtensionManager** | `Nook/Managers/ExtensionManager/` | WKWebExtension integration (12 files). Singleton, global across profiles, disabled in private tabs. See [Extension CLAUDE.md](Nook/Managers/ExtensionManager/CLAUDE.md) |
| **ContentBlockerManager** | `Nook/Managers/ContentBlockerManager/` | Ad/tracker blocking. See Content Blocker System below and `docs/adblocker-architecture.md` |
| **WindowRegistry** | `Nook/Managers/WindowRegistry/` | Multi-window state tracking. Single source of truth for all open windows |
| **WebViewCoordinator** | `Nook/Managers/WebViewCoordinator/` | WebView pool for multi-window tab display |

**Feature managers:**

| Manager | Purpose |
|---------|---------|
| **AIManager/** | AI chat: providers (Gemini, OpenRouter, Ollama, OpenAI-compatible), MCP client/server, browser tool execution |
| **SiteRoutingManager/** | "Air Traffic Control": rules (domain + optional path prefix → target space + profile) stored in `NookSettingsService.siteRoutingRules`. Guards run in `decidePolicyFor`, `createWebViewWith` (popups), and `AppDelegate` external URL handling. Longest path-prefix wins. |
| **SponsorBlockManager/** | Built-in SponsorBlock: queries `sponsor.ajay.app` by hashed video ID, skips segments via `youtube-sponsorblock.js` |
| **TabOrganizerManager/** | On-device LLM tab grouping via MLX. `LocalLLMEngine` owns model download, load, idle unload, and memory-pressure response. Apple Silicon only. |
| **DialogManager/** | Modal dialogs: profile creation, space editing, basic auth, settings, import, confirmations |
| **DownloadManager/** | File downloads via `WKDownloadDelegate` |
| **DragManager/** | `TabDragManager` and `DragLockManager`. Legacy; still referenced by 2 files. New code uses `Nook/Components/DragDrop/` (see below) |
| **FindManager/** | In-page find/search |
| **HistoryManager/** | Browsing history, SwiftData persistence |
| **ImportManager/** | Browser import from Safari, Arc, and Dia |
| **KeyboardShortcutManager/** | Global + website-specific keyboard shortcuts |
| **PeekManager/** | Quick-preview overlay for links (PeekSession + PeekWebView) |
| **PrivacyManager/** | `OAuthDetector` (OAuth flows get ad-block exemptions) |
| **SearchManager/** | Search engine integration |
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

- **`@Observable`** (Swift Observation): `Profile`, `Space`, `Tab`, `BrowserWindowState`, `WebViewCoordinator`, `WindowRegistry`, `AIService`
- **`@Published` / `ObservableObject`** (Combine): `BrowserManager`, `Tab` (dual: uses both patterns, `loadingState` is `@Published`), `ExtensionManager`, `NookDragSessionManager`, `PeekManager`
- **SwiftData**: `SpaceEntity`, `ProfileEntity`, `TabEntity`, `FolderEntity`, `HistoryEntity`, `ExtensionEntity`, `TabsStateEntity`
- **UserDefaults**: `NookSettingsService` (all app settings)
- All state is `@MainActor` confined.

### App Entry & Window Hierarchy

```
NookApp.swift          — @main entry, WindowGroup scene, environment injection
  └─ ContentView.swift — Per-window container, registers with WindowRegistry
       └─ WindowView   — Main browser: Sidebar + WebsiteView + TopBar + StatusBar
```

**Environment injection**: `NookApp` creates `BrowserManager`, `WindowRegistry`, `WebViewCoordinator`, `NookSettingsService`, `KeyboardShortcutManager`, `AIConfigService`, `MCPManager`, `AIService` and injects them as `@EnvironmentObject` / `@Environment`. Each window gets its own `BrowserWindowState`.

### Top-Level Modules

| Directory | Purpose |
|-----------|---------|
| `App/` | Entry point (`NookApp.swift`), `AppDelegate`, `ContentView`, window management, `NookCommands` |
| `Nook/Managers/` | ~30 feature managers (business logic) |
| `Nook/Models/` | Data models and SwiftData entities |
| `Nook/Components/` | SwiftUI views. `Settings/` holds `SettingsWindow` (NavigationSplitView sidebar) and the `SettingsTabs` enum in `SettingsUtils.swift` (11 tabs: general, appearance, ai, privacy, adBlocker, sponsorBlock, airTrafficControl, profiles, shortcuts, extensions, advanced) |
| `Nook/Protocols/` | Protocol definitions (e.g., `TabListDataSource`) |
| `Nook/Adapters/` | External API adapters (`TabListAdapter`) |
| `Nook/Design/` | `NookDesign.swift`: the design token file (see Design System below) |
| `Nook/Extensions/` | Swift extensions, including `View+GlassEffect.swift`, the only Liquid Glass entry point |
| `Nook/Utils/` | Utilities, WebKit extensions, `WebStoreInjector.js` (Chrome Web Store install button) |
| `Nook/ThirdParty/` | Embedded dependencies |
| `Settings/` | `NookSettingsService`: `@Observable` settings backed by UserDefaults |
| `CommandPalette/` | Command palette UI |
| `UI/` | Shared UI components |
| `Navigation/` | Sidebar structure (header, bottom bar, spaces list, context menus) |
| `Onboarding/` | 4 stages: Hello → TabLayout → Import (`SafariImportFlow`) → Final. Metal-shader transitions. |
| `docs/` | `adblocker-architecture.md`; `gui-remodel-next-moves.md`; `superpowers/specs/` and `superpowers/plans/` (design specs and implementation plans, including the September 2026 GUI remodel spec `2026-09-14-gui-remodel-design.md` and its five phase plans) |
| `ASSESSMENT.md` | Build and warning audit snapshot from 2026-03-20. Numbers are stale; the category breakdown is still useful. |

## Design System

The September 2026 remodel (spec: `docs/superpowers/specs/2026-09-14-gui-remodel-design.md`) put every visual value in one file, `Nook/Design/NookDesign.swift`. Rules:

- **No literals in the UI layer.** Radii, spacing, sizes, fonts, animation curves, shadows, and fills come from `NookDesign.Radius / Spacing / Size / Font / Motion / Surface / Elevation`. Text colors are `.primary / .secondary / .tertiary`. When nothing fits, add a token with a comment saying what it is for; do not mint a token just to hide a number from a grep (a window's fixed size belongs in a `private let` in its view). `spacing: 0` and `lineWidth: 1` may stay literal.
- **Corners are continuous.** Build shapes with `NookDesign.Radius.shape(_:)`; CALayer corners get `cornerCurve = .continuous`.
- **Elevation, not shadows.** `.nookElevation(.flat / .raised / .floating)`. The modifier is branch-free so view identity is stable and shadows animate; use `isActive ? .raised : .flat` for conditional elevation.
- **Glass only on layers that float over content**: command palette, toasts, hover sidebar overlay, find bar, dialog cards, extension panels, split drop card. `nookGlassEffect(in:)` in `View+GlassEffect.swift` is the only entry point and already includes `.floating` elevation. The sidebar itself is `BlurEffectView(material: .sidebar)` in `WindowView`, and rows are `Surface` fills; never glass on glass.
- **Space color is an accent only.** `space.accentColor` tints the space icon, the active switcher item, and folder icons. Persisted as a one-node `SpaceGradient`; old multi-node data still decodes. Space icons are SF Symbol names rendered through `SpaceIconView`, with a text fallback for pre-remodel emoji values.
- **Row geometry**: `Size.row` (32) tall, `Radius.md`, `Spacing.rowPadding` sides, `Spacing.rowGap` between rows. The drag session's `itemCellSize` / `itemCellSpacing` caches must equal these.
- **Context menus** are the three shared builders in `Nook/Components/Sidebar/ContextMenus/` (`TabContextMenu(tab:context:)`, `FolderContextMenu`, `SpaceContextMenu`). Do not add inline `.contextMenu` bodies to rows.
- **Settings** are a `Settings` scene, one file per tab under `Nook/Components/Settings/Tabs/`, every tab a grouped `Form`; large entry lists (cache, cookies) stay in a virtualized `List` under the Form.

## Drag-and-Drop System

The unified drag-drop system in `Nook/Components/DragDrop/` replaces the older `TabDragManager`:

| File | Purpose |
|------|---------|
| `NookDragSessionManager.swift` | Singleton coordinator: active drag state, cursor position, zone geometry, insertion indices, preview window |
| `NookDragItem.swift` | Draggable item model + `DropZoneID` enum (`.essentials`, `.spacePinned(UUID)`, `.spaceRegular(UUID)`, `.folder(UUID)`) |
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

Located in `Nook/Managers/ContentBlockerManager/`. Full description in `docs/adblocker-architecture.md`. Foundation + WebKit only, no AppKit, so it ports to iOS unchanged.

- **ContentBlockerManager**: enable/disable, whitelist (domain suffix match), per-tab temporary disable, OAuth exemption, per-navigation main-frame config, subframe lookups via the `nookAdvancedBlocking` reply handler.
- **FilterListManager**: downloads, caches, validates filter lists (conditional GET, daily). Snapshots of every default list ship in `Resources/`, so first run is protected before any network.
- **ContentRuleListCompiler**: SafariConverterLib conversion, 30K-entry chunks, `WKContentRuleListStore` compile, SHA-256 cache.
- **AdvancedRulesEngine**: wraps SafariConverterLib's `FilterEngine`/`WebExtension` for per-URL lookup of advanced rules (cosmetic CSS, extended CSS, scriptlets, JS) with correct exception semantics.
- **Resources/nook-advanced-blocking.js**: AdGuard's `@adguard/safari-extension` content-script library (ExtendedCss + Scriptlets) bundled by esbuild; rebuild per `Resources/BUILD-advanced-blocking.md`. Injected in all frames at document start.
- **Resources/*-blocker.js**: site-specific scripts (YouTube, Facebook, X), static, main frame only, hostname-guarded.
- **TrackingParamStripper**: `$removeparam` for main-frame navigations (parsed from raw filter lines, applied in `Tab.decidePolicyFor`).
- **RequestStatsEngine** + `Resources/nook-request-stats.js` + `Nook/ThirdParty/AdblockRustFFI`: blocked-request counts per tab via Brave's adblock-rust (C API, static lib; rebuild with `build.sh`, needs Rust).
- Filter lists refresh on their own `! Expires:` interval; `scripts/refresh-filter-lists.sh` updates the bundled snapshots and runs in CI before each release build.

**Rules for changes:**
- Every blocker-owned user script starts with `// Nook Content Blocker` or `// Nook Content Blocker Config`; removal filters on those prefixes.
- Do not re-inject scripts after load. Scriptlets are not idempotent.
- Do not rewrite `:has()` rules out of the content rule list; WebKit supports them natively.
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

**Info.plist**: Registers as URL handler for `http`/`https` (LSHandlerRank: Owner) with `CFBundleDocumentTypes` so Nook appears in the default-browser picker. Allows arbitrary loads in web content and local networking. Sparkle: daily check, feed `https://l984-451.github.io/Nook/appcast.xml`, `SUPublicEDKey` must match the `SPARKLE_SIGNING_KEY` repo secret.

## Key Patterns

- **Lazy WebView**: `Tab.webView` is lazily initialized on first access. Tabs exist without loaded webviews to save memory. When changing the active tab (e.g., after data load), call `loadWebViewIfNeeded()` before refreshing the compositor; the compositor skips unloaded tabs.
- **Multi-window webviews**: Same tab in multiple windows gets separate webview instances via `WebViewCoordinator`. Primary window owns the "real" webview; others get clones.
- **Profile data isolation**: Each `Profile` owns a unique `WKWebsiteDataStore`. Ephemeral profiles use `.nonPersistent()` stores destroyed on window close.
- **Atomic persistence**: `TabManager` uses a Swift `actor` (`PersistenceActor`) for coalesced, atomic snapshot writes with backup recovery. `persistSnapshot()` is debounced at 100ms via `debouncedPersistSnapshot()` for most mutations; only critical paths (app quit, startup) use immediate persistence.
- **Tab reattach timing**: `TabManager.reattachBrowserManager()` MUST be synchronous. If async (wrapped in `Task`), tabs won't have `browserManager` set when `setupWindowState` runs, causing webviews to fail creation (profile resolves to nil).
- **Startup tab loading**: `setupWindowState()` → `applyStartupLoadMode()` runs when each window registers via `onWindowRegister`. Always loads the last active tab regardless of startup mode setting. The `.tabManagerDidLoadInitialData` notification fires during `TabManager.init()` before observers exist; do not rely on it.
- **Favicon cache**: Global LRU cache (200 max) with persistent disk cache at `~/Library/Caches/FaviconCache/{host}.png`. Disk I/O runs on `faviconCacheQueue` (background). Favicons are restored from disk cache during `toRuntime()` for instant display on startup. Network fetches are deferred via `ensureFaviconLoaded()` until the tab becomes visible (`.onAppear`) or active (`loadWebViewIfNeeded`).
- **New-OS API wrappers**: When adopting a macOS 27 API before the deployment target moves to 27, gate it behind a small `View` extension or helper with an `#available(macOS 27, *)` fallback (`Nook/Extensions/View+GlassEffect.swift` is the shape; its own guards were removed once 26 became the minimum). Remove the guards when the target is raised.
- **Hover detection**: Use NSTrackingArea-based hover (see `HoverSidebarManager`), not SwiftUI `.onHover`, which misfires with overlapping AppKit-hosted views.
- **File-system-synced groups**: Xcode uses filesystem-synchronized groups; new files in a directory are automatically included in the build.
- **WebContent sandbox**: WKWebView's WebContent processes are sandboxed by Apple. They cannot access the system pasteboard, launchservicesd, or RunningBoard. Clipboard operations must route through the app process. `WebContent[PID]` sandbox log messages are normal.
- **WKWebView.configuration returns a copy**: `webView.configuration.preferences.setValue(...)` modifies a discarded copy. Use the base config before webview creation, or access `userContentController` (which IS shared).
- **`WKUserContentController.userScripts` is lazily bridged**: it is a proxy over WebKit's NSArray. Evaluate everything you need from it (filter, count) before calling `removeAllUserScripts()`; touching the old array afterwards traps in Release builds only (`WKNSArray objectAtIndex:` SIGTRAP). Debug builds hide this.
- **Verifying a build**: there is no test target. Build unsigned Debug, launch `build/Build/Products/Debug/Nook.app`, and stream logs with `/usr/bin/log stream --level info --predicate 'subsystem == "com.baingurley.nook"'` (`log` alone is a zsh builtin). Always also run the Release configuration before installing or shipping; optimizer-only crashes exist (see above).
- **MV3 service workers die after ~5 min idle**: extension badge/tab state can vanish. `ExtensionManager.wakeBackgroundWorkers()` is called on tab activation and on `NSApplication.didBecomeActiveNotification`. Do not add a polling timer for this.

## Dependencies

**SPM packages (5 direct, resolved automatically):**

| Package | Product | Purpose | Used by |
|---------|---------|---------|--------|
| **Sparkle** | Sparkle | Auto-updates (notarized DMG distribution) | AppDelegate, BrowserManager |
| **Garnish** | Garnish | Color contrast/mixing utilities | CommandPalette, NookButtonStyle, SidebarAIChat, SidebarMenuHistoryTab |
| **FaviconFinder** | FaviconFinder | Fetches favicon URLs | Tab, CommandPalette suggestions, SidebarMenuHistoryTab |
| **mlx-swift-lm** | MLXLLM | On-device LLM inference (Apple Silicon only) | LocalLLMEngine → TabOrganizerManager |
| **SafariConverterLib** | ContentBlockerConverter | Converts AdGuard/uBlock filter rules to Safari format | AdvancedBlockingEngine, ContentRuleListCompiler |

Transitive: swift-atomics, swift-numerics, swift-collections, swift-transformers, swift-jinja, swift-argument-parser, swift-asn1, swift-crypto, swift-psl, swift-log, SwiftSoup, LRUCache, PunycodeSwift, Chronicle, yyjson, mlx-swift.

**Embedded in ThirdParty/:** BigUIPaging (paged views; the macOS `PlatformPageView` is locally modified for swipe haptics), HTSymbolHook (ObjC symbol hooking), MuteableWKWebView (audio muting, ObjC).

## CI/CD

One GitHub Actions workflow, `.github/workflows/macos-notarize.yml`: on push to `release`, builds Release for arm64, re-signs the Sparkle framework and XPC services, notarizes, creates and signs a DMG, uploads to the GitHub release, appends an entry to `appcast.xml` on `gh-pages`.

**Known state**: runner is `macos-26` (restored 2026-09-14; the SDK 26 deployment target requires it). The workflow uses the runner's default Xcode and does not pin a version. No run has succeeded since v1.0.6 (2026-02-28); the next push to `release` is the first real test of the restored pipeline. Local tags `v1.1.x`/`v1.2.0` were never published.

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
