# Nook for iOS: shared core, two idioms

Status: design, not implemented
Date: 2026-09-17

## Problem

Nook is a macOS browser. The parts that make it worth using, the content
blocker and the site tweaks, are exactly the parts iOS users cannot get from
Safari or from any App Store browser, because every iOS browser is a WKWebView
wrapper with no filtering layer of its own.

Three things stand between here and an iOS app, in this order:

1. **Nook links GPL-3.0 code it does not own.** SafariConverterLib is AdGuard's,
   licensed GPLv3, and so is the `@adguard/safari-extension` bundle inside
   `nook-advanced-blocking.js`. GPLv3 and the App Store are incompatible:
   Apple's terms impose redistribution and device-count restrictions that
   GPLv3 sections 4 through 6 forbid a distributor from adding. This is why VLC
   was pulled in 2011.
2. **Twelve people hold copyright in Nook.** No CLA exists. `CONTRIBUTING.md`
   line 107 licenses contributions under GPL-3.0 and nothing assigns copyright.
3. **The macOS UI does not port.** 20,775 lines of sidebar, window management,
   NSView-based drag, and NSTrackingArea hover, none of it meaningful on a
   phone.

## Decisions

**License.** Nook stays GPL-3.0. A GPLv3 section 7 additional permission is
added allowing distribution through Apple's App Store. "Nook", the wordmark,
and the icon are asserted as trademarks under a policy forbidding use by forks.
GPL permits reselling by design, so the trademark is what makes a rebranded
clone commercially worthless rather than illegal.

**AdGuard leaves.** Replaced by `adblock-rust`, MPL-2.0, which Nook already
vendors. This happens on macOS first, alone, before any iOS work starts.

**Scope.** iOS v1 ships core browsing, spaces, the content blocker, and the
site tweaks. Extensions, AI chat, MCP, the MLX tab organizer, split view, Peek,
the command palette, multi-window, and import are all out.

**Devices.** iPhone and iPad together, one SwiftUI codebase, size classes.

**Sync.** CloudKit sync of synced-scope items ships in v1.

**Repo.** One repo, shared SPM packages, two app targets.

## Consent

Every copyright holder has granted the App Store exception. The records are
kept outside this repo.

## Architecture

```
Packages/
  NookTabsCore/   exists, Foundation only, unchanged
  NookSettings/   NookSettingsService and the value types it stores
  NookDesign/     design tokens, values resolved per platform
  NookBlocker/    ContentBlockerManager, AdblockRustFFI (xcframework), Resources
  NookTweaks/     YouTube, Facebook, SocialImage, SponsorBlock, SiteRouting
  NookWeb/        TabsController, PageSession, FaviconCache, History, Search,
                  WindowRegistry, BrowserWindowState, FocusableWKWebView
  NookUI/         shared SwiftUI leaves: rows, menus, settings tab bodies, toasts
  NookSync/       CloudKit mirror of synced-scope items and settings (phase 4)
Nook/             macOS app target: sidebar, windows, AppKit drag, hover
NookiOS/          iOS app target: bottom bar, tab grid, split view, touch drag
```

Dependency order is a straight line. `TabsCore` has no dependencies.
`Settings` and `Design` depend on nothing else. `Blocker` and `Tweaks` depend
on `TabsCore` and `Settings`. `Web` depends on `Blocker`, `Tweaks`, `Design`
and `Settings`. `UI` depends on `Design` and `Web`. Both app targets sit on
top.

The split earns its keep rather than being structure for its own sake.
`NookBlocker` carries a Rust static library and a build script that nothing
else should inherit. `NookTweaks` is the most unit-testable code in the
project. `NookTabsCore` stays Foundation-only, which is why it already runs
`swift test`. `NookSettings` is its own package because settings will sync
across devices the way tabs do, so the model has to be Foundation-only with
no UI types in it.

## Phase 1: replace AdGuard with adblock-rust

Ships to macOS as an ordinary release. iOS work does not begin until this
holds in production.

### What AdGuard does today

`ContentRuleListCompiler.swift` (278 lines) calls
`ContentBlockerConverter().convertArray(...)` to turn filter text into
WKContentRuleList JSON, chunked at 30K, cached by SHA-256.

