# iOS Port Phase 2: Extract the Shared Packages

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the platform-neutral half of Nook into local SPM packages so an iOS target can consume it, with zero behaviour change on macOS.

**Architecture:** Seven local packages in a straight dependency line (TabsCore → Settings, Design → Blocker, Tweaks → Web → UI). Files move with `git mv`; every type the app touches gains `public`; the places where a moved file reached `BrowserManager` or `ExtensionManager.shared` become small protocols the app conforms to. Platform differences are resolved in `NookDesign.swift` or in `+macOS.swift` sibling files, never in view bodies.

**Tech Stack:** Swift 5 language mode, swift-tools-version 6.0, Xcode 27 (SDK 27, deployment target macOS 26 / iOS 26), SwiftUI, WebKit, SwiftData, adblock-rust via a C ABI xcframework.

**Spec:** `docs/superpowers/specs/2026-09-17-ios-port-design.md` (Architecture and Phase 2 sections).

## Global Constraints

- Zero behaviour change on macOS. Every task ends with a Debug build that launches and browses. The final task adds a Developer ID signed Release build.
- Package platforms: `[.macOS("26.0"), .iOS("26.0")]`, `swiftLanguageMode(.v5)`, tools version 6.0, matching `Packages/NookTabsCore/Package.swift`.
- No `#available` guards below macOS 26.
- No AppKit import in a package file unless the file is a `+macOS.swift` sibling wrapped in `#if os(macOS)`. A shared file needing more than one `#if os` gets split.
- Design tokens: platform values resolved inside `NookDesign.swift` only.
- Every blocker-owned user script keeps its `// Nook Content Blocker` / `// Nook` prefix. Resource loading switches from `Bundle.main` to `Bundle.module`.
- Never re-add a user script Nook does not own (`WKUserScript+NookOwned.swift`).
- The tree may hold another session's uncommitted edits. Check `git status` before each commit and stage only this task's paths.
- Commit messages end with `Assisted by Claude Code.` (CONTRIBUTING.md AI disclosure).
- Build commands (run from the repo root, keep output short with `| tail -5` or `| grep -E "error|warning: unre|BUILD"`):
  - Debug: `xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build 2>&1 | grep -E "error:|BUILD" | head -20`
  - Package alone: `cd Packages/<Name> && swift build 2>&1 | tail -3` (packages that import WebKit or SwiftData build fine with `swift build` on macOS).
  - Release, Developer ID: see Task 9.
- Xcode uses filesystem-synchronized groups, so a file that leaves `Nook/`, `Settings/`, `Navigation/` or `UI/` leaves the app target automatically, and a file added under `Packages/` is picked up by SPM automatically. The only pbxproj edits are adding package references (Task 1 shows the exact edit) and removing the Rust search paths (Task 0).

---

### Task 0: Rust static library as an xcframework

**Files:**
- Modify: `Nook/ThirdParty/AdblockRustFFI/build.sh`
- Create: `Nook/ThirdParty/AdblockRustFFI/NookAdblock.xcframework/` (generated, committed)
- Delete: `Nook/ThirdParty/AdblockRustFFI/lib/macos-arm64/libnook_adblock.a`
- Modify: `Nook.xcodeproj/project.pbxproj` (lines ~421-431 and ~482-492: `HEADER_SEARCH_PATHS`, `LIBRARY_SEARCH_PATHS`, `-lnook_adblock` in `OTHER_LDFLAGS`; lines 33-42: membership exceptions)
- Modify: `Nook/Supporting Files/Nook-Bridging-Header.h` (drop `#import "nook_adblock.h"` only in Task 3, when the blocker leaves the app; in this task the app still calls the C ABI directly)

**Interfaces:**
- Produces: `NookAdblock.xcframework` with a `macos-arm64` library slice, headers folder holding `nook_adblock.h` plus a `module.modulemap` declaring `module NookAdblockFFI { header "nook_adblock.h"; export * }`. Task 3 declares it as `.binaryTarget(name: "NookAdblockFFI", path: "../../Nook/ThirdParty/AdblockRustFFI/NookAdblock.xcframework")`.

- [ ] **Step 1: Add the modulemap next to the header**

Create `Nook/ThirdParty/AdblockRustFFI/include/module.modulemap`:

```
module NookAdblockFFI {
    header "nook_adblock.h"
    export *
}
```

- [ ] **Step 2: Rewrite build.sh to emit the xcframework**

Replace the body after `cargo test --release` with:

```sh
cargo build --release --target aarch64-apple-darwin
# iOS slices (phase 3): rustup target add aarch64-apple-ios aarch64-apple-ios-sim,
# cargo build for each, and add two more -library/-headers pairs below.
rm -rf NookAdblock.xcframework
xcodebuild -create-xcframework \
  -library "$CARGO_TARGET_DIR/aarch64-apple-darwin/release/libnook_adblock.a" -headers include \
  -output NookAdblock.xcframework
ls NookAdblock.xcframework
```

Remove the `mkdir -p lib/macos-arm64` and `cp ... lib/macos-arm64/` lines and the trailing `ls -lh lib/...`.

- [ ] **Step 3: Run it**

Run: `sh Nook/ThirdParty/AdblockRustFFI/build.sh 2>&1 | tail -5`
Expected: `cargo test` passes, `NookAdblock.xcframework/Info.plist` and `NookAdblock.xcframework/macos-arm64/` exist. Then `git rm -r Nook/ThirdParty/AdblockRustFFI/lib`.

- [ ] **Step 4: Point the app at the framework for now**

In `project.pbxproj`, in both build configurations, replace the `HEADER_SEARCH_PATHS` value `"$(PROJECT_DIR)/Nook/ThirdParty/AdblockRustFFI/include"` with `"$(PROJECT_DIR)/Nook/ThirdParty/AdblockRustFFI/NookAdblock.xcframework/macos-arm64/Headers"` and the `LIBRARY_SEARCH_PATHS` value with `"$(PROJECT_DIR)/Nook/ThirdParty/AdblockRustFFI/NookAdblock.xcframework/macos-arm64"`. Leave `-lnook_adblock`. In the membership exceptions list replace the two `include/...` and `lib/...` lines with `ThirdParty/AdblockRustFFI/include/nook_adblock.h`, `ThirdParty/AdblockRustFFI/include/module.modulemap`, and `ThirdParty/AdblockRustFFI/NookAdblock.xcframework`. (Task 3 removes all of this when the blocker moves into its package.)

