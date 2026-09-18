# iOS port, Phase 3 handoff

Written 2026-09-18 for the session that builds the iOS app. Read this, then the
spec's Phase 3 section (`docs/superpowers/specs/2026-09-17-ios-port-design.md`),
then CLAUDE.md's Packages section. Start with the brainstorming skill: Phase 3 is
architectural (a new target with no existing flow to read).

## Where things stand

- Phase 1 (adblock-rust replaces AdGuard) and Phase 2 (seven shared packages)
  are on `main` at 4fdbaf1 and installed as the signed Release in
  `/Applications/Nook.app`. Nothing is pushed or tagged; `release` is untouched.
- Consent for the App Store section 7 exception is in from all eleven holders
  (`LICENSE-EXCEPTION.md`). Two chores remain before a submission: file a
  durable record per holder, and add the pointer line
  `// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.`
  to every source file (0 of 296 Swift files have it). The pointer is a
  mechanical commit; do it early in Phase 3 so every new iOS file is born with
  it.
- Packages and the line they form: `NookTabsCore` → `NookSettings`,
  `NookDesign` → `NookBlocker`, `NookTweaks` → `NookWeb` → `NookUI`. Each
  declares `.iOS("26.0")` but none has been built for iOS. Expect a first
  `swift build --destination` for iOS (or an iOS target build) to surface
  compile errors that the macOS build never exercised: the `#else` branches of
  `Platform.swift`, `Haptics.swift`, `HoverTracking.swift`, `NookDesign.swift`,
  and any `NSImage`/`NSColor` reference that slipped through under
  `canImport(AppKit)`.

## The app conforms to nine protocols

Every package boundary is a protocol the macOS app implements in a
`BrowserManager+*.swift` file. The iOS target implements the same nine; most
are trivial or no-op on one scene with no extensions.

| Protocol | Package | macOS conformance | iOS expectation |
|---|---|---|---|
| `ContentBlockerHost`, `BlockablePage` | NookBlocker | `BrowserManager+Blocker.swift`, `PageSession+Blockable.swift` | same shape, one window |
| `SiteRoutingHost`, `MediaDownloading` | NookTweaks | `BrowserManager+Tweaks.swift` | route opens a tab in the space; download saves to Photos or Files |
| `WebViewProvider` | NookWeb | pooled `WebViewCoordinator` | hold one `WKWebView` per session directly |
| `PageSessionDelegate` | NookWeb | `BrowserManager+NookWeb.swift` (downloads, peek, auth, zoom, mute, PiP, shortcuts, cross-window nav, config) | downloads and zoom real; peek, PiP, shortcuts, cross-window no-op |
| `TabEventObserver` | NookWeb | forwards to `ExtensionManager.shared` | no-op |
| `AlertPresenter` | NookWeb | `NSAlert`, `NSOpenPanel` | `UIAlertController`, `UIDocumentPickerViewController` |
| `SessionWebView` | NookWeb | `FocusableWKWebView` | a plain `WKWebView` subclass with `owningSession` |
| `TabActions` (10 members) | NookUI | `BrowserManager+UI.swift`, injected via `\.tabActions` | pasteboard and share sheet on UIKit; split and dialogs no-op or sheet |

Read each protocol file for the exact members; the tables in CLAUDE.md are
summaries.

## What Phase 3 has to build, in order

1. **Rust slices.** `Nook/ThirdParty/AdblockRustFFI/build.sh` has the commented
   steps: `rustup target add aarch64-apple-ios aarch64-apple-ios-sim`, two more
   `cargo build --release --target`, two more `-library … -headers include`
   pairs on `xcodebuild -create-xcframework`. Commit the regenerated
   `NookAdblock.xcframework`. Then `swift build` each package for iOS and fix
   what fails.