`AdvancedRulesEngine.swift` (159 lines) builds a `WebExtension` over
`FilterEngine` and calls `configuration(for:topUrl:)` per navigation, returning
cosmetic CSS, extended CSS, scriptlets, and JS rules for that URL.
`nook-advanced-blocking.js` applies them in the page.

These two files are the only place SafariConverterLib is imported. The other
1,142 lines of the blocker are already clean.

### The replacement

`adblock` 0.13.3, MPL-2.0, released August 2026, actively maintained. Line 9 of
its `lib.rs` lists "iOS content-blocking syntax conversion" as an explicit
purpose of the crate; Brave wrote that module for Brave iOS.

Two crate modules replace AdGuard's two jobs:

- `content_blocking.rs` gives `CbRule`, `CbTrigger`, `CbAction`, `CbType`, with
  `impl TryFrom<NetworkFilter> for CbRuleEquivalent` and
  `impl TryFrom<CosmeticFilter> for CbRule`. That second conversion is the
  `css-display-none` path.
- `cosmetic_filter_cache.rs` gives
  `CosmeticFilterCache::hostname_cosmetic_resources()`, returning
  `UrlSpecificResources`.

`UrlSpecificResources` maps onto what `AdvancedRulesEngine` already produces:

| adblock-rust field | AdvancedRulesEngine equivalent |
|---|---|
| `hide_selectors: HashSet<String>` | cosmetic CSS |
| `procedural_actions: HashSet<String>` | extended CSS, JSON for a content script |
| `injected_script: String` | scriptlets |
| `generichide: bool` | `$generichide` exception |
| `exceptions` plus `hidden_class_id_selectors()` | generic rule exceptions |

### Cargo changes

```toml
adblock = { version = "0.13.3", features = ["content-blocking"] }
```

`content_blocking` is behind a feature flag that is **off by default**. The
current `Cargo.toml` has a bare `adblock = "0.13.3"` and would fail to compile
against the new code with a confusing error. `cosmetic_filter_cache` is not
gated and is available today.

Review `single-thread`, on by default, which is the reason for the Send-not-Sync
warning already in `nook_adblock.h`. Measure `css-validation` before enabling
it: it pulls cssparser and selectors, which are Servo crates and not small.

### FFI additions

Three functions added to the existing 158-line `lib.rs`:

```c
char *nook_adblock_convert_to_content_blocking(const char *rules, size_t len, size_t *out_count);
void *nook_adblock_cosmetic_from_rules(const char *rules, size_t len);
char *nook_adblock_cosmetic_for_url(void *cache, const char *url, bool generic_hide);
```

The hand-written C ABI stays. UniFFI and swift-bridge add a codegen step and a
runtime to a surface going from five functions to eight, which is machinery
bought to avoid writing three `extern "C"` declarations.

Convert per 30K chunk rather than per list, since `ContentRuleListCompiler`
already chunks and a whole-list conversion returns multi-megabyte JSON across
the FFI boundary in one allocation. The cosmetic cache carries the same
Send-not-Sync constraint as the engine; one actor owns both.

### Swift changes

`ContentRuleListCompiler` keeps its chunking, SHA-256 cache, and
`WKContentRuleListStore` compile, swapping only the converter call.

`AdvancedRulesEngine` becomes a cosmetic engine over `CosmeticFilterCache` at
roughly its current size, preserving the `configuration(for:topUrl:)` shape so
`PageSession` does not change.

### JS changes

`nook-advanced-blocking.js` is deleted along with its esbuild pipeline and
`BUILD-advanced-blocking.md`. A replacement script reads `UrlSpecificResources`
JSON and injects `hide_selectors` as a stylesheet, plus every procedural filter
that `ProceduralOrActionFilter.as_css()` can express as plain CSS.

True procedural operators (`:has-text`, `:upward`, `:matches-css`) get a JS
evaluator in a later pass. Not this one.

Scriptlets are deferred. The crate ships `Resource` machinery but no scriptlet
bodies; Brave supplies theirs from `brave/adblock-resources`, which is likely
uBO-derived and therefore GPL-3.0. **Check this before designing around it.**
If it is GPL, ship `injected_script` empty at v1. Nook's own Facebook,
Instagram, YouTube, and stealth-redirect scripts already cover the sites that
matter and none of them are AdGuard's.