- [ ] **Step 5: Debug build and launch**

Run the Debug build command. Expected: `BUILD SUCCEEDED`. Launch `build/Build/Products/Debug/Nook.app`, load `https://www.youtube.com`, confirm ads are blocked (no pre-roll), quit.

- [ ] **Step 6: Commit**

```bash
git add Nook/ThirdParty/AdblockRustFFI Nook.xcodeproj/project.pbxproj
git commit -m "build(adblock): ship the Rust library as an xcframework

build.sh now emits NookAdblock.xcframework (macos-arm64, header and modulemap
inside) instead of a bare .a, so NookBlocker can declare it as a binaryTarget
and phase 3 can add iOS slices.

Assisted by Claude Code."
```

---

### Task 1: NookSettings package

**Files:**
- Create: `Packages/NookSettings/Package.swift`
- Move (git mv): `Settings/NookSettingsService.swift` → `Packages/NookSettings/Sources/NookSettings/NookSettingsService.swift`
- Move: `Nook/Models/Settings/SiteSearch.swift`, `Nook/Models/AI/AIModels.swift`, `Nook/Models/AI/MCPModels.swift`, `Nook/Managers/SponsorBlockManager/SponsorBlockModels.swift`, `Nook/Managers/SiteRoutingManager/SiteRoutingRule.swift` → `Packages/NookSettings/Sources/NookSettings/`
- Move the `SidebarPosition` enum out of `Nook/Components/Sidebar/Menu/SidebarMenu.swift` (lines 15-20) and the `YouTubeHomeSection` enum out of `Nook/Managers/YouTubeTweaks/YouTubeTweaks.swift` (line 16 onward) into `Packages/NookSettings/Sources/NookSettings/SettingsValueTypes.swift`.
- Modify: `Packages/NookSettings/Sources/NookSettings/NookSettingsService.swift` (remove `currentSettingsTab`, remove the `DevMCPServer` call, `public` pass)
- Create: `Nook/Components/Settings/SettingsNavigation.swift` (holds `currentSettingsTab` as an app-side `@Observable` singleton `SettingsNavigation.shared`)
- Modify: the 9 files that read `nookSettings.currentSettingsTab` (find with `grep -rln currentSettingsTab Nook App`) to use `SettingsNavigation.shared.currentSettingsTab`
- Modify: `Nook/Components/Settings/Tabs/AI.swift`: the Browser Control toggle gains `.onChange(of: settings.browserControlServerEnabled) { DevMCPServer.shared.applyEnabledSetting($1) }`
- Modify: `Nook.xcodeproj/project.pbxproj` (package reference + product dependency)
- Modify: every file that references a moved type without an import (the build tells you; add `import NookSettings`)

**Interfaces:**
- Produces: `public final class NookSettingsService` (`@Observable`, `@MainActor`), every stored property `public`, `public init(userDefaults:)` and whatever initializer `NookApp` uses today; `public enum SidebarPosition`, `public enum YouTubeHomeSection`, `public enum SponsorBlockCategory`, `public enum SponsorBlockSkipOption`, `public struct SiteRoutingRule`, `public struct CustomSearchEngine`, `public struct SiteSearchEntry`, `public enum AIProviderType`, `public final class AIKeychainStorage`, `public struct MCPServerConfig` and the rest of `AIModels.swift`/`MCPModels.swift`.
- `SiteSearchEntry.color` (`Color(hex:)`) leaves the model: delete it from the struct and add `extension SiteSearchEntry { var color: Color { Color(hex: colorHex) } }` in `Nook/Components/Settings/Tabs/SiteSearchEditor.swift`, so the package imports Foundation only.

- [ ] **Step 1: Create the package**

`Packages/NookSettings/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookSettings",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [.library(name: "NookSettings", targets: ["NookSettings"])],
    targets: [
        .target(name: "NookSettings", swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
```

- [ ] **Step 2: Move the files with git mv, extract the two enums, drop SwiftUI**

`git mv` each file listed above. Cut `SidebarPosition` and `YouTubeHomeSection` into `SettingsValueTypes.swift`. Change `import SwiftUI` to `import Foundation` in every moved file; move `SiteSearchEntry.color` to the app as described. Delete `var currentSettingsTab: SettingsTabs = .general` and delete the `DevMCPServer.shared.applyEnabledSetting(...)` line from the `browserControlServerEnabled` setter (keep the UserDefaults write).

- [ ] **Step 3: Build the package alone and make it public**

Run: `cd Packages/NookSettings && swift build 2>&1 | grep -E "error" | head`. Fix every error by adding `public` (types, inits, properties, methods, enum cases are public with the enum). Repeat until `swift build` prints `Build complete!`.

- [ ] **Step 4: Wire the package into the app**

In `project.pbxproj`, copy the three `NookTabsCore` entries with new IDs. Exact edits:

```
/* PBXBuildFile */   C0DE7AB50000000000000013 /* NookSettings in Frameworks */ = {isa = PBXBuildFile; productRef = C0DE7AB50000000000000012 /* NookSettings */; };
/* Frameworks build phase files list */   C0DE7AB50000000000000013 /* NookSettings in Frameworks */,
/* packageProductDependencies */   C0DE7AB50000000000000012 /* NookSettings */,
/* packageReferences of the project (next to the XCLocalSwiftPackageReference for NookTabsCore) */   C0DE7AB50000000000000011 /* XCLocalSwiftPackageReference "Packages/NookSettings" */,
/* XCLocalSwiftPackageReference section */
		C0DE7AB50000000000000011 /* XCLocalSwiftPackageReference "Packages/NookSettings" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = Packages/NookSettings;
		};
/* XCSwiftPackageProductDependency section */
		C0DE7AB50000000000000012 /* NookSettings */ = {
			isa = XCSwiftPackageProductDependency;
			productName = NookSettings;
		};
```