2. **The target.** `NookiOS/` at the repo root (the spec's layout), one app
   target in the same `Nook.xcodeproj`, `SDKROOT = iphoneos`, deployment
   target iOS 26, the seven package products, bundle id `com.gstudios.nook`
   (decided 2026-09-18; the macOS app moves to the same id in the transition
   track that runs first, see the spec's Phase 3 decisions). Entry point, one `WindowGroup`, a `BrowserModel` (the
   iOS stand-in for `BrowserManager`: owns settings, registry, blocker,
   sponsorBlock, siteRouting, history, tabs, and the nine conformances).
3. **Milestone one:** the iOS target builds and loads one page with the
   blocker on, in the simulator. No chrome beyond a URL field. This is the
   gate that proves the packages port; stop and review here.
4. **The device spike the spec flags as the biggest risk:** compile the full
   filter set into `WKContentRuleList` on a real iPhone, first launch, cold
   cache. Measure time and peak memory (`vmmap` style footprint, not RSS).
   If it fails or takes more than a few seconds, fall back to a reduced
   default list set on iOS or a staged background compile with progress.
   Decide before building the bottom bar.
5. **Chrome.** iPhone: bottom bar with URL and actions, swipe to switch tabs,
   space dots above it, the tab outline as a sheet, long-press for the shared
   context menu builders. iPad: `NavigationSplitView` with the sidebar rows
   from NookUI. Touch drag via `.draggable` / `.dropDestination` calling
   `TabsController.drop(...)`. `TabCompositorManager` tuned for jetsam.
   Downloads to the app container with `LSSupportsOpeningDocumentsInPlace`.
6. **Open design questions**: answered 2026-09-18, see the spec's Phase 3
   decisions (indented outline for folders, four-column tile grid for
   favorites, settings visual pass out of Phase 3).
7. **Entitlements.** Apply for `com.apple.developer.web-browser` now; the
   review takes time and it is the difference between a browser and a viewer.
   Team ZHB786H6YN needs an iOS provisioning profile.

## Rules that carried from Phase 2

- Platform differences live in `NookDesign.swift` or in a thin wrapper file
  (`Platform.swift`, `Haptics.swift`, `HoverTracking.swift`), never in a view
  body; a file that needs more than one `#if os` gets a `+iOS.swift` sibling.
- Zero behaviour change on macOS. Every task ends with a macOS Debug build;
  the branch ends with a signed Release build and a hands-off runtime check.
- Hands-off verification on the Mac: `open -g`, DevMCP over curl, `log show`,
  `defaults`. Never take the screen. On iOS use the simulator (`xcrun simctl`)
  and its `log stream`; `DevMCPServer` is macOS-only today and porting it to
  the simulator is worth a task of its own, since it is how every check runs.
- One writer on the tree at a time; reviews are read-only and can run in
  parallel. Work on a branch; commit per task; disclose AI assistance.
- Crash hazard learned 2026-09-18: an ObjC exception (`NSInvalidArgumentException`
  from `JSONSerialization` on a bare `String`, which `try?` cannot catch)
  unwinding out of a `@MainActor` task corrupts the executor state, and the
  next `MainActor.assumeIsolated` anywhere segfaults with no app frames. Never
  mark an SDK `NS_SWIFT_UI_ACTOR` delegate requirement `nonisolated` plus
  `assumeIsolated`. Encode with `.fragmentsAllowed` or `isValidJSONObject`.

## Known debt to leave alone unless it blocks you

Three hex parsers coexist (`NookDesign` `Color(hex:)`, `NookWeb`
`PlatformColor.fromHex`, `Nook/Utils/Colors.swift` `NSColor(hex:)` with one
consumer). `Surface.incognitoAccent` duplicates `SpaceGradient.incognito`.
`MainActor.assumeIsolated` in `BrowserManager+Blocker.swift` (make
`BrowserConfiguration` `@MainActor`). `DownloadManager` splits after
`fix/download-memory` is merged. `withTimeout`'s `T: Sendable` is satisfied by
`[String: Any]` only in Swift 5 mode.

## Manual checks nobody has done on macOS since the extraction

Context menu items in secondary and private windows; pin, unpin, reopen
closed, drag reorder, split, second window; `alert()`, file picker, extension
badge on tab switch, download, Peek, zoom, mute, PiP; Instagram, Facebook and
VSCO download button; Shorts and Reels hidden; signed-in Facebook and
Instagram ad removal; each moved settings tab; Settings > AI. The signed
Release runtime check covered tabs, blocking, user-script stability and
relaunch only.
