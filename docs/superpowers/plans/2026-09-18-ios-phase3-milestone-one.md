# iOS Phase 3, Milestone One Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An iOS app target in `Nook.xcodeproj` that builds against the seven shared packages and loads one page with the content blocker active in the iPhone simulator, with no chrome beyond a URL field.

**Architecture:** The seven packages under `Packages/` already declare iOS 26. This milestone gives `NookBlocker`'s Rust binary its iOS slices, fixes whatever the packages fail to compile for iOS in their platform wrapper files, adds a second app target `NookiOS` whose sources live in `NookiOS/` at the repo root, and writes a `BrowserModel` that owns the managers and conforms to the package seams the way `BrowserManager` does on macOS, with one `WKWebView` per session and no-op conformances for everything a phone does not have. The gate at the end is a simulator run read through `log show` and a screenshot.

**Tech Stack:** Swift 5 language mode, SwiftUI, WebKit, Rust (adblock-rust FFI), Xcode 27, iOS 27 SDK, deployment target iOS 26.

**Spec:** `docs/superpowers/specs/2026-09-17-ios-port-design.md`, "Phase 3: the iOS app" and "Decisions, 2026-09-18". Handoff: `docs/ios-port-phase3-handoff.md`.

## Global Constraints

- Bundle id `com.gstudios.nook` for the iOS target too; team `ZHB786H6YN`; `IPHONEOS_DEPLOYMENT_TARGET = 26.0`; `SWIFT_VERSION = 5.0`; `TARGETED_DEVICE_FAMILY = "1,2"`.
- Zero behaviour change on macOS. Every task that touches a package or the project ends with a macOS Debug build (`xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO`).
- Platform differences live in `NookDesign.swift` or a thin wrapper file (`Platform.swift`, `Haptics.swift`, `HoverTracking.swift`), never in a view body; a file needing more than one `#if os` gets a `+iOS.swift` or `+macOS.swift` sibling.
- Work on `develop`. Plain commit messages, one per task, no attribution lines.
- Hands-off verification: the simulator via `xcrun simctl`, its log via `xcrun simctl spawn <udid> log show`, screenshots via `xcrun simctl io <udid> screenshot`. Never take the user's screen.
- Package iOS build command, run inside a package directory: `xcodebuild -scheme <Package> -destination 'generic/platform=iOS Simulator' -derivedDataPath /Users/bain/git/Nook/build-ios build`.
- Out of scope here: bottom bar, tab sheet, iPad split view, drag, downloads, the device compile spike, `DevMCPServer` on iOS, the entitlement request. Those are the second plan.

---

### Task 1: License pointer in every Swift source file

**Files:**
- Modify: every `*.swift` under `App/`, `CommandPalette/`, `Navigation/`, `Nook/` (except `Nook/ThirdParty/`), `Onboarding/`, `Settings/`, `UI/`, `Packages/*/Sources/`, `Packages/*/Tests/`.
- Modify: `LICENSE-EXCEPTION.md` "Source file notice" section if it counts files.

**Interfaces:** none.

- [ ] **Step 1: Add the line as line 1 of each file that lacks it**

```bash
cd /Users/bain/git/Nook
LINE='// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.'
find App CommandPalette Navigation Nook Onboarding Settings UI Packages -name '*.swift' \
  -not -path 'Nook/ThirdParty/*' -not -path '*/.build/*' -print0 \
| while IFS= read -r -d '' f; do
    head -1 "$f" | grep -qF "$LINE" && continue
    printf '%s\n' "$LINE" | cat - "$f" > "$f.tmp" && mv "$f.tmp" "$f"
  done
echo "with pointer: $(grep -rlF "$LINE" --include='*.swift' App CommandPalette Navigation Nook Onboarding Settings UI Packages | grep -v ThirdParty | grep -v '/.build/' | wc -l)"
echo "without:      $(find App CommandPalette Navigation Nook Onboarding Settings UI Packages -name '*.swift' -not -path 'Nook/ThirdParty/*' -not -path '*/.build/*' | xargs grep -LF "$LINE" | wc -l)"
```
Expected: `without: 0`.