### Gate

Do not proceed past phase 1 until all of these hold:

- Both converters run over the bundled lists; a human reads the rule counts and
  a sampled diff of the output.
- The top twenty sites browse clean under the new engine, driven through
  `DevMCPServer`.
- Release configuration builds and runs clean.

AdGuard tuned their converter for Safari for years. Brave's is production code
in Brave iOS. They will not agree exactly, and the disagreements are the point
of this gate.

## Phase 2: extract the packages

File moves plus small seams. No behavior change. The macOS app builds Debug
and Release (Developer ID signed, the CI entitlements recipe) and runs
identically at the end, verified by hand. Decisions settled on 2026-09-17
after surveying the tree:

**Rust library.** `build.sh` emits `NookAdblock.xcframework` (macos-arm64 now,
ios-arm64 and ios-arm64-simulator slices added in phase 3) with the header
inside, committed to the repo and declared as a `binaryTarget`. The
`HEADER_SEARCH_PATHS` and `LIBRARY_SEARCH_PATHS` entries leave the pbxproj.
Git LFS is deferred; the repo accepts the growth for now.

**Settings.** `NookSettingsService` (806 lines) moves into `NookSettings`
with the value types it stores (`SiteRoutingRule`, `SponsorBlockCategory`,
`AIProvider`, `StartupLoadMode`, `TabManagementMode`, `AppearanceMode`).
`SettingsTabs` and `currentSettingsTab` stay in the app: window navigation
state, never synced. Blocker and Tweaks import the concrete service rather
than per-package protocols. Two facts for phase 4, recorded here so the
package shape does not fight them later: API keys live in UserDefaults today
and must move to Keychain before any sync backend exists, and per-device
values (window frames, startup mode, last selected tab) need a local-only
marker.

**NookWeb seams.** `TabsController` and `PageSession` reach `browserManager`
80 times across 19 members and `ExtensionManager.shared` 21 times. A single
wide host protocol would only relocate the god object, so the seams are:

- Concrete package types injected at init: `WindowRegistry`,
  `ContentBlockerManager`, `SponsorBlockManager`, `SiteRoutingManager`,
  `HistoryManager`, `NookSettingsService`.
- `WebViewProvider`: the pooled `WebViewCoordinator` on macOS; iOS holds views
  directly.
- `PageSessionDelegate`: downloads, peek, auth, zoom, mute, shortcuts,
  cross-window navigation, space change. `BrowserManager` conforms.
- `TabEventObserver`: the six extension notifications. macOS registers
  `ExtensionManager`; iOS registers nothing.
- `AlertPresenter`: `NSAlert` and `NSOpenPanel` on macOS, `UIAlertController`
  and `UIDocumentPicker` on iOS.
- `PlatformImage` / `PlatformColor` typealiases.

`MuteableWKWebView` (ObjC, reached through the bridging header today) becomes
a C target inside `NookWeb`, since packages have no bridging header.
`BrowserWindowState`, `WindowRegistry` and `FocusableWKWebView` move with
the sessions that depend on them. `WebViewCoordinator` stays in the app.

Most `NS` symbols in the share candidates are Foundation and already work on
iOS. The AppKit surface:

| Symbol | Where | Replacement |
|---|---|---|
| `NSImage`, `NSBitmapImageRep` | `FaviconCache`, `PageSession` | `typealias PlatformImage`, `UIImage.pngData()` |
| `NSColor` | `SpaceRecord+UI`, `PageSession` x3 | `typealias PlatformColor` |
| `NSAlert` | `TabsController`, `PageSession+UIDelegate` | `AlertPresenter` |
| `NSOpenPanel` | `PageSession+UIDelegate` | `AlertPresenter` |
| `NSApplication`, `NSRunningApplication` | `TabsController` | macOS-only file |
| `NSEvent`, `NSMenu`, `NSSavePanel` | `FocusableWKWebView` | `+macOS.swift` sibling |

A file needing more than one `#if os` gets split into a shared file and a
`+macOS.swift` sibling.