Find each of the five places by grepping for the matching `NookTabsCore` line (`grep -n NookTabsCore Nook.xcodeproj/project.pbxproj`). Later tasks use IDs `...0021/22/23` (Design), `...0031/32/33` (Blocker), `...0041/42/43` (Tweaks), `...0051/52/53` (Web), `...0061/62/63` (UI).

- [ ] **Step 5: Create SettingsNavigation and fix the app**

`Nook/Components/Settings/SettingsNavigation.swift`:

```swift
import Observation

/// Which settings tab the Settings window shows. Window navigation state, not a setting:
/// it never syncs, so it stays in the app rather than in NookSettings.
@MainActor @Observable
final class SettingsNavigation {
    static let shared = SettingsNavigation()
    var currentSettingsTab: SettingsTabs = .general
}
```

Replace every `nookSettings.currentSettingsTab` / `settings.currentSettingsTab` / `browserManager.nookSettings.currentSettingsTab` with `SettingsNavigation.shared.currentSettingsTab`. Add the `.onChange` in `AI.swift`. Run the Debug build; add `import NookSettings` wherever the compiler reports an unknown type.

- [ ] **Step 6: Debug build, launch, verify**

Expected: `BUILD SUCCEEDED`. Launch, open Settings (Cmd+,), change a value in General, quit, relaunch, confirm it persisted. Open Settings > AI, toggle Browser Control on, confirm `curl -s http://127.0.0.1:47823/mcp` connects (any HTTP response), toggle off.

- [ ] **Step 7: Commit**

```bash
git add Packages/NookSettings Settings Nook Nook.xcodeproj/project.pbxproj App
git commit -m "refactor(settings): move NookSettingsService into Packages/NookSettings

Foundation-only package holding the settings service and the value types it
stores, so a sync backend can sit under it later. currentSettingsTab is window
navigation state and stays in the app as SettingsNavigation; the Browser
Control toggle drives DevMCPServer from the AI settings tab instead of from
the setter.

Assisted by Claude Code."
```

---

### Task 2: NookDesign package

**Files:**
- Create: `Packages/NookDesign/Package.swift` (same shape as Task 1, name `NookDesign`, no dependencies)
- Move: `Nook/Design/NookDesign.swift` → `Packages/NookDesign/Sources/NookDesign/NookDesign.swift`
- Move: `Nook/Extensions/View+GlassEffect.swift` → `Packages/NookDesign/Sources/NookDesign/View+GlassEffect.swift`
- Modify: `Nook.xcodeproj/project.pbxproj` (IDs `...0021/22/23`)
- Modify: every UI file (add `import NookDesign`; the build lists them)

**Interfaces:**
- Produces: `public enum NookDesign` with public nested `Radius`, `Spacing`, `Size`, `Font`, `Motion`, `Surface`, `Elevation` and all their members; `public extension View { func nookElevation(_:) ; func nookGlassEffect(in:) }`.
- `NookDesign.swift` currently imports AppKit. Replace with `#if canImport(AppKit) import AppKit #elseif canImport(UIKit) import UIKit #endif` and, for the one or two NS values it uses (`NSColor.windowBackgroundColor` in `Surface`), define at the top of the file:

```swift
#if canImport(AppKit)
typealias PlatformColor = NSColor
#else
typealias PlatformColor = UIColor
#endif
```

and a `static var windowBackground: Color` in `Surface` that returns `Color(nsColor: .windowBackgroundColor)` under `#if os(macOS)` and `Color(uiColor: .systemBackground)` otherwise. `Size.row` becomes:

```swift
#if os(iOS)
public static let row: CGFloat = 44
#else
public static let row: CGFloat = 32
#endif
```

This is the only file allowed to hold platform conditionals for token values.

- [ ] **Step 1: Create the package, move the two files, add the conditionals above**
- [ ] **Step 2: `swift build` in the package; add `public` until it builds**
- [ ] **Step 3: Wire into pbxproj (IDs `...0021/22/23`), Debug build, add `import NookDesign` where reported**
- [ ] **Step 4: Launch and compare**: sidebar row height, corner radii and the command palette glass look unchanged next to a screenshot taken before the task (take one with the running app from Task 1 first).
- [ ] **Step 5: Commit** `refactor(design): move design tokens into Packages/NookDesign` with the disclosure line.

---

### Task 3: NookBlocker package

**Files:**
- Create: `Packages/NookBlocker/Package.swift`
- Move: the 7 Swift files in `Nook/Managers/ContentBlockerManager/` → `Packages/NookBlocker/Sources/NookBlocker/`
- Move: `Nook/Managers/ContentBlockerManager/Resources/` (all `.txt` and `.js` except `youtube-sponsorblock.js`, which Task 4 takes) → `Packages/NookBlocker/Sources/NookBlocker/Resources/`
- Move: `Nook/Managers/PrivacyManager/OAuthDetector.swift` → `Packages/NookBlocker/Sources/NookBlocker/OAuthDetector.swift` (Foundation only; the blocker's OAuth exemption needs it and `PageSession` reaches it through NookWeb's dependency on NookBlocker)
- Move: `Nook/Utils/WebKit/WKUserScript+NookOwned.swift` → `Packages/NookBlocker/Sources/NookBlocker/` (the blocker owns the `.nookOwned` rule)
- Create: `Packages/NookBlocker/Sources/NookBlocker/BlockablePage.swift` (the seam)
- Modify: `Nook/Managers/BrowserManager/BrowserManager.swift` (conform to `ContentBlockerHost`, set `contentBlockerManager.host = self`)
- Modify: `Nook.xcodeproj/project.pbxproj`: remove `HEADER_SEARCH_PATHS`, `LIBRARY_SEARCH_PATHS`, and `-lnook_adblock` (both configs); remove the AdblockRustFFI membership exceptions; add package IDs `...0031/32/33`
- Modify: `Nook/Supporting Files/Nook-Bridging-Header.h`: delete `#import "nook_adblock.h"`
- Modify: `.github/workflows/macos-notarize.yml` if it references `lib/macos-arm64` (grep; it should not)