- [ ] **Step 2: Build macOS and the NookTabsCore tests**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -2
(cd Packages/NookTabsCore && swift test 2>&1 | tail -1)
```
Expected: `** BUILD SUCCEEDED **` and the test summary line with 0 failures.

- [ ] **Step 3: Commit**

```bash
git add -A App CommandPalette Navigation Nook Onboarding Settings UI Packages LICENSE-EXCEPTION.md
git commit -m "chore: license pointer in every Swift file"
```

---

### Task 2: iOS slices of the adblock-rust binary

**Files:**
- Modify: `Nook/ThirdParty/AdblockRustFFI/build.sh`
- Modify (generated): `Nook/ThirdParty/AdblockRustFFI/NookAdblock.xcframework/` (gains `ios-arm64/` and `ios-arm64-simulator/`, plus the `Info.plist`)

**Interfaces:**
- Produces: the `NookAdblockFFI` binary target resolves for `iphoneos` and `iphonesimulator`, so `NookBlocker` links on iOS.

- [ ] **Step 1: Install the Rust targets**

```bash
export PATH="$HOME/.cargo/bin:$PATH"
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
rustup target list --installed | tr '\n' ' '
```
Expected: `aarch64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim`.

- [ ] **Step 2: Extend the build script**

Replace the body of `build.sh` after `cargo test --release` with:

```sh
cargo build --release --target aarch64-apple-darwin
cargo build --release --target aarch64-apple-ios
cargo build --release --target aarch64-apple-ios-sim
rm -rf NookAdblock.xcframework
xcodebuild -create-xcframework \
  -library "$CARGO_TARGET_DIR/aarch64-apple-darwin/release/libnook_adblock.a" -headers include \
  -library "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libnook_adblock.a" -headers include \
  -library "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/libnook_adblock.a" -headers include \
  -output NookAdblock.xcframework
ls NookAdblock.xcframework
```

and delete the two-line "iOS slices (phase 3)" comment. Update the header comment to say "for macOS arm64, iOS arm64 and the iOS simulator".

- [ ] **Step 3: Build**

```bash
cd /Users/bain/git/Nook/Nook/ThirdParty/AdblockRustFFI && ./build.sh 2>&1 | tail -4
plutil -p NookAdblock.xcframework/Info.plist | grep -E 'LibraryIdentifier|SupportedPlatform"' | tr -d ' '
du -sh NookAdblock.xcframework
```
Expected: `cargo test` passes (the `no_overbroad_rules` test among them), the plist lists `macos-arm64`, `ios-arm64`, `ios-arm64-simulator`, and the size is roughly three times the old 8.8 MB.

- [ ] **Step 4: macOS still builds, NookBlocker builds for the simulator**

```bash
cd /Users/bain/git/Nook
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -2
(cd Packages/NookBlocker && xcodebuild -scheme NookBlocker -destination 'generic/platform=iOS Simulator' -derivedDataPath /Users/bain/git/Nook/build-ios build 2>&1 | grep -E 'error:|BUILD' | sort -u | head -10)
```
Expected: both `** BUILD SUCCEEDED **`. If NookBlocker reports Swift errors (not link errors), they belong to Task 3; note them and continue.

- [ ] **Step 5: Commit**

```bash
git add Nook/ThirdParty/AdblockRustFFI/build.sh Nook/ThirdParty/AdblockRustFFI/NookAdblock.xcframework
git commit -m "build: iOS and simulator slices of the adblock-rust binary"
```

---

### Task 3: The four remaining packages build for the iOS simulator

**Files:**
- Modify, as the compiler dictates, only: `Packages/NookWeb/Sources/NookWeb/Platform.swift`, `Packages/NookUI/Sources/NookUI/HoverTracking.swift`, `Packages/NookUI/Sources/NookUI/Haptics.swift`, `Packages/NookDesign/Sources/NookDesign/NookDesign.swift`, and new `+iOS.swift` / `+macOS.swift` siblings for any file that needs more than one conditional. Expected candidates: `PageSession+UIDelegate.swift` (`runOpenPanelWith` is a macOS-only `WKUIDelegate` method), `SpaceRecord+UI.swift`, `BrowserWindowState.swift`'s `WindowHandle` conformers, any `Color(nsColor:)` or `NSImage` reach that slipped past `canImport`.

**Interfaces:**
- Produces: `NookBlocker`, `NookTweaks`, `NookWeb`, `NookUI` each build with `-destination 'generic/platform=iOS Simulator'`. Public API unchanged for macOS.

- [ ] **Step 1: Build each package in dependency order and collect errors**

```bash
cd /Users/bain/git/Nook
for p in NookBlocker NookTweaks NookWeb NookUI; do
  echo "== $p"
  (cd Packages/$p && xcodebuild -scheme $p -destination 'generic/platform=iOS Simulator' -derivedDataPath /Users/bain/git/Nook/build-ios build 2>&1 | grep -E 'error:' | sort -u | head -30)