**NookUI is built in this phase**, not deferred, so the seams above get a real
consumer at once. It holds the tab and folder rows, the space dots, the
favorites grid, the three context menu builders (taking `TabsController` plus
a `TabActions` protocol in place of `browserManager`), the empty state, the
find bar, toasts, and the settings tab bodies for General, Spaces, Ad
Blocker, Air Traffic Control, YouTube and Social Media. Extensions, AI,
Shortcuts and Advanced settings stay macOS. `UI` depends on `Web` so rows can
take a `TabsController` directly, which is how they are written today.

**Stays in the app.** `BrowserManager`, `WebViewCoordinator`, the drag
system, sidebar chrome, extensions, AI, MLX, and `DownloadManager`.
`DownloadManager` (656 lines, `NSWorkspace`, `NSSavePanel`, `NSScreen`) is
being rewritten on `fix/download-memory`; once that lands it splits into a
Foundation download core in `NookWeb` and a macOS presentation layer. That
split is a tracked follow-up, not part of this phase.

**The `public` pass.** Every type, initializer and member the app touches
gains `public`. For `TabsController` and `PageSession` that is several hundred
keyword changes, mechanical and behavior-free.

`BlurEffectView` wraps `NSVisualEffectView` and needs a `UIVisualEffectView`
twin in phase 3. `nookGlassEffect` survives unchanged, since Liquid Glass
exists on iOS 26.

### Outcome

The seven packages match this plan, with a handful of deviations.
`FocusableWKWebView` stayed in the app rather than moving with the sessions
that depend on it, since it is an `NSView` subclass with no iOS equivalent
yet; it reaches `PageSession` through a new `SessionWebView` seam instead.
The find bar stayed in the app too, typed directly on `FindManager`, rather
than joining the rest of the shared rows in `NookUI`. `TabActions` grew to
10 members instead of the 8 sketched here once space creation, deletion,
pasteboard and sharing calls were accounted for. `NookUI` picked up a second
platform wrapper beyond `Haptics.swift`: `HoverTracking.swift`, for the
NSTrackingArea-based hover pattern this file already requires elsewhere.
`DownloadManager` stayed untouched, exactly as planned, still pending the
`fix/download-memory` rewrite. One behavior changed: the persisted ad-block
allowlist now loads at launch, because the old code read a `settings`
reference that was `nil` at attach time and silently skipped it; the package
seam wiring fixed that as a side effect rather than by design. Find and zoom
now fall back to the session's primary web view when the pool has no view
for the active window; the old code reported the view as unavailable.

## Phase 3: the iOS app

### Sharing discipline

Three layers, and the boundaries are not negotiable:

**State shares completely** and already does. Every manager is
`@MainActor @Observable`.

**Leaf views share.** Rows, cells, accent dots, forms, menus, toasts, the find
bar, the empty state. The repo already demonstrates this:
`FolderContextMenu.swift` (71 lines) and `SpaceContextMenu.swift` (60 lines)
contain zero AppKit references, and `TabContextMenu.swift` (312 lines) contains
five. 443 lines of interaction logic shares almost as-is, because those
builders call `TabsController` intents and render SwiftUI `Menu`.

**Chrome diverges on purpose.** Sidebar against bottom bar against split view.
Windows against scenes. `NSTrackingArea` hover against nothing at all.

**Platforms are resolved in the token file, never in view bodies.**
`NookDesign.Size.row` is 32pt today; iOS needs 44pt for a touch target. So
`Size.row` resolves per platform and every view using it stays byte-identical
across targets. Same for `Spacing.rowPadding` and hit areas. Token names stay
identical everywhere and only the token file knows which OS it is on.

The failure mode to avoid is a view body with `#if os(iOS)` scattered through
it, which is worse than two honest files. Platform conditionals live in the
token file and in thin wrapper types. A view needing more than one gets split.

Drag is the clean example. macOS keeps its `NSView`-based
`NookDragSessionManager` and its floating preview window. iOS gets SwiftUI
`.draggable` and `.dropDestination`. Neither shares a line of gesture code and
both call the same `TabsController.drop(...)`, so the model half is fully
shared and only the plumbing differs.

Expect all model and state code plus roughly half the view code by line to be
shared. The sidebar and window chrome are the irreducible half.

### iPhone

Bottom bar carrying URL and actions, within thumb reach. Horizontal swipe on
that bar switches tabs. Spaces sit above it as a row of accent dots, the same
language as `SpacesList` on macOS. Tab grid opens as a sheet. Long-press opens
the shared context menu builders.

