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
  NookBlocker/    ContentBlockerManager, AdblockRustFFI, Resources
  NookTweaks/     YouTube, Facebook, SocialImage, SponsorBlock, SiteRouting
  NookDesign/     design tokens, values resolved per platform
  NookUI/         shared SwiftUI leaves: rows, menus, forms, toasts
  NookWeb/        PageSession, TabsController, FaviconCache, Search, History, Download
  NookSync/       CloudKit mirror of synced-scope items
Nook/             macOS app target: sidebar, windows, AppKit drag, hover
NookiOS/          iOS app target: bottom bar, tab grid, split view, touch drag
```

Dependency order is a straight line. `TabsCore` has no dependencies.
`Blocker`, `Tweaks`, `Design`, and `Sync` depend only on `TabsCore`. `Web`
depends on `Blocker` and `Tweaks`. `UI` depends on `Design` and `Web`. Both app
targets sit on top.

The split earns its keep rather than being structure for its own sake.
`NookBlocker` carries a Rust static library and a build script that nothing
else should inherit. `NookTweaks` has zero dependencies and is the most
unit-testable code in the project. `NookTabsCore` stays Foundation-only, which
is why it already runs `swift test`.

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

File moves plus one shim. No behavior change. The macOS app builds Release and
runs identically at the end, verified by hand.

Most `NS` symbols in the share candidates are Foundation and already work on
iOS. The actual shim surface:

| Symbol | Where | Replacement |
|---|---|---|
| `NSImage`, `NSBitmapImageRep` | `FaviconCache`, `PageSession` | `typealias PlatformImage`, `UIImage.pngData()` |
| `NSColor` | `SpaceRecord+UI`, `PageSession` x3 | `typealias PlatformColor` |
| `NSAlert` | `TabsController`, `PageSession+UIDelegate` | protocol satisfied by each app target |
| `NSOpenPanel` | `PageSession+UIDelegate` | same protocol, `UIDocumentPicker` on iOS |
| `NSApplication`, `NSRunningApplication` | `TabsController` | macOS-only file |

Roughly 400 to 600 lines touched across nine files.

`BlurEffectView` wraps `NSVisualEffectView` and needs a `UIVisualEffectView`
twin. `nookGlassEffect` survives unchanged, since Liquid Glass exists on
iOS 26.

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