done
```

- [ ] **Step 2: Fix each error in the wrapper file that owns the difference**

Rules for the fix, in order of preference:
1. A missing cross-platform spelling (`Color(nsColor:)`, `NSImage`, `NSColor`) becomes the `PlatformColor` / `PlatformImage` / `Color(platformColor:)` spelling already in `Platform.swift`.
2. A macOS-only delegate method (`runOpenPanelWith`, `NSMenu` hooks) is wrapped in `#if os(macOS)` when it is the only conditional in the file; otherwise the file is split into `+macOS.swift` and `+iOS.swift` siblings with the shared part staying in the original.
3. A missing view modifier on iOS (`onHoverTracking`) gets its iOS branch in the same wrapper file, returning `self` unchanged (phones do not hover).
4. Nothing platform-specific goes into a view body or a manager.

Re-run Step 1 until all four print no errors.

- [ ] **Step 3: macOS still builds**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -2
```
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 4: Commit**

```bash
git add Packages
git commit -m "packages: build for iOS"
```

---

### Task 4: The NookiOS target in Nook.xcodeproj

**Files:**
- Modify: `Nook.xcodeproj/project.pbxproj` (new target, group, phases, configurations, package product dependencies)
- Create: `Nook.xcodeproj/xcshareddata/xcschemes/NookiOS.xcscheme`
- Create: `NookiOS/Info.plist`
- Create: `NookiOS/NookiOS.entitlements` (empty dict; the web-browser entitlement is added when Apple grants it)

**Interfaces:**
- Produces: `xcodebuild -list` shows targets `Nook` and `NookiOS` and scheme `NookiOS`. The target compiles everything under `NookiOS/` (a filesystem-synchronized root group) and links the seven local package products.

The project uses object version 77 with filesystem-synchronized groups; the macOS target is `7F8340FB2E37F39400674A5D`. New objects use the fixed id prefix `10500000000000000000XXXX` so they are recognisable in diffs.

- [ ] **Step 1: Info.plist and entitlements**

`NookiOS/Info.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleURLTypes</key>
	<array>
		<dict>
			<key>CFBundleTypeRole</key>
			<string>Viewer</string>
			<key>CFBundleURLName</key>
			<string>Web Site URL</string>
			<key>CFBundleURLSchemes</key>
			<array>
				<string>http</string>
				<string>https</string>
			</array>
		</dict>
	</array>
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoadsInWebContent</key>
		<true/>
	</dict>
	<key>UIApplicationSceneManifest</key>
	<dict>
		<key>UIApplicationSupportsMultipleScenes</key>
		<false/>
	</dict>
	<key>UILaunchScreen</key>
	<dict/>
	<key>UISupportedInterfaceOrientations</key>
	<array>
		<string>UIInterfaceOrientationPortrait</string>
		<string>UIInterfaceOrientationLandscapeLeft</string>
		<string>UIInterfaceOrientationLandscapeRight</string>
	</array>
</dict>
</plist>
```

`NookiOS/NookiOS.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
```

- [ ] **Step 2: Add the target with a script**

Save as `scripts/add-ios-target.py` (kept in the repo so the edit is reproducible), run once, then keep the resulting `project.pbxproj`:

```python
#!/usr/bin/env python3
"""Adds the NookiOS app target to Nook.xcodeproj. Idempotent: exits if the target exists."""
import re, sys, pathlib

P = pathlib.Path(__file__).resolve().parent.parent / "Nook.xcodeproj/project.pbxproj"
s = P.read_text()
if "NookiOS" in s:
    print("NookiOS target already present"); sys.exit(0)

def oid(n): return f"1050000000000000000{n:05d}"

TARGET, GROUP, SOURCES, FRAMEWORKS, RESOURCES = oid(1), oid(2), oid(3), oid(4), oid(5)
CONFLIST, DEBUG, RELEASE, PRODUCT = oid(6), oid(7), oid(8), oid(9)
PACKAGES = ["NookTabsCore", "NookSettings", "NookDesign", "NookBlocker", "NookTweaks", "NookWeb", "NookUI"]
dep_ids = {p: oid(100 + i) for i, p in enumerate(PACKAGES)}       # XCSwiftPackageProductDependency
file_ids = {p: oid(200 + i) for i, p in enumerate(PACKAGES)}      # PBXBuildFile

def insert_before(marker, text):
    global s
    assert s.count(marker) == 1, marker
    s = s.replace(marker, text + marker)

# PBXBuildFile entries for the package products
insert_before("/* End PBXBuildFile section */", "".join(
    f"\t\t{file_ids[p]} /* {p} in Frameworks */ = {{isa = PBXBuildFile; productRef = {dep_ids[p]} /* {p} */; }};\n"
    for p in PACKAGES))

# Product file reference
insert_before("/* End PBXFileReference section */",
    f"\t\t{PRODUCT} /* NookiOS.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = NookiOS.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n")