**Interfaces:**
- Consumes: `NookSettingsService` (Task 1) for the 5 settings the blocker reads (`grep -n "settings\." ...`).
- Produces:

```swift
import WebKit

/// What the blocker needs from a live page. PageSession (NookWeb) conforms.
@MainActor public protocol BlockablePage: AnyObject {
    var itemID: UUID { get }
    var isPrivate: Bool { get }
    var currentURL: URL? { get }
    var webView: WKWebView? { get }
    func reload()
}

/// How the blocker finds pages. BrowserManager conforms.
@MainActor public protocol ContentBlockerHost: AnyObject {
    func page(for webView: WKWebView) -> BlockablePage?
    /// Pages visible in any window, for reload after a rule change.
    var visiblePages: [BlockablePage] { get }
}
```

`ContentBlockerManager` gains `public weak var host: ContentBlockerHost?` and `public init(settings: NookSettingsService)`; `weak var browserManager` is deleted. Every method that took a `PageSession` takes a `BlockablePage`. If a call site uses a PageSession member not in the protocol above, add it to the protocol (keep the list minimal; list the final members in the commit message).

- [ ] **Step 1: Package manifest**

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookBlocker",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [.library(name: "NookBlocker", targets: ["NookBlocker"])],
    dependencies: [
        .package(path: "../NookTabsCore"),
        .package(path: "../NookSettings"),
    ],
    targets: [
        .binaryTarget(name: "NookAdblockFFI", path: "../../Nook/ThirdParty/AdblockRustFFI/NookAdblock.xcframework"),
        .target(
            name: "NookBlocker",
            dependencies: ["NookAdblockFFI", "NookTabsCore", "NookSettings"],
            resources: [.copy("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

`.copy("Resources")` keeps the folder, so lookups become `Bundle.module.url(forResource: name, withExtension: "js", subdirectory: "Resources")`. Replace every `Bundle.main.url(forResource:` / `Bundle.main.path(forResource:` in the moved files accordingly (9 sites, listed by `grep -n "Bundle.main" Packages/NookBlocker -r`). `Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", ...)` stays as is: `Bundle.main` is the app bundle at runtime and that is the subsystem we want.

- [ ] **Step 2: git mv the files, add the seam file, replace `browserManager` uses**

`grep -n "browserManager\|PageSession" Packages/NookBlocker -r` lists every site. `browserManager?.tabs.session(for: webView)` → `host?.page(for: webView)`; the `windowRegistry` use → `host?.visiblePages ?? []`; settings reads → the injected `settings`.

- [ ] **Step 3: `swift build` in the package until it builds; public pass**

Expected end: `Build complete!`. `RustContentBlockingConverter.swift` and `BlockerEngine.swift` now `import NookAdblockFFI` instead of relying on the bridging header.

- [ ] **Step 4: App side**

Wire the package (IDs `...0031/32/33`), strip the search paths and linker flag and membership exceptions from the pbxproj, drop the header import from the bridging header. In `BrowserManager`: `extension BrowserManager: ContentBlockerHost { func page(for webView: WKWebView) -> BlockablePage? { tabs.session(for: webView) } ; var visiblePages: [BlockablePage] { /* every window's selected session plus split panes, via tabs.isVisibleInAnyWindow */ } }`, and `extension PageSession: BlockablePage` in the app for now (moves into NookWeb in Task 6). Update the `ContentBlockerManager(...)` construction to pass `settings:` and set `.host = self`.

- [ ] **Step 5: Debug build, launch, verify**

Load youtube.com (no pre-roll), facebook.com signed in (no Sponsored posts), a news site; toggle the blocker off and on in Settings > Ad Blocker and confirm the page reloads with ads and then without; allowlist a site and confirm it. Check `log stream --predicate 'subsystem == "com.baingurley.nook"' --level info` shows the `ContentBlocker` category compiling rules from the bundled snapshots.

- [ ] **Step 6: Commit** `refactor(blocker): move the content blocker into Packages/NookBlocker` naming the seam members, plus the disclosure line.

---

### Task 4: NookTweaks package

**Files:**
- Create: `Packages/NookTweaks/Package.swift` (dependencies NookTabsCore, NookSettings; `resources: [.copy("Resources")]`)
- Move: `Nook/Managers/YouTubeTweaks/YouTubeTweaks.swift`, `Nook/Managers/FacebookTweaks/FacebookTweaks.swift`, `Nook/Managers/SocialImageTweaks/SocialImageTweaks.swift`, `Nook/Managers/SponsorBlockManager/SponsorBlockManager.swift`, `Nook/Managers/SiteRoutingManager/SiteRoutingManager.swift` → `Packages/NookTweaks/Sources/NookTweaks/`
- Move: `youtube-tweaks.js`, `social-image-download.js`, `social-video-source.js` (from the tweak folders), `youtube-sponsorblock.js` (from the blocker's Resources; if Task 3 already moved it into NookBlocker, `git mv` it from there) → `Packages/NookTweaks/Sources/NookTweaks/Resources/`
- Create: `Packages/NookTweaks/Sources/NookTweaks/TweaksHost.swift`
- Modify: `BrowserManager.swift` (conformances, construction)

**Interfaces:**
- Produces:

```swift
/// SiteRoutingManager moves a page to another space. BrowserManager conforms.
@MainActor public protocol SiteRoutingHost: AnyObject {
    /// The space the given page is shown in, or the active window's space when nil.
    func currentSpaceID(for page: AnyObject?) -> UUID?
    /// Move the page's item to `spaceID` and show it there. Returns false if nothing moved.
    func move(page: AnyObject, toSpace spaceID: UUID) -> Bool
    /// Open `url` in `spaceID`, used when there is no page yet (popups, external links).
    func open(url: URL, inSpace spaceID: UUID)
}

/// SocialImageTweaks saves media through the app's download path.
@MainActor public protocol MediaDownloading: AnyObject {
    func downloadImage(at url: URL, from webView: WKWebView)
}
```

Read `SiteRoutingManager.applyRoute(url:from:)` and the other `browserManager` site before finalising the three members: the protocol must carry exactly what those call sites need, no more. `SponsorBlockManager` gets `public init(settings: NookSettingsService)`; `SocialImageTweaks` gets `public static var downloader: MediaDownloading?` set by `BrowserManager` (it is a stateless enum today; keep it that way). `YouTubeTweaks.apply` and `FacebookTweaks` take `settings:` as a parameter where they read `browserManager?.nookSettings` today.

- [ ] **Step 1: Manifest, git mv, Bundle.module, seam file**
- [ ] **Step 2: `swift build` until clean; public pass**
- [ ] **Step 3: App side**: pbxproj IDs `...0041/42/43`; `BrowserManager: SiteRoutingHost`, conform `FocusableWKWebView`'s owner (BrowserManager) to `MediaDownloading` by forwarding to `FocusableWKWebView.downloadImage`; pass `settings:` at the call sites in `PageSession+Navigation.swift` (`YouTubeTweaks.apply`, `FacebookTweaks`) and construct `SponsorBlockManager(settings:)`.
- [ ] **Step 4: Debug build, launch, verify**: YouTube Shorts hidden with the toggle on; SponsorBlock skips a sponsored segment on a known video (e.g. any Linus Tech Tips upload); an Air Traffic Control rule routes `github.com` to a second space; right-click a photo on instagram.com shows the download button.
- [ ] **Step 5: Commit** `refactor(tweaks): move site tweaks into Packages/NookTweaks` with disclosure.

---

### Task 5: NookWeb, part 1: the clean leaves

**Files:**
- Create: `Packages/NookWeb/Package.swift`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NookWeb",
    platforms: [.macOS("26.0"), .iOS("26.0")],
    products: [.library(name: "NookWeb", targets: ["NookWeb"])],
    dependencies: [
        .package(path: "../NookTabsCore"),
        .package(path: "../NookSettings"),
        .package(path: "../NookDesign"),
        .package(path: "../NookBlocker"),
        .package(path: "../NookTweaks"),
        .package(url: "https://github.com/will-lumley/FaviconFinder.git", from: "5.0.0"),
    ],
    targets: [
        .target(name: "MuteableWKWebView", path: "Sources/MuteableWKWebView", publicHeadersPath: "include"),
        .target(
            name: "NookWeb",
            dependencies: ["MuteableWKWebView", "NookTabsCore", "NookSettings", "NookDesign", "NookBlocker", "NookTweaks", "FaviconFinder"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
```

  Copy the FaviconFinder version requirement from `Nook.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` so the app and the package resolve the same version.
- Move: `Nook/ThirdParty/MuteableWKWebView/*.{h,m,c}` → `Packages/NookWeb/Sources/MuteableWKWebView/` with `MuteableWKWebView.h` in `include/` and the private headers beside the `.m` files. Delete the `README.md` membership exception for it in the pbxproj. Remove `#import "MuteableWKWebView.h"` from the bridging header; if the bridging header is then empty, delete it and the `SWIFT_OBJC_BRIDGING_HEADER` setting in both configs.
- Move into `Packages/NookWeb/Sources/NookWeb/`: `Nook/Models/Profile/Profile.swift`, `Nook/Utils/BrowserPerformance.swift`, `Nook/Models/History/HistoryEntity.swift`, `Nook/Managers/HistoryManager/HistoryManager.swift`, `Nook/Managers/SearchManager/SearchManager.swift`, `Nook/Managers/SearchManager/Utils.swift`, `Nook/Managers/WindowRegistry/WindowRegistry.swift`, `Nook/Browser/FaviconCache.swift`, `Nook/Browser/SpaceRecord+UI.swift`, `Nook/Utils/WebKit/WebContextMenuBridge.swift`.
- Create: `Packages/NookWeb/Sources/NookWeb/Platform.swift`:

```swift
#if canImport(AppKit)
import AppKit
public typealias PlatformImage = NSImage
public typealias PlatformColor = NSColor
#else
import UIKit
public typealias PlatformImage = UIImage
public typealias PlatformColor = UIColor
#endif
```

**Interfaces:**
- `FaviconCache`: replace `NSImage`/`NSBitmapImageRep` with `PlatformImage` and a `pngData()` helper in `Platform.swift`: on macOS `NSBitmapImageRep(data: image.tiffRepresentation ?? Data())?.representation(using: .png, properties: [:])`, on iOS `image.pngData()`. `SwiftUI.Image(nsImage:)` → `Image(platformImage:)` helper defined in `Platform.swift` under the same `#if`.
- `SpaceRecord+UI` (`NSColor` → `PlatformColor`, `Color(nsColor:)` → helper).
- `WindowRegistry` references `BrowserManager.setupWindowState` once: replace with `public var onWindowRegister: ((BrowserWindowState) -> Void)?` and call it; `NookApp` sets it (it already sets a callback per the CLAUDE.md `onWindowRegister` note; check and reuse).
- `SearchManager` references `BrowserWindowState` and `TabsController`: both move in Task 6, so in this task `SearchManager` moves but its two uses are left compiling by moving `BrowserWindowState` too (it is `Foundation + NookTabsCore + SwiftUI`, uses `NSWindow` for `window` and frame strings, `CommandPalette`, `ExtensionLibraryPanelController`, `ShortcutConflictInfo`, `Tabs`, `Profile`). Split it: `BrowserWindowState.swift` keeps the shared state (`spaceID`, `selectedItemBySpace`, `split`, private tree/sessions/closed, `ephemeralProfile`, sidebar width), and `BrowserWindowState+macOS.swift` in the app (`Nook/Models/`) holds an `extension BrowserWindowState` with `window: NSWindow?`, `commandPalette`, `extensionLibraryPanelController`, `shortcutConflictInfo`, `sidebarMenuSelectedTab`, `isCommandPaletteVisible`. Since stored properties cannot live in an extension, the shared class keeps them typed `AnyObject?` / `Any?` with `@ObservationIgnored` and the app extension exposes typed accessors (the file already does this for `_extensionLibraryPanelController`; follow that pattern).
- `HistoryManager` uses `BrowserPerformance` (moves with it) and SwiftData; the app's `BrowserManager.schema` keeps listing `HistoryEntity` via `import NookWeb`.

- [ ] **Step 1: Manifest, ObjC target, git mv, Platform.swift**
- [ ] **Step 2: `swift build` in the package until clean; public pass** (temporarily stub nothing: if a moved file needs `TabsController`, it waits for Task 6, so move exactly the list above and no more).
- [ ] **Step 3: App side**: pbxproj IDs `...0051/52/53`, `import NookWeb` where needed, bridging header cleanup, `BrowserWindowState+macOS.swift`.
- [ ] **Step 4: Debug build, launch, verify**: history records visits (Sidebar menu > History), favicons show on rows after restart, search suggestions appear in the command palette, mute a tab (the MuteableWKWebView path) and confirm audio stops.
- [ ] **Step 5: Commit** `refactor(web): start Packages/NookWeb with history, search, favicons, window state` with disclosure.

---

### Task 6: NookWeb, part 2: TabsController and PageSession

**Files:**
- Move into `Packages/NookWeb/Sources/NookWeb/`: `Nook/Browser/TabsController.swift`, `Nook/Browser/TabsController+Intents.swift`, `Nook/Browser/Session/PageSession.swift`, `PageSession+Navigation.swift`, `PageSession+Scripts.swift`, `PageSession+Media.swift`, `PageSession+UIDelegate.swift`, `Nook/Models/BrowserConfig/BrowserConfig.swift`, `Nook/Utils/WebKit/FocusableWKWebView.swift` (split, see below), `Nook/Components/Sidebar/Outline/TabsController+Sidebar.swift` and `Nook/Components/Sidebar/SpaceSection/TabsController+SpaceChrome.swift` (both are `TabsController` extensions with no AppKit; check `TabsController+Sidebar.swift`'s one NS symbol and move it to the app if it is not Foundation).
- Create: `Packages/NookWeb/Sources/NookWeb/PageSessionDelegate.swift`, `WebViewProvider.swift`, `TabEventObserver.swift`, `AlertPresenter.swift`
- Create in the app: `Nook/Utils/WebKit/FocusableWKWebView+macOS.swift` (the NSEvent/NSMenu/NSSavePanel/WebContextMenu parts), `Nook/Browser/TabsController+macOS.swift` (the `NSApplication`/`NSRunningApplication` uses and the `NSAlert` for the read-only notice, via `AlertPresenter`), `Nook/Managers/BrowserManager/BrowserManager+NookWeb.swift` (all conformances)
- Modify: `BrowserManager.swift`, `NookApp.swift` (construction and injection)

**Interfaces:**

```swift
// WebViewProvider.swift
@MainActor public protocol WebViewProvider: AnyObject {
    /// The web view a window should display for an item, creating or cloning as needed.
    func webView(for session: PageSession, in windowID: UUID) -> WKWebView?
    func releaseWebViews(for itemID: UUID)
}

// PageSessionDelegate.swift: the members PageSession reaches through browserManager today.
@MainActor public protocol PageSessionDelegate: AnyObject {
    func session(_ session: PageSession, didStartDownload download: WKDownload)
    func session(_ session: PageSession, requestPeekFor url: URL)
    func session(_ session: PageSession, beginIdentityFlow request: IdentityRequest)
    func loadZoom(for session: PageSession)
    func cleanupZoom(for session: PageSession)
    func session(_ session: PageSession, didChangeMuteState muted: Bool)
    func session(_ session: PageSession, requestPiPWith webView: WKWebView?)
    func session(_ session: PageSession, navigateAcrossWindowsTo url: URL)
    func handleKeyboardShortcut(_ event: Any, in session: PageSession) -> Bool
    func makeWebStoreHandler() -> WKScriptMessageHandler?
    func webViewConfiguration(for profile: Profile, isPrivate: Bool) -> WKWebViewConfiguration
}

// TabEventObserver.swift: the six ExtensionManager notifications plus the two access grants.
@MainActor public protocol TabEventObserver: AnyObject {
    func tabOpened(_ session: PageSession)
    func tabClosed(itemID: UUID)
    func tabActivated(_ session: PageSession, in windowID: UUID)
    func tabMoved(itemID: UUID)
    func tabPropertiesChanged(_ session: PageSession)
    func wakeBackgroundWorkers()
    func grantAccess(to url: URL, for session: PageSession)
}

// AlertPresenter.swift
@MainActor public protocol AlertPresenter: AnyObject {
    func presentAlert(title: String, message: String, buttons: [String]) async -> Int
    func presentOpenPanel(allowsMultiple: Bool, allowsDirectories: Bool) async -> [URL]
}
```

Before finalising each protocol, list the real call sites (`grep -n "browserManager" Nook/Browser -r` gives 80 lines; `grep -rn "ExtensionManager.shared" Nook/Browser` gives 21) and adjust member names and signatures to what those sites pass. The lists above are the expected shape; the call sites are the truth. `IdentityRequest` and `IdentityFlowResult` are nested in `AuthenticationManager` today; move those two types into `PageSessionDelegate.swift` as top-level public structs and typealias them back inside `AuthenticationManager` so its file does not change. `Placement` (defined in `TabsController.swift`) moves with it.

`TabsController` gains `public init(settings: NookSettingsService, windowRegistry: WindowRegistry, blocker: ContentBlockerManager, sponsorBlock: SponsorBlockManager, siteRouting: SiteRoutingManager, history: HistoryManager?, webViews: WebViewProvider, legacyProfiles: [(id: UUID, name: String)] = [], directory: URL = TabsController.defaultDirectory)` and public weak `sessionDelegate: PageSessionDelegate?`, `tabEvents: TabEventObserver?`, `alerts: AlertPresenter?`, `currentProfileProvider: (() -> Profile?)?` (for the one `browserManager?.currentProfile` use). `PageSession.init` drops `browserManager:` and reads everything through `controller`. `weak var browserManager` disappears from both.

`FocusableWKWebView` split: the shared class in the package keeps `owningSession`, `contextMenuBridge`, the download image entry point as a `MediaDownloading` conformance, and the WebKit-only parts; the `NSEvent`, `NSMenu`, `NSSavePanel`, `WebContextMenuItem`, `DestinationPreference`, `Download` parts move to `FocusableWKWebView+macOS.swift` in the app as an extension. If a stored property has to stay in the class for the macOS extension, keep it in the shared class typed as `Any?` with `@ObservationIgnored`. `BrowserConfig.swift` drops `import AppKit` if nothing in it needs AppKit (line 8 is the only import; check what uses it).

`PiPManager`, `AuthenticationManager`, `WebStoreScriptHandler`, `DownloadManager`, `WebContextMenu.swift` stay in the app and are reached only through `PageSessionDelegate`.

- [ ] **Step 1: git mv, create the four seam files, split FocusableWKWebView and TabsController, replace every `browserManager` and `ExtensionManager.shared` site**
- [ ] **Step 2: `swift build` in the package until clean; public pass** (this is the large one: expect several hundred `public` additions across TabsController and PageSession; `@Observable` classes need `public` on every property the app reads)
- [ ] **Step 3: App side**: `BrowserManager+NookWeb.swift` with `extension BrowserManager: WebViewProvider, PageSessionDelegate, TabEventObserver, AlertPresenter` (TabEventObserver forwards to `ExtensionManager.shared`; AlertPresenter wraps `NSAlert`/`NSOpenPanel`), construction order in `BrowserManager.init` (settings, registry, blocker, sponsorBlock, siteRouting, history, then `TabsController(...)`, then set the three delegates), `extension PageSession: BlockablePage` moves from the app into the package.
- [ ] **Step 4: Debug build, launch, verify by hand**: open, close, reopen (Cmd+Shift+T), pin, unpin, move to another space, drag reorder, split view, second window shows the same tab, close the second window, a popup (`window.open`) opens as a new tab, an `alert()` shows, a `<input type=file>` opens the panel, an extension badge updates on tab switch, a download starts, Peek on Shift+click, zoom persists per site, mute, PiP, quit and relaunch restores tabs. Check `log stream` for the `Tabs` category with no errors.
- [ ] **Step 5: Commit** `refactor(web): move TabsController and PageSession into Packages/NookWeb` naming the four protocols, with disclosure.

---

### Task 7: NookUI package

**Files:**
- Create: `Packages/NookUI/Package.swift` (dependencies NookDesign, NookWeb, NookSettings, NookTabsCore, Garnish if any moved view uses it)
- Move into `Packages/NookUI/Sources/NookUI/`:
  - Rows: `Nook/Components/Sidebar/SpaceSection/SpaceTab.swift`, `TabFolderView.swift`, `SplitTabRow.swift`, `SpaceSeparator.swift`, `Nook/Components/Sidebar/PinnedButtons/PinnedTabView.swift`
  - Space dots: `Navigation/Sidebar/SpacesList/SpacesList.swift`, `SpacesListItem.swift` (the `NSHapticFeedbackManager` line becomes `Haptics.alignment()` in a new `Packages/NookUI/Sources/NookUI/Haptics.swift`: `#if os(macOS) NSHapticFeedbackManager... #else UISelectionFeedbackGenerator().selectionChanged() #endif`, the one allowed platform conditional, in a wrapper type). Remove the two `Navigation/` membership-exception lines for them from the pbxproj.
  - Menus: `Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift`, `FolderContextMenu.swift`, `SpaceContextMenu.swift`
  - Leaves: `Nook/Components/WebsiteView/EmptyWebsiteView.swift`, `Nook/Components/FindBar/FindBarView.swift`, `Nook/Components/Toast/ToastView.swift`, `Nook/Components/Toast/ShortcutConflictToast.swift`, `Nook/Components/Sidebar/CopyURLToast/CopyURLToast.swift`, `Nook/Components/Sidebar/TabClosureToast/TabClosureToast.swift`
  - Settings tab bodies: `Nook/Components/Settings/Tabs/General.swift`, `Appearance.swift`, `Spaces.swift`, `AdBlocker.swift`, `AirTrafficControlSettingsView.swift`, `YouTube.swift`, `SocialMedia.swift`, `SiteSearchEditor.swift`, and the `SpaceAccentPicker` they use (find it: `grep -rn "struct SpaceAccentPicker"`).
- Create: `Packages/NookUI/Sources/NookUI/TabActions.swift`
- Modify: `BrowserManager.swift` (conform to `TabActions`), the views' call sites, `SettingsWindow.swift` (imports)

**Interfaces:**

```swift
/// App actions the shared rows and menus trigger that are not TabsController intents.
/// BrowserManager conforms on macOS.
@MainActor public protocol TabActions: AnyObject {
    func enterSplit(with itemID: UUID, in window: BrowserWindowState)
    func showDialog(_ dialog: AnyView)
    func closeDialog()
    func hideTabClosureToast()
    var tabClosureToastCount: Int { get }
    var accentColor: Color { get }
    func copyToPasteboard(_ string: String)
    func share(_ url: URL)
}
```

The eight members come from the grep in the survey (`browserManager.tabs` ×5 becomes the injected `TabsController`; `splitManager.enterSplit` ×2; `dialogManager.showDialog`/`closeDialog` ×3; `tabClosureToastCount` ×2; `hideTabClosureToast` ×2; `gradientColorManager.accentColor` ×2; `NSPasteboard` and `NSSharingServicePicker` in `TabContextMenu` lines 169-178). Verify against the files before finalising. The views take it as `@Environment(\.tabActions)` via a `public struct TabActionsKey: EnvironmentKey` in `TabActions.swift`; `WindowView` injects `.environment(\.tabActions, browserManager)`. `@EnvironmentObject var browserManager: BrowserManager` disappears from every moved file.

Rows that host drag sources (`NookDragSourceView`) stay in the app: if `SpaceTab.swift` or `PinnedTabView.swift` wraps itself in a drag source, split the visual row into the package (`TabRowLabel`) and leave the drag wrapper in the app file. Check `grep -n "NookDrag" ` on each before moving.

Settings tabs that read `browserManager` (`AdBlocker` ×5, `AirTrafficControl` ×10, `Spaces` ×7, `General` ×1) reach `ContentBlockerManager`, `SiteRoutingManager`, `TabsController` and `NookSettingsService`: inject them with `@Environment(TabsController.self)`, `@Environment(NookSettingsService.self)` (already injected per CLAUDE.md), and add `.environment(contentBlockerManager)` / `.environment(siteRoutingManager)` in `SettingsWindow` for the two managers. If either manager is `ObservableObject` rather than `@Observable`, use `.environmentObject`.

- [ ] **Step 1: Manifest, git mv, `TabActions.swift`, `Haptics.swift`, replace `browserManager` uses**
- [ ] **Step 2: `swift build` in the package until clean; public pass** (`public struct ... : View { public init(...) ; public var body }` for every moved view)
- [ ] **Step 3: App side**: pbxproj IDs `...0061/62/63`, `import NookUI`, environment injection in `WindowView` and `SettingsWindow`, `extension BrowserManager: TabActions`
- [ ] **Step 4: Debug build, launch, verify**: every row renders as before (compare with the Task 2 screenshot), right-click menus on a tab, folder and space work including "Move to Space", Copy URL and Share; find bar (Cmd+F) works; closing a tab shows the toast; empty space shows "Ah, peace."; each moved settings tab edits its value.
- [ ] **Step 5: Commit** `refactor(ui): move shared rows, menus, toasts and settings tabs into Packages/NookUI` with disclosure.

---

### Task 8: Docs

**Files:**
- Modify: `CLAUDE.md` (Top-Level Modules table gains a `Packages/` row listing the seven packages and the rule "platform values in the token file, seams are the protocols in NookBlocker/NookTweaks/NookWeb/NookUI"; update the Content Blocker, Tab Model, and Key Patterns entries whose paths moved: `Nook/Managers/ContentBlockerManager/` → `Packages/NookBlocker/Sources/NookBlocker/`, `Nook/Browser/` → `Packages/NookWeb/Sources/NookWeb/`, `Nook/Design/NookDesign.swift` → `Packages/NookDesign/...`, bridging header note, `WKUserScript+NookOwned.swift` path, `Resources/` path, `build.sh` output)
- Modify: `docs/adblocker-architecture.md` paths
- Modify: `Nook/ThirdParty/AdblockRustFFI/README.md` (xcframework)

- [ ] **Step 1: Update the paths and add the Packages row**
- [ ] **Step 2: Commit** `docs: record the phase 2 package layout` with disclosure.

---

### Task 9: Release build, signed, and the hand check

**Files:** none modified unless the Release build fails.

- [ ] **Step 1: Build Release with Developer ID**

```bash
xcodebuild -scheme Nook -configuration Release -arch arm64 -derivedDataPath build-release \
  CODE_SIGN_IDENTITY="Developer ID Application: Bain Gurley (ZHB786H6YN)" \
  CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=ZHB786H6YN \
  CODE_SIGN_ENTITLEMENTS="$PWD/Nook/Nook-CI.entitlements" \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO PROVISIONING_PROFILE_SPECIFIER="" \
  COMPILER_INDEX_STORE_ENABLE=NO 2>&1 | grep -E "error:|warning: .*Release|BUILD" | head
```

Expected: `BUILD SUCCEEDED`. Then `codesign -dv --verbose=2 build-release/Build/Products/Release/Nook.app 2>&1 | grep -E "Authority|TeamIdentifier"` shows `Developer ID Application: Bain Gurley`.

- [ ] **Step 2: Run the Release app through the Task 6 and Task 7 checklists** (Release-only traps: the `WKNSArray objectAtIndex:` SIGTRAP when toggling the blocker, so toggle it three times on youtube.com; open and close five tabs; quit and relaunch).
- [ ] **Step 3: Report** the result to the user with the exact commands run and anything that differed from Debug. No commit unless a fix was needed; a fix gets its own commit with disclosure.

---

## Self-review

- Spec coverage: xcframework (T0), NookSettings with sync notes (T1), Design tokens per platform (T2), Blocker with `Bundle.module` (T3), Tweaks (T4), Web seams: `WebViewProvider`, `PageSessionDelegate`, `TabEventObserver`, `AlertPresenter`, `PlatformImage`/`PlatformColor`, MuteableWKWebView as a C target, `+macOS.swift` splits (T5, T6), UI built now with `TabActions` and settings tab bodies (T7), DownloadManager stays (T6 notes), docs (T8), Debug and Developer ID Release verified by hand (every task, T9).
- Names used across tasks: `NookSettingsService` (T1) consumed in T3, T4, T6, T7; `BlockablePage`/`ContentBlockerHost` (T3) consumed in T6; `SiteRoutingHost`/`MediaDownloading` (T4) consumed in T6; `PlatformImage`/`PlatformColor` (T5) consumed in T6, T7; `BrowserWindowState` split (T5) consumed in T6, T7; pbxproj ID blocks per package fixed in T1.
- Known judgement calls left to the executor, each bounded by "the call sites are the truth": exact protocol member lists in T3, T4, T6, T7, and which stored properties in `BrowserWindowState` and `FocusableWKWebView` must stay in the shared class as `Any?`.