### iPad

`NavigationSplitView` with the sidebar, because the macOS sidebar design
already exists and translates directly.

### Simplifications

`WebViewCoordinator`'s pooling exists for multi-window; iOS v1 has one scene,
so the iOS target holds webviews directly.

`TabCompositorManager` stays and is tuned harder. Jetsam on a phone is
unforgiving in a way macOS memory pressure is not.

Downloads go to the app container with `LSSupportsOpeningDocumentsInPlace` so
Files sees them.

Sparkle is macOS-only and does not come along.

### Open design items for this phase

- **Folders and favorites on iPhone.** Both stay in v1, but the phone layout
  for a five-deep folder tree and a favorites grid is undecided. Decide with
  mockups before building the bottom bar.
- **Settings visual pass.** The macOS settings window resembles System
  Settings but does not feel built the same way. Phase 2 extracts the tab
  bodies unchanged; the redesign that makes them match System Settings on
  macOS and Settings.app on iOS happens here, once, in `NookUI`.

### Entitlements

Apply for `com.apple.developer.web-browser` early. It is a request form to
Apple with a review attached, and it is the difference between shipping a
browser and shipping a viewer.

## Phase 4: CloudKit sync

`structure.json` stays the local source of truth and CloudKit mirrors it.
`device.json` never syncs, which is already the correct boundary.

`CKSyncEngine` rather than hand-rolled `CKQueryOperation`. It handles state
serialization, batching, and retry, and hand-rolling those is where sync
projects die.

One `CKRecord` per synced-scope `Item` and per `SpaceRecord`. Conflict
resolution is last-writer-wins per field. Ordering needs no coordination at all
because `OrderKey` is already a string. The 30-day tombstones already in
`structure.json` handle deletes. The tab model was built for this.

## Risks

**Content rule list compilation on a phone.** Nook ships EasyList, EasyPrivacy,
the uBlock lists, urlhaus, and more. Compiling that set within an iPhone's
memory budget on first launch may be slow or may be fatal. This is the risk
most likely to force a design change and it is cheap to measure. Spike it on a
real device before phase 3 begins. If it fails, the fallbacks are a
reduced default list set on iOS or a staged background compile with progress.

**CloudKit on an unsandboxed Developer ID macOS app.** Nook is not sandboxed
and ships by DMG and Sparkle. Whether iCloud entitlements work in that
configuration needs verifying rather than assuming. Spike before phase 4
commits.

**Converter parity.** Covered by the phase 1 gate.

**A contributor declines or goes quiet.** Every holder has granted the exception.
The fallback for any later dispute is rewriting that holder's surviving lines.

**Scriptlet resources.** `brave/adblock-resources` licensing is unverified.
Shipping `injected_script` empty is an acceptable v1 answer and the fallback is
writing the twenty scriptlets that matter, each a few lines.

## Planning note

Phase 1 is a separate project from phases 2 through 4 and gets its own
implementation plan. It ships to macOS on its own schedule, carries its own
gate, and has value even if the iOS app never happens, because it removes the
last GPL dependency Nook does not own. Write that plan first. The iOS plan
covering phases 2 through 4 comes after phase 1 clears its gate, when the shape
of the replacement blocker is known rather than assumed.

## Out of scope

Extensions (WKWebExtension exists on iOS 18.4+, but `ExtensionManager` is 12
files with 9 AppKit importers and would need substantial rework). AI chat and
MCP. The MLX tab organizer. Split view. Peek. The command palette.
Multi-window. Browser import. A JS evaluator for true procedural cosmetic
filters. Scriptlet injection.

**A custom video backend.** WKWebView's media stack is closed: WebCore plays
`<video>` through its own AVFoundation backend inside the web content and GPU
processes, the large sites feed bytes through Media Source Extensions rather
than handing over a URL, and FairPlay sits on top for DRM. Apple exposes no
API to substitute a media engine and the WebContent sandbox blocks hooking
near it, so AetherEngine or any other player cannot take over page video. The
only feasible cousin is "open in native player" for pages whose video has a
plain MP4 or HLS URL, which covers none of the big sites and no DRM. Possible
after phase 3; not part of the port.