# Synchronized root group for NookiOS/
insert_before("/* End PBXFileSystemSynchronizedRootGroup section */",
    f"\t\t{GROUP} /* NookiOS */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = NookiOS;\n\t\t\tsourceTree = \"<group>\";\n\t\t}};\n")

# Build phases
insert_before("/* End PBXFrameworksBuildPhase section */",
    f"\t\t{FRAMEWORKS} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n"
    + "".join(f"\t\t\t\t{file_ids[p]} /* {p} in Frameworks */,\n" for p in PACKAGES)
    + "\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t};\n")
insert_before("/* End PBXSourcesBuildPhase section */",
    f"\t\t{SOURCES} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")
insert_before("/* End PBXResourcesBuildPhase section */",
    f"\t\t{RESOURCES} /* Resources */ = {{\n\t\t\tisa = PBXResourcesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};\n")

# Native target
insert_before("/* End PBXNativeTarget section */", f"""\t\t{TARGET} /* NookiOS */ = {{
\t\t\tisa = PBXNativeTarget;
\t\t\tbuildConfigurationList = {CONFLIST} /* Build configuration list for PBXNativeTarget "NookiOS" */;
\t\t\tbuildPhases = (
\t\t\t\t{SOURCES} /* Sources */,
\t\t\t\t{FRAMEWORKS} /* Frameworks */,
\t\t\t\t{RESOURCES} /* Resources */,
\t\t\t);
\t\t\tbuildRules = (
\t\t\t);
\t\t\tdependencies = (
\t\t\t);
\t\t\tfileSystemSynchronizedGroups = (
\t\t\t\t{GROUP} /* NookiOS */,
\t\t\t);
\t\t\tname = NookiOS;
\t\t\tpackageProductDependencies = (
""" + "".join(f"\t\t\t\t{dep_ids[p]} /* {p} */,\n" for p in PACKAGES) + f"""\t\t\t);
\t\t\tproductName = NookiOS;
\t\t\tproductReference = {PRODUCT} /* NookiOS.app */;
\t\t\tproductType = "com.apple.product-type.application";
\t\t}};
""")

# Register the target and the group with the project
s = s.replace("\t\t\ttargets = (\n\t\t\t\t7F8340FB2E37F39400674A5D /* Nook */,\n",
              f"\t\t\ttargets = (\n\t\t\t\t7F8340FB2E37F39400674A5D /* Nook */,\n\t\t\t\t{TARGET} /* NookiOS */,\n", 1)
assert TARGET in s
m = re.search(r"(\t\t7F8340F32E37F39400674A5D = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)", s)
assert m, "main group"
s = s[:m.end()] + f"\t\t\t\t{GROUP} /* NookiOS */,\n" + s[m.end():]
m = re.search(r"(\t\t7F8340FD2E37F39400674A5D /\* Products \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n)", s)
assert m, "products group"
s = s[:m.end()] + f"\t\t\t\t{PRODUCT} /* NookiOS.app */,\n" + s[m.end():]

# Package product dependencies (local packages: no package reference needed)
insert_before("/* End XCSwiftPackageProductDependency section */", "".join(
    f"\t\t{dep_ids[p]} /* {p} */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tproductName = {p};\n\t\t}};\n"
    for p in PACKAGES))

# Build configurations
def config(oid_, name, extra):
    return f"""\t\t{oid_} /* {name} */ = {{
\t\t\tisa = XCBuildConfiguration;
\t\t\tbuildSettings = {{
\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
\t\t\t\tCODE_SIGN_ENTITLEMENTS = NookiOS/NookiOS.entitlements;
\t\t\t\tCODE_SIGN_STYLE = Automatic;
\t\t\t\tCURRENT_PROJECT_VERSION = 1;
\t\t\t\tDEVELOPMENT_TEAM = ZHB786H6YN;
\t\t\t\tGENERATE_INFOPLIST_FILE = YES;
\t\t\t\tINFOPLIST_FILE = NookiOS/Info.plist;
\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = Nook;
\t\t\t\tINFOPLIST_KEY_UIApplicationSupportsIndirectInputEvents = YES;
\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 26.0;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (
\t\t\t\t\t"$(inherited)",
\t\t\t\t\t"@executable_path/Frameworks",
\t\t\t\t);
\t\t\t\tMARKETING_VERSION = 0.1.0;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.gstudios.nook;
\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";
\t\t\t\tSDKROOT = iphoneos;
\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;
\t\t\t\tSWIFT_VERSION = 5.0;
\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";
{extra}\t\t\t}};
\t\t\tname = {name};
\t\t}};
"""
insert_before("/* End XCBuildConfiguration section */",
    config(DEBUG, "Debug", "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";\n")
    + config(RELEASE, "Release", "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n"))
insert_before("/* End XCConfigurationList section */", f"""\t\t{CONFLIST} /* Build configuration list for PBXNativeTarget "NookiOS" */ = {{
\t\t\tisa = XCConfigurationList;
\t\t\tbuildConfigurations = (
\t\t\t\t{DEBUG} /* Debug */,
\t\t\t\t{RELEASE} /* Release */,
\t\t\t);
\t\t\tdefaultConfigurationIsVisible = 0;
\t\t\tdefaultConfigurationName = Release;
\t\t}};
""")
P.write_text(s)
print("NookiOS target added")
```

The project-level configurations set `SDKROOT = macosx`; the target-level `SDKROOT = iphoneos` and `SUPPORTED_PLATFORMS` override it. Check that the `PBXGroup` for the main group and the Products group match the regexes; if the main group's children list is formatted differently, adjust the regex rather than the file.

- [ ] **Step 3: Scheme**

`Nook.xcodeproj/xcshareddata/xcschemes/NookiOS.xcscheme`: copy `Nook.xcscheme`, then replace every `BlueprintIdentifier = "7F8340FB2E37F39400674A5D"` with `"10500000000000000000001"`, every `BuildableName = "Nook.app"` with `"NookiOS.app"`, every `BlueprintName = "Nook"` with `"NookiOS"`. Leave the rest.

```bash
cd /Users/bain/git/Nook
sed -e 's/BlueprintIdentifier = "7F8340FB2E37F39400674A5D"/BlueprintIdentifier = "10500000000000000000001"/g' \
    -e 's/BuildableName = "Nook.app"/BuildableName = "NookiOS.app"/g' \
    -e 's/BlueprintName = "Nook"/BlueprintName = "NookiOS"/g' \
    Nook.xcodeproj/xcshareddata/xcschemes/Nook.xcscheme > Nook.xcodeproj/xcshareddata/xcschemes/NookiOS.xcscheme
grep -c NookiOS Nook.xcodeproj/xcshareddata/xcschemes/NookiOS.xcscheme
```

- [ ] **Step 4: Placeholder app so the target has a source, then list and build**

`NookiOS/NookiOSApp.swift` (replaced in Task 5):

```swift
// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import SwiftUI

@main
struct NookiOSApp: App {
    var body: some Scene {
        WindowGroup { Text("Nook") }
    }
}
```

```bash
python3 scripts/add-ios-target.py
xcodebuild -list -project Nook.xcodeproj 2>&1 | sed -n '/Targets/,/Schemes/p'
xcodebuild -scheme NookiOS -destination 'generic/platform=iOS Simulator' -derivedDataPath build-ios CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -3
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -1
```
Expected: targets `Nook`, `NookiOS`; both builds `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Nook.xcodeproj NookiOS scripts/add-ios-target.py
git commit -m "ios: NookiOS app target"
```

---

### Task 5: BrowserModel, the web view, and the root view

**Files:**
- Create: `NookiOS/BrowserModel.swift`
- Create: `NookiOS/BrowserModel+Seams.swift`
- Create: `NookiOS/NookWebView.swift`
- Create: `NookiOS/RootView.swift`
- Replace: `NookiOS/NookiOSApp.swift`

**Interfaces:**
- Consumes: `TabsController(settings:windowRegistry:blocker:sponsorBlock:siteRouting:)`, `tabs.attach(window:)`, `tabs.select(_:in:)`, `tabs.selectedSession(in:)`, `tabs.sessions`, `tabs.session(for:)` (both overloads), `tabs.profile(forSpace:)`, `tabs.window(for:)`, `tabs.open(url:in:placement:parent:)`, `tabs.orderedSpaces`, `tabs.space(_:)`; `PageSession.navigate(to:)`, `.activeWebView`, `.webView`, `.isPrivate`; `ContentBlockerManager(settings:)`, `.attach(host:)`, `.setEnabled(_:)`, `.activationTask`, `.isEnabled`; `BrowserConfiguration.shared`; `SponsorBlockManager(settings:)`, `SiteRoutingManager(settings:)`, `.host`; `SocialImageTweaks.downloader`; `WindowRegistry.register/setActive`; `BrowserWindowState(id:)`, `.spaceID`, `.selectedItemID`, `.isIncognito`; the seven protocols from Task 3's packages.
- Produces: `BrowserModel` (`@MainActor final class`, `ObservableObject`), `NookWebView: WKWebView, SessionWebView`, `RootView`, `WebViewContainer`.

- [ ] **Step 1: The model**

`NookiOS/BrowserModel.swift`:

```swift
// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  BrowserModel.swift
//  NookiOS
//
//  The iOS stand-in for BrowserManager: owns the managers, one window state, and the
//  conformances the packages need (BrowserModel+Seams.swift). One scene, one WKWebView
//  per session, no extensions.
//

import Combine
import OSLog
import SwiftUI
import WebKit
import NookBlocker
import NookSettings
import NookTweaks
import NookWeb

@MainActor
final class BrowserModel: ObservableObject {
    let settings: NookSettingsService
    let windowRegistry = WindowRegistry()
    let blocker: ContentBlockerManager
    let sponsorBlock: SponsorBlockManager
    let siteRouting: SiteRoutingManager
    let tabs: TabsController
    let window = BrowserWindowState()

    /// The active space's data store; PageSession waits on the publisher when this is nil.
    @Published private(set) var currentProfileValue: Profile?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "BrowserModel")

    init() {
        let settings = NookSettingsService()
        self.settings = settings
        let blocker = ContentBlockerManager(settings: settings)
        let sponsorBlock = SponsorBlockManager(settings: settings)
        let siteRouting = SiteRoutingManager(settings: settings)
        self.blocker = blocker
        self.sponsorBlock = sponsorBlock
        self.siteRouting = siteRouting
        self.tabs = TabsController(
            settings: settings, windowRegistry: windowRegistry, blocker: blocker,
            sponsorBlock: sponsorBlock, siteRouting: siteRouting)

        tabs.webViews = self
        tabs.sessionDelegate = self
        tabs.tabEvents = nil
        tabs.alerts = self
        blocker.attach(host: self)
        siteRouting.host = self
        SocialImageTweaks.downloader = self

        windowRegistry.register(window)
        windowRegistry.setActive(window)
        tabs.attach(window: window)
        currentProfileValue = window.spaceID.flatMap { tabs.profile(forSpace: $0) }

        blocker.setEnabled(settings.blockCrossSiteTracking || settings.adBlockerEnabled)
        log.info("Model ready: \(self.tabs.orderedSpaces.count) spaces, selected \(String(describing: self.window.selectedItemID), privacy: .public)")
    }

    /// Loads the window's selected page once the blocker has had up to two seconds to activate,
    /// the same wait BrowserManager.applyStartupLoadMode makes on macOS.
    func start() async {
        if !blocker.isEnabled, let activation = blocker.activationTask {
            _ = await withTaskGroup(of: Void.self) { group in
                group.addTask { await activation.value }
                group.addTask { try? await Task.sleep(for: .seconds(2)) }
                await group.next()
                group.cancelAll()
            }
        }
        if let selected = window.selectedItemID {
            tabs.select(selected, in: window)
        }
    }

    var selectedSession: PageSession? { tabs.selectedSession(in: window) }

    func navigate(_ input: String) {
        if let session = selectedSession {
            session.navigate(to: input)
        } else if let url = URL(string: normalizeURL(input, queryTemplate: settings.resolvedSearchEngineTemplate)) {
            tabs.open(url: url, in: window, placement: .newTab)
        }
    }
}
```

`Placement` is `newTab`, `background`, `replaceCurrent` (`TabsController.swift:22`); `resolvedSearchEngineTemplate` is what `PageSession.navigate(to:)` uses.

- [ ] **Step 2: The seams**

`NookiOS/BrowserModel+Seams.swift`:

```swift
// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  BrowserModel+Seams.swift
//  NookiOS
//
//  The package seams, phone edition: one web view per session, no windows to cross, no Peek,
//  PiP, zoom, shortcuts, extensions or Chrome Web Store. Alerts are UIAlertControllers.
//

import Combine
import UIKit
import WebKit
import NookBlocker
import NookTweaks
import NookWeb

// MARK: - ContentBlockerHost

extension BrowserModel: ContentBlockerHost {
    var blockablePages: [any BlockablePage] { tabs.sessions }
    func blockablePage(for webView: WKWebView) -> (any BlockablePage)? { tabs.session(for: webView) }
    var sharedUserContentController: WKUserContentController {
        BrowserConfiguration.shared.webViewConfiguration.userContentController
    }
    func onNewUserContentController(_ handler: @escaping @MainActor (WKUserContentController) -> Void) {
        BrowserConfiguration.shared.contentRuleListApplicator = { controller in
            MainActor.assumeIsolated { handler(controller) }
        }
    }
}

// MARK: - SiteRoutingHost, MediaDownloading

extension BrowserModel: SiteRoutingHost {
    func route(url: URL, toSpace spaceID: UUID, from page: AnyObject?) -> Bool {
        guard (page as? PageSession)?.isPrivate != true, tabs.space(spaceID) != nil,
              window.spaceID != spaceID else { return false }
        Task { @MainActor [tabs, window] in
            tabs.open(url: url, in: window, placement: .newTab, parent: .tabs(spaceID: spaceID))
        }
        return true
    }
    func liveSpaceIDs() -> Set<UUID> { Set(tabs.orderedSpaces.map(\.id)) }
}

extension BrowserModel: MediaDownloading {
    // ponytail: saving to Photos or Files is chrome work in the second plan.
    func downloadImage(at url: URL, from webView: WKWebView) {}
}

// MARK: - WebViewProvider

extension BrowserModel: WebViewProvider {
    func makeWebView(configuration: WKWebViewConfiguration) -> WKWebView {
        NookWebView(frame: .zero, configuration: configuration)
    }
    func webView(for itemID: UUID, in windowID: UUID) -> WKWebView? { tabs.session(for: itemID)?.webView }
    func allWebViews(for itemID: UUID) -> [WKWebView] { tabs.session(for: itemID)?.webView.map { [$0] } ?? [] }
    func releaseWebViews(for session: PageSession) { session.webView?.removeFromSuperview() }
    func removeFromContainers(_ webView: WKWebView) { webView.removeFromSuperview() }
}

// MARK: - PageSessionDelegate

extension BrowserModel: PageSessionDelegate {
    var currentProfile: Profile? { currentProfileValue }
    var currentProfilePublisher: AnyPublisher<Profile?, Never> { $currentProfileValue.eraseToAnyPublisher() }
    func navigateAcrossWindows(_ itemID: UUID, to url: URL) {}
    func windowSpaceChanged(_ window: BrowserWindowState) {
        currentProfileValue = window.spaceID.flatMap { tabs.profile(forSpace: $0) }
    }
    func addDownload(_ download: WKDownload, originalURL: URL, suggestedFilename: String) {
        download.cancel()   // ponytail: downloads land in the second plan
    }
    func toggleFullScreen(for webView: WKWebView) -> Bool { false }
    func presentPeek(url: URL, from session: PageSession) { session.navigate(to: url.absoluteString) }
    func presentSignInWindow(url: URL, completion: @escaping (Bool) -> Void) { completion(false) }
    func handleAuthenticationChallenge(
        _ challenge: URLAuthenticationChallenge, for session: PageSession,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) -> Bool { false }
    func beginIdentityFlow(_ request: IdentityRequest, from session: PageSession) {}
    func loadZoom(for itemID: UUID) {}
    func cleanupZoom(for itemID: UUID) {}
    func setMuteState(_ muted: Bool, for itemID: UUID) {}
    func requestPictureInPicture(for session: PageSession, webView: WKWebView?) {}
    func isPictureInPictureActive(for session: PageSession) -> Bool { false }
    func configureShortcutDetection(in webView: WKWebView) {}
    func shortcutDetectorDidNavigate(to url: URL) {}
    func updateDetectedShortcuts(for url: String, shortcuts: Set<String>) {}
    func installWebStoreScript(in webView: WKWebView) -> AnyObject? { nil }
    func removeWebStoreHandler(from controller: WKUserContentController) {}
}

// MARK: - AlertPresenter

extension BrowserModel: AlertPresenter {
    private func present(_ alert: UIAlertController, over webView: WKWebView, cancel: @escaping () -> Void) {
        guard let root = webView.window?.rootViewController else { return cancel() }
        var top = root
        while let next = top.presentedViewController { top = next }
        top.present(alert, animated: true)
    }
    func presentAlert(message: String, over webView: WKWebView, completion: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion() })
        present(alert, over: webView, cancel: completion)
    }
    func presentConfirm(message: String, over webView: WKWebView, completion: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(false) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completion(true) })
        present(alert, over: webView) { completion(false) }
    }
    func presentPrompt(prompt: String, defaultText: String?, over webView: WKWebView, completion: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completion(nil) })
        alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in completion(alert?.textFields?.first?.text) })
        present(alert, over: webView) { completion(nil) }
    }
    func presentOpenPanel(allowsMultipleSelection: Bool, allowsDirectories: Bool, over webView: WKWebView, completion: @escaping ([URL]?) -> Void) {
        completion(nil)   // ponytail: UIDocumentPickerViewController comes with downloads
    }
}
```

If the `PageSession+UIDelegate.swift` split in Task 3 removed `presentOpenPanel` from the iOS side of `AlertPresenter`, drop that method here too; the protocol is what the package says it is.

- [ ] **Step 3: The web view and the root view**

`NookiOS/NookWebView.swift`:

```swift
// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import WebKit
import NookWeb

/// The session's view on iOS. FocusableWKWebView's job on macOS is focus and the context menu;
/// neither exists here, so this only carries the back-reference the package expects.
@MainActor
final class NookWebView: WKWebView, SessionWebView {
    weak var owningSession: PageSession?
    var contextMenuBridge: WebContextMenuBridge?
    func contextMenuPayloadDidUpdate(_ payload: WebContextMenuPayload?) {}
}
```

`NookiOS/RootView.swift`:

```swift
// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import SwiftUI
import WebKit
import NookDesign
import NookWeb

struct RootView: View {
    @EnvironmentObject private var model: BrowserModel
    @State private var address = ""

    var body: some View {
        VStack(spacing: 0) {
            if let session = model.selectedSession {
                WebViewContainer(webView: session.activeWebView)
            } else {
                Color.clear
            }
            TextField("Search or enter address", text: $address)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { model.navigate(address) }
                .padding(NookDesign.Spacing.md)
        }
        .task { await model.start() }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    func makeUIView(context: Context) -> UIView { UIView() }
    func updateUIView(_ view: UIView, context: Context) {
        guard webView.superview !== view else { return }
        view.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)
    }
}
```

`NookiOS/NookiOSApp.swift`:

```swift
// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import SwiftUI

@main
struct NookiOSApp: App {
    @StateObject private var model = BrowserModel()

    var body: some Scene {
        WindowGroup {
            RootView().environmentObject(model)
        }
    }
}
```

- [ ] **Step 4: Build**

```bash
cd /Users/bain/git/Nook
xcodebuild -scheme NookiOS -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -derivedDataPath build-ios CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E 'error:|BUILD' | tail -5
```
Expected: `** BUILD SUCCEEDED **`. Fix compile errors against the actual package signatures; the names in this task were read from the packages on 2026-09-18 and the notes above say where to look if one moved.

- [ ] **Step 5: Commit**

```bash
git add NookiOS
git commit -m "ios: BrowserModel, seams, and a page with a URL field"
```

---

### Task 6: Gate: one page with the blocker on, in the simulator

**Files:** none.

- [ ] **Step 1: Boot, install, launch**

```bash
cd /Users/bain/git/Nook
UDID=$(xcrun simctl list devices available -j | python3 -c "import json,sys; d=json.load(sys.stdin)['devices']; print(next(x['udid'] for k in d for x in d[k] if x['name']=='iPhone 17 Pro'))")
xcrun simctl boot "$UDID" 2>/dev/null; xcrun simctl bootstatus "$UDID" -b | tail -1
APP=build-ios/Build/Products/Debug-iphonesimulator/NookiOS.app
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" com.gstudios.nook
sleep 15
xcrun simctl spawn "$UDID" log show --last 1m --info --predicate 'subsystem == "com.gstudios.nook"' --style compact 2>/dev/null | grep -E 'BrowserModel|Tabs|ContentBlocker|PageSession' | grep -v '^Timestamp' | sed 's/^[^ ]* [^ ]* [^ ]* [^ ]* //' | cut -c1-160 | head -20
xcrun simctl io "$UDID" screenshot /private/tmp/claude-501/-Users-bain-git-Nook/95344b49-e2e8-463e-a75f-635d11defbf5/scratchpad/ios-gate.png
```
Expected in the log: `Tabs loaded: firstLaunch, 1 items`, `Model ready: 1 spaces`, `Activated with N rule list(s)` (the first launch compiles from the bundled snapshots, so several seconds), and a `PageSession` line for google.com committing. The screenshot (read it with the Read tool) shows Google's page above a text field.

- [ ] **Step 2: Navigate through the field and confirm blocking**

Type into the field with the simulator's keyboard is not hands-off; instead open a URL through the app's scheme registration:

```bash
xcrun simctl openurl "$UDID" "https://www.reddit.com"
sleep 10
xcrun simctl spawn "$UDID" log show --last 30s --info --predicate 'subsystem == "com.gstudios.nook" && category == "ContentBlocker"' --style compact 2>/dev/null | grep -v '^Timestamp' | sed 's/^[^ ]* [^ ]* [^ ]* [^ ]* //' | cut -c1-160 | tail -5
```
If `openurl` does not reach the app (no `onOpenURL` handler yet), add `.onOpenURL { model.navigate($0.absoluteString) }` to `RootView` and rebuild; that handler is wanted anyway. Expected: `main frame www.reddit.com: exempt=false config=… ruleLists=N`.

- [ ] **Step 3: Record the result in the handoff and stop for review**

Append to `docs/ios-port-phase3-handoff.md` under "Where things stand": the date, the commit, the rule-list count and activation time from the simulator log, and the list of package files that needed iOS fixes in Task 3. Commit:

```bash
git add docs/ios-port-phase3-handoff.md
git commit -m "docs: milestone one reached in the simulator"
```

Then stop. The second plan (device compile spike, bottom bar, tab sheet, iPad, downloads, DevMCP on iOS) starts after this gate is reviewed.
