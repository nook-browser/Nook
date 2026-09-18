# Repo Transition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Nook 1.1.0 as `com.gstudios.nook` from the canonical `nook-browser/Nook` repo, with the 1.0.7 install base told about it through Sparkle and their data carried over on first launch.

**Architecture:** The bundle id changes in the project file and every path or logger that spelled it out now derives from `Bundle.main`. A new `@main` entry runs a one-time file and defaults copy from the previous bundle ids before SwiftUI constructs anything, and the first-launch path builds the tab tree from the old SwiftData spaces, folders and tabs instead of one tab per profile. The notarize workflow keeps emitting appcast items, each carrying an informational-update scope so Sparkle 2.8.1 in the 1.0.7 app shows a link instead of attempting an install it would reject (different Team ID).

**Tech Stack:** Swift 5, SwiftUI, SwiftData, Sparkle 2, GitHub Actions, `gh`.

**Spec:** `docs/superpowers/specs/2026-09-17-ios-port-design.md`, section "Decisions, 2026-09-18". Facts behind the decisions: `docs/ios-port-phase3-handoff.md`.

## Global Constraints

- Bundle id: `com.gstudios.nook`, App ID on team `ZHB786H6YN`.
- Canonical repo: `nook-browser/Nook`. Sparkle feed: `https://nook-browser.github.io/Nook/appcast.xml`. `SUPublicEDKey` stays `oWrc3J4HWz5PEVE5fIMKj5fEnCUwqYl0bO1li3xOYM4=`.
- Version 1.1.0, build 110 (the first release after upstream's 1.0.7). The informational scope is "below 110".
- Previous bundle ids, newest first: `com.baingurley.nook` (1.1.x to 1.2.1), `io.browsewithnook.nook` (1.0.x).
- Zero behaviour change on macOS beyond the migration. Every task ends with a Debug build. No test target exists; verification is a build plus a hands-off run (`open -g`, `log show`, never take the screen).
- Commit per task with a plain message.
- Never delete a directory without listing it first. Nothing in this plan removes user data; copies only.
- Do not launch the app between Task 1 and Task 3's verification: a launch under the new id creates a fresh store and the migration guard would then skip the copy.

---

### Task 1: Bundle id and the paths derived from it

**Files:**
- Modify: `Nook.xcodeproj/project.pbxproj:435` and `:483` (`PRODUCT_BUNDLE_IDENTIFIER`)
- Modify: `Packages/NookWeb/Sources/NookWeb/TabsController.swift:52`, `:70`, `:130`
- Modify: `Packages/NookWeb/Sources/NookWeb/PageSession.swift:26`
- Modify: `Packages/NookWeb/Sources/NookWeb/HistoryManager.swift:103`
- Modify: `Packages/NookTweaks/Sources/NookTweaks/{FacebookTweaks,SiteRoutingManager,SponsorBlockManager,YouTubeTweaks,SocialImageTweaks}.swift` (one `Logger` line each)
- Modify: `Packages/NookTabsCore/Sources/NookTabsCore/TabStore.swift:53`
- Modify: `Nook/Managers/BrowserManager/BrowserManager+Tweaks.swift:18`
- Modify: `Nook/Managers/DevMCPServer/DevMCPServer.swift:9`, `:32`, `:80`
- Modify: `Nook/Components/Settings/Tabs/AI.swift:519`
- Modify: `CLAUDE.md:14`, `:189`, `:279-282` (bundle id, storage path, log predicates, token path)

**Interfaces:**
- Produces: nothing new. `TabsController.defaultDirectory` and `DevMCPServer.loadOrCreateToken` resolve to `~/Library/Application Support/com.gstudios.nook/` at runtime.

- [x] **Step 1: Replace the literal in code**

```bash
cd /Users/bain/git/Nook
sed -i '' 's/PRODUCT_BUNDLE_IDENTIFIER = com\.baingurley\.nook;/PRODUCT_BUNDLE_IDENTIFIER = com.gstudios.nook;/' Nook.xcodeproj/project.pbxproj
# Loggers and directories derive from the bundle, as the rest of the app already does.
grep -rl 'Logger(subsystem: "com.baingurley.nook"' Packages Nook | xargs sed -i '' 's/Logger(subsystem: "com\.baingurley\.nook"/Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook"/'
sed -i '' 's/\.appendingPathComponent("com\.baingurley\.nook", isDirectory: true)/.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Nook", isDirectory: true)/' Packages/NookWeb/Sources/NookWeb/TabsController.swift Nook/Managers/DevMCPServer/DevMCPServer.swift
# Queue labels and user-facing text name the new id outright.
sed -i '' 's/com\.baingurley\.nook/com.gstudios.nook/g' Packages/NookTabsCore/Sources/NookTabsCore/TabStore.swift Nook/Managers/DevMCPServer/DevMCPServer.swift Nook/Components/Settings/Tabs/AI.swift
grep -rn 'com\.baingurley\.nook' Nook.xcodeproj Nook App Packages/*/Sources Settings
```
Expected: the final grep prints nothing.

- [x] **Step 2: Update CLAUDE.md**

Replace every `com.baingurley.nook` in `CLAUDE.md` with `com.gstudios.nook`:
```bash
sed -i '' 's/com\.baingurley\.nook/com.gstudios.nook/g' CLAUDE.md
grep -c 'com.gstudios.nook' CLAUDE.md
```
Expected: 6 or more.

- [x] **Step 3: Build**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3
/usr/libexec/PlistBuddy -c 'Print CFBundleIdentifier' build/Build/Products/Debug/Nook.app/Contents/Info.plist
```
Expected: `** BUILD SUCCEEDED **` and `com.gstudios.nook`. Do not launch.

- [x] **Step 4: Commit**

```bash
git add Nook.xcodeproj/project.pbxproj Packages Nook CLAUDE.md
git commit -m "chore: bundle id com.gstudios.nook, derive paths and loggers from the bundle"
```

---

### Task 2: Feed URL, appcast bridge item, repo links

**Files:**
- Modify: `Nook/Info.plist:56` (`SUFeedURL`)
- Modify: `.github/workflows/macos-notarize.yml:181-194` (the appcast `ENTRY`)
- Modify: `README.md:16`, `:57`; `CONTRIBUTING.md:19`; `TRADEMARK.md:35`; `LICENSE-EXCEPTION.md:14`; `CLAUDE.md:9` (fork status paragraph), `CLAUDE.md` Info.plist line

**Interfaces:**
- Produces: every future appcast item has the shape Sparkle 2.8.1 reads as informational for hosts below build 110 (`SUAppcast.m` parses `sparkle:informationalUpdate` with `sparkle:belowVersion` children into a `<110` entry; `SPUAppcastItemStateResolver` compares the host's `CFBundleVersion` against it). The `<link>` element is the item's `infoURL`, which the "Learn More" button opens.

- [x] **Step 1: Feed URL and links**

```bash
sed -i '' 's#https://l984-451.github.io/Nook/appcast.xml#https://nook-browser.github.io/Nook/appcast.xml#' Nook/Info.plist CLAUDE.md
sed -i '' 's#github.com/l984-451/Nook#github.com/nook-browser/Nook#g' README.md CONTRIBUTING.md TRADEMARK.md LICENSE-EXCEPTION.md
grep -rn 'l984-451' README.md CONTRIBUTING.md TRADEMARK.md LICENSE-EXCEPTION.md Nook/Info.plist
```
Expected: nothing.

- [x] **Step 2: Fork status paragraph in CLAUDE.md**

Replace the paragraph starting `**Fork status**:` with:

```markdown
**Repo status**: `nook-browser/Nook` is the canonical repo and `origin`; Bain Gurley is the maintainer since September 2026. The project ran as the fork `l984-451/Nook` from March to September 2026 and that fork is archived. The 24 upstream commits from March 2026 that the fork never took (sidebar animation work) were superseded by the September remodel. Treat this repo as the only source of truth.
```

- [x] **Step 3: Appcast entry in the workflow**

In `.github/workflows/macos-notarize.yml`, change the `ENTRY` heredoc so the item reads:

```xml
            <item>
              <title>Version ${SHORT_VERSION}</title>
              <link>https://github.com/${{ github.repository }}/releases/tag/${VERSION}</link>
              <sparkle:releaseNotesLink>https://github.com/${{ github.repository }}/releases/tag/${VERSION}</sparkle:releaseNotesLink>
              <sparkle:informationalUpdate>
                <sparkle:belowVersion>110</sparkle:belowVersion>
              </sparkle:informationalUpdate>
              <pubDate>${DATE}</pubDate>
              <enclosure
                url="${DMG_URL}"
                sparkle:version="${BUILD_NUMBER}"
                sparkle:shortVersionString="${SHORT_VERSION}"
                sparkle:edSignature="${ED_SIGNATURE}"
                length="${DMG_LENGTH}"
                type="application/octet-stream"/>
            </item>
```

Add this comment above the heredoc:

```yaml
          # Builds below 110 (the 1.0.x line, bundle id io.browsewithnook.nook, signed by another
          # team) cannot install our updates: Sparkle binds an update to the running app's Team ID.
          # The informational scope shows them a link instead. Keep it on every item.
```

- [x] **Step 4: Validate the YAML and build**

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/macos-notarize.yml')); print('yaml ok')" 2>/dev/null || ruby -ryaml -e "YAML.load_file('.github/workflows/macos-notarize.yml'); puts 'yaml ok'"
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1
/usr/libexec/PlistBuddy -c 'Print SUFeedURL' build/Build/Products/Debug/Nook.app/Contents/Info.plist
```
Expected: `yaml ok`, `** BUILD SUCCEEDED **`, the org feed URL.

- [x] **Step 5: Commit**

```bash
git add Nook/Info.plist .github/workflows/macos-notarize.yml README.md CONTRIBUTING.md TRADEMARK.md LICENSE-EXCEPTION.md CLAUDE.md
git commit -m "chore: point Sparkle and docs at nook-browser/Nook, scope appcast items for 1.0.x hosts"
```

---

### Task 3: First-launch copy of the previous bundle id's data

**Files:**
- Create: `App/LegacyDataMigration.swift`
- Create: `App/Main.swift`
- Modify: `App/NookApp.swift:27` (remove `@main`)

**Interfaces:**
- Produces: `LegacyDataMigration.migrateIfNeeded(currentBundleID:library:defaults:)`, static, synchronous, safe to call more than once. `Main.main()` is the process entry.

What is copied, from the first previous id whose Application Support holds `default.store`:

| From `~/Library/…/<old id>/` | To `~/Library/…/com.gstudios.nook/` | Holds |
|---|---|---|
| `Application Support/{default.store, -shm, -wal}` | same | history, extensions, and the legacy spaces, folders, tabs, profiles |
| `Application Support/Tabs/` | same | the JSON tab model (only `com.baingurley.nook` has one) |
| `WebKit/WebsiteDataStore/<uuid>/` | same | cookies, local storage, logins, one directory per space or profile id |
| defaults domain `<old id>` | `com.gstudios.nook` | every setting, including onboarding state |

Not copied: `ContentBlocker/` (a compile cache), `WebKit/ContentRuleLists` (recompiled), `Caches`, `HTTPStorages` (WebKit's cookies live under `WebsiteDataStore`). Keychain items use literal service names (`com.nook.basicAuth`, `com.nook.aiProvider`) and carry over on their own. Extensions live under `Application Support/Nook/Extensions`, not under the bundle id. `FileManager.copyItem` clones on APFS, so the 900 MB data store on this Mac copies in well under a second.

- [x] **Step 1: Write the migration**

`App/LegacyDataMigration.swift`:

```swift
//
//  LegacyDataMigration.swift
//  Nook
//
//  Nook shipped as io.browsewithnook.nook (1.0.x) and com.baingurley.nook (1.1 to 1.2.1) before
//  com.gstudios.nook. Application Support, WebKit's per-space data stores and UserDefaults are all
//  keyed by bundle id, so the first launch under the new id copies them across. Runs before
//  SwiftUI constructs anything, from Main.swift.
//

import Foundation
import OSLog

enum LegacyDataMigration {
    /// Newest first: anyone with both ran the fork after the original.
    static let previousBundleIDs = ["com.baingurley.nook", "io.browsewithnook.nook"]

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "Migration")

    static func migrateIfNeeded(
        currentBundleID: String = Bundle.main.bundleIdentifier ?? "Nook",
        library: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0],
        defaults: UserDefaults = .standard
    ) {
        let fm = FileManager.default
        let appSupport = library.appendingPathComponent("Application Support", isDirectory: true)
        let webKit = library.appendingPathComponent("WebKit", isDirectory: true)
        let target = appSupport.appendingPathComponent(currentBundleID, isDirectory: true)

        // Anything already under the new id means this ran, or the user started fresh here.
        guard !fm.fileExists(atPath: target.appendingPathComponent("default.store").path),
              !fm.fileExists(atPath: target.appendingPathComponent("Tabs").path)
        else { return }
        guard let old = previousBundleIDs.first(where: {
            fm.fileExists(atPath: appSupport.appendingPathComponent($0).appendingPathComponent("default.store").path)
        }) else { return }

        log.notice("Migrating data from \(old, privacy: .public) to \(currentBundleID, privacy: .public)")
        let source = appSupport.appendingPathComponent(old, isDirectory: true)
        for name in ["default.store", "default.store-shm", "default.store-wal", "Tabs"] {
            copy(source.appendingPathComponent(name), to: target.appendingPathComponent(name))
        }
        copy(webKit.appendingPathComponent(old).appendingPathComponent("WebsiteDataStore"),
             to: webKit.appendingPathComponent(currentBundleID).appendingPathComponent("WebsiteDataStore"))

        if let domain = defaults.persistentDomain(forName: old) {
            for (key, value) in domain where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            log.notice("Copied \(domain.count) defaults from \(old, privacy: .public)")
        }
    }

    private static func copy(_ from: URL, to: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { return }
        do {
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: from, to: to)
            log.notice("Copied \(from.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Copy of \(from.path, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }
}
```

- [x] **Step 2: Run it before SwiftUI**

`NookApp`'s stored properties (`WebViewCoordinator()`, `KeyboardShortcutManager()`, `MCPManager()`, `TabOrganizerManager()`) are initialised before `init()`'s body runs, and some read defaults or Application Support. A separate entry point runs first. Create `App/Main.swift`:

```swift
//
//  Main.swift
//  Nook
//
//  The process entry. The bundle-id migration must finish before NookApp's stored properties are
//  built, since those already read UserDefaults and Application Support.
//

@main
enum Main {
    static func main() {
        LegacyDataMigration.migrateIfNeeded()
        NookApp.main()
    }
}
```

In `App/NookApp.swift`, delete the `@main` line above `struct NookApp: App {`. `NookApp.main()` then resolves to SwiftUI's default. The `@NSApplicationDelegateAdaptor` stays where it is (only `NookApp` declares one).

- [x] **Step 3: Build**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1
```
Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 4: Verify on this Mac against real data**

This Mac holds `com.baingurley.nook` data (current) and `io.browsewithnook.nook` data (March 2026). First confirm nothing exists under the new id yet, then launch in the background and read the log.

```bash
ls ~/Library/Application\ Support/com.gstudios.nook ~/Library/WebKit/com.gstudios.nook 2>&1 | head -3
defaults read com.gstudios.nook 2>&1 | head -1
```
Expected: "No such file or directory" for both directories and "does not exist" for the domain. If anything exists, stop and report; do not delete.

```bash
open -g build/Build/Products/Debug/Nook.app; sleep 8
/usr/bin/log show --last 1m --predicate 'subsystem == "com.gstudios.nook" && (category == "Migration" || category == "Tabs" || category == "Persistence")' --style compact | grep -v '^Timestamp'
osascript -e 'quit app "Nook"'
ls ~/Library/Application\ Support/com.gstudios.nook ~/Library/WebKit/com.gstudios.nook/WebsiteDataStore
diff <(ls ~/Library/WebKit/com.baingurley.nook/WebsiteDataStore) <(ls ~/Library/WebKit/com.gstudios.nook/WebsiteDataStore) && echo "data stores match"
defaults read com.gstudios.nook settings.didFinishOnboarding
```
Expected: log lines `Migrating data from com.baingurley.nook to com.gstudios.nook`, four `Copied …` lines (store, shm, wal, Tabs) plus `Copied WebsiteDataStore`, `Copied N defaults`, `SwiftData container initialized successfully`, and `Tabs loaded: loaded, N items` with the same N the last `com.baingurley.nook` run logged. `data stores match`. Onboarding reads `1`.

- [x] **Step 5: Commit**

```bash
git add App/LegacyDataMigration.swift App/Main.swift App/NookApp.swift
git commit -m "feat: copy the previous bundle id's data on first launch"
```

---

### Task 4: Import the 1.0.x spaces, folders and tabs on first launch

The copied `default.store` from a 1.0.x install has no `Tabs/` JSON. Today's first-launch path seeds one space per `ProfileEntity` with one Google tab each, which keeps logins and loses every tab. This task builds the tree from `SpaceEntity`, `FolderEntity` and `TabEntity` instead. This is a deviation from the spec's "runs the existing first-launch path" sentence, made because that path drops the user's tabs.

Mapping, in the old model's terms: `isPinned` was the global "essentials" row, per profile, and becomes the favorites of that profile's first space. `isSpacePinned` becomes the space's pinned section. `FolderEntity.isRegular` folders sat in the tabs section; the others in the pinned section. A profile's first space takes the profile's id so `WKWebsiteDataStore(forIdentifier:)` finds its cookies, the rule `ProfileMerge` already applies to formatVersion 1 files. Spaces with no profile belong to the first profile.

**Files:**
- Create: `Nook/Models/Legacy/LegacyTabImport.swift`
- Modify: `Packages/NookWeb/Sources/NookWeb/TabsController.swift:76-104` (init gains `legacyTree`)
- Modify: `Nook/Managers/BrowserManager/BrowserManager.swift:438-441` (passes it)

**Interfaces:**
- Consumes: `TabTree.createSpace(id:name:icon:accentHex:after:now:)`, `createFolder(id:title:in:after:now:) throws`, `createTab(id:url:title:in:after:now:) throws`, `rename(_:customTitle:now:) throws`, `children(of:)`, `orderedSpaces`, `items` from `NookTabsCore`; `SpaceGradient.decode(_:).primaryColorHex` from `Nook/Models/Space/SpaceGradient.swift`.
- Produces: `LegacyTabImport.tree(from: ModelContext, now: Date) -> TabTree?` (nil when the store has no spaces or nothing imports). `TabsController.init(..., legacyTree: () -> TabTree? = { nil }, ...)`, called only when the load outcome is `.firstLaunch`.

- [x] **Step 1: Write the importer**

`Nook/Models/Legacy/LegacyTabImport.swift`:

```swift
//
//  LegacyTabImport.swift
//  Nook
//
//  Builds the first tab tree from a 1.0.x SwiftData store so a user arriving from an old bundle
//  id keeps their spaces, folders and tabs, not only their cookies. Profiles map as ProfileMerge
//  maps them: a profile's first space takes the profile's id so its data store follows it.
//

import Foundation
import SwiftData
import NookTabsCore

enum LegacyTabImport {
    static func tree(from context: ModelContext, now: Date = Date()) -> TabTree? {
        let spaces = (try? context.fetch(FetchDescriptor<SpaceEntity>(sortBy: [SortDescriptor(\.index)]))) ?? []
        guard !spaces.isEmpty else { return nil }
        let profiles = (try? context.fetch(FetchDescriptor<ProfileEntity>(sortBy: [SortDescriptor(\.index)]))) ?? []
        let folders = (try? context.fetch(FetchDescriptor<FolderEntity>(sortBy: [SortDescriptor(\.index)]))) ?? []
        let tabs = (try? context.fetch(FetchDescriptor<TabEntity>(sortBy: [SortDescriptor(\.index)]))) ?? []

        var tree = TabTree()
        var spaceID: [UUID: UUID] = [:]            // old space id -> id in the tree
        var firstSpace: [UUID: UUID] = [:]         // profile id -> its first space in the tree
        let fallbackProfile = profiles.first?.id

        for space in spaces {
            let profile = space.profileId ?? fallbackProfile
            var id = space.id
            if let profile, firstSpace[profile] == nil {
                id = profile
                firstSpace[profile] = id
            }
            spaceID[space.id] = id
            tree.createSpace(id: id, name: space.name, icon: space.icon,
                             accentHex: SpaceGradient.decode(space.gradientData).primaryColorHex,
                             after: tree.orderedSpaces.last?.id, now: now)
        }

        var folderIDs = Set<UUID>()
        for folder in folders {
            guard let space = spaceID[folder.spaceId] else { continue }
            let parent: Parent = folder.isRegular ? .tabs(spaceID: space) : .pinned(spaceID: space)
            if (try? tree.createFolder(id: folder.id, title: folder.name, in: parent,
                                       after: tree.children(of: parent).last?.id, now: now)) != nil {
                folderIDs.insert(folder.id)
            }
        }

        for tab in tabs {
            let parent: Parent
            if let folder = tab.folderId, folderIDs.contains(folder) {
                parent = .folder(itemID: folder)
            } else if tab.isPinned {
                guard let space = (tab.profileId ?? fallbackProfile).flatMap({ firstSpace[$0] })
                        ?? tree.orderedSpaces.first?.id else { continue }
                parent = .favorites(spaceID: space)
            } else if let space = tab.spaceId.flatMap({ spaceID[$0] }) {
                parent = tab.isSpacePinned ? .pinned(spaceID: space) : .tabs(spaceID: space)
            } else {
                continue
            }
            let synced = tab.isPinned || tab.isSpacePinned
            let urlString = synced ? (tab.pinnedURLString ?? tab.urlString) : (tab.currentURLString ?? tab.urlString)
            guard let url = URL(string: urlString) else { continue }
            guard (try? tree.createTab(id: tab.id, url: url, title: tab.name, in: parent,
                                       after: tree.children(of: parent).last?.id, now: now)) != nil else { continue }
            if let custom = tab.displayNameOverride, !custom.isEmpty {
                _ = try? tree.rename(tab.id, customTitle: custom, now: now)
            }
        }
        return tree.items.isEmpty ? nil : tree
    }
}
```

- [x] **Step 2: Let TabsController take it**

In `Packages/NookWeb/Sources/NookWeb/TabsController.swift`, add the parameter after `legacyProfiles`:

```swift
        legacyProfiles: [(id: UUID, name: String)] = [],
        /// A tree built from a pre-1.1 store; asked for only on a first launch.
        legacyTree: () -> TabTree? = { nil },
        directory: URL = TabsController.defaultDirectory
```

and change the first-launch branch:

```swift
        case .firstLaunch, .readOnly:
            // Read-only still needs a working sidebar; the store writes nothing this session.
            if case .firstLaunch = loaded.outcome, let imported = legacyTree() {
                tree = imported
                log.info("Imported \(imported.orderedSpaces.count) spaces and \(imported.items.count) items from the legacy store")
            } else {
                tree = Self.seed(from: legacyProfiles)
            }
            device = DeviceState()
            device.firstLaunchCompleted = true
```

In `Nook/Managers/BrowserManager/BrowserManager.swift`, the `TabsController(` call gains one argument after `legacyProfiles:`:

```swift
            legacyProfiles: Self.legacyProfileRecords(in: modelContext),
            legacyTree: { [modelContext] in LegacyTabImport.tree(from: modelContext) })
```

- [x] **Step 3: Build**

```bash
xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1
```
Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 4: Verify against the March 2026 store in a staged home**

The real home already migrated in Task 3 from `com.baingurley.nook`, so the 1.0.x path runs in a scratch `HOME` holding a copy of the `io.browsewithnook.nook` Application Support folder (31 MB). `NSHomeDirectory()` honours `HOME`, so file paths land in the staged tree; defaults still go to the real cfprefsd and are not checked here.

```bash
STAGE=/private/tmp/claude-501/-Users-bain-git-Nook/95344b49-e2e8-463e-a75f-635d11defbf5/scratchpad/home
mkdir -p "$STAGE/Library/Application Support" "$STAGE/Library/WebKit"
cp -R ~/Library/Application\ Support/io.browsewithnook.nook "$STAGE/Library/Application Support/"
sqlite3 -readonly "$STAGE/Library/Application Support/io.browsewithnook.nook/default.store" \
  "select (select count(*) from ZSPACEENTITY), (select count(*) from ZFOLDERENTITY), (select count(*) from ZTABENTITY)"
HOME="$STAGE" build/Build/Products/Debug/Nook.app/Contents/MacOS/Nook >/dev/null 2>&1 &
sleep 10
/usr/bin/log show --last 1m --predicate 'subsystem == "com.gstudios.nook" && (category == "Migration" || category == "Tabs" || category == "Persistence")' --style compact | grep -v '^Timestamp'
osascript -e 'quit app "Nook"'; sleep 2
python3 -c "
import json,sys
s=json.load(open('$STAGE/Library/Application Support/com.gstudios.nook/Tabs/structure.json'))
print('spaces:', [sp['name'] for sp in s['spaces']])
"
```
Expected: the sqlite line prints the counts (on this Mac: 5 spaces, 8 folders, 43 tabs). The log shows `Migrating data from io.browsewithnook.nook`, `SwiftData container initialized successfully` (no "schema mismatch" line), `Imported 5 spaces and N items` with N near 51, and `Tabs loaded: firstLaunch, N items`. `structure.json` lists the five space names. If the log shows a schema-mismatch reset, stop: the 1.0.x store cannot be opened by the current schema and the import needs a different route; report it.

- [x] **Step 5: Commit**

```bash
git add Nook/Models/Legacy/LegacyTabImport.swift Packages/NookWeb/Sources/NookWeb/TabsController.swift Nook/Managers/BrowserManager/BrowserManager.swift
git commit -m "feat: import 1.0.x spaces, folders and tabs on the first launch after the bundle id change"
```

---

### Task 5: Release build, hands-off runtime check

**Files:** none modified.

- [x] **Step 1: Release build**

```bash
xcodebuild -scheme Nook -configuration Release -arch arm64 -derivedDataPath build-release \
  CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO 2>&1 | tail -1
```
Expected: `** BUILD SUCCEEDED **`.

- [x] **Step 2: Run it against the migrated real home**

```bash
open -g build-release/Build/Products/Release/Nook.app; sleep 10
/usr/bin/log show --last 1m --predicate 'subsystem == "com.gstudios.nook" && (category == "Tabs" || category == "ContentBlocker" || category == "Migration")' --style compact | grep -v '^Timestamp' | head -20
TOKEN=$(cat ~/Library/Application\ Support/com.gstudios.nook/dev-mcp-token 2>/dev/null)
[ -n "$TOKEN" ] && curl -s http://127.0.0.1:47823/mcp -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"blocker_status","arguments":{}}}' | head -c 400
osascript -e 'quit app "Nook"'
```
Expected: no `Migration` line (it ran in Task 3), `Tabs loaded: loaded`, the blocker reports enabled with compiled lists. The `curl` step needs Settings > AI > Browser Control on; skip it if the token file is absent and say so.

---

### Task 6: Move the repo and ship

**Files:** none in the tree. Operates on GitHub with `gh` and `git`. Steps marked **Bain** need values only Bain has.

- [x] **Step 1: Push this history to the org repo**

The org's `Main protection` ruleset blocks non-fast-forward pushes and deletions but bypasses org admins, which Bain is. The lease pins the push to the upstream head recorded on 2026-09-18.

```bash
cd /Users/bain/git/Nook
git remote add org https://github.com/nook-browser/Nook.git
git push org main:main --force-with-lease=main:e5c85a9dba76c01cbaa9dadd3e6227ac3df6693e
git push org --delete dev
gh api repos/nook-browser/Nook/commits/main --jq '.sha' ; git rev-parse HEAD
```
Expected: both SHAs equal. The push removes `.github/workflows/enforce-pr-base.yml` with the rest of the old tree.

- [ ] **Step 2 (Bain): secrets on the org repo**

The org repo holds the old team's certificate and no Sparkle key. Replace them from the same files used for the fork on 2026-09-14:

```bash
gh secret set SPARKLE_SIGNING_KEY -R nook-browser/Nook < <path to the ed25519 private key file>
gh secret set APPLE_CERTIFICATE_P12_BASE64 -R nook-browser/Nook --body "$(base64 -i <path to DeveloperID.p12>)"
gh secret set APPLE_CERTIFICATE_PASSWORD -R nook-browser/Nook
gh secret set APPLE_TEAM_ID -R nook-browser/Nook --body ZHB786H6YN
gh secret set APPLE_ID -R nook-browser/Nook
gh secret set APPLE_APP_SPECIFIC_PASSWORD -R nook-browser/Nook
gh secret list -R nook-browser/Nook
```
Expected: six secrets, all dated today.

- [ ] **Step 3: Ship**

```bash
git push org main:release
gh run watch -R nook-browser/Nook --exit-status
curl -s https://nook-browser.github.io/Nook/appcast.xml | grep -A14 'Version 1.1.0'
gh release view v1.1.0 -R nook-browser/Nook --json assets --jq '.assets[].name'
```
Expected: the run succeeds; the appcast's first item is 1.1.0 with `<link>`, the `informationalUpdate` block, and an `edSignature`; the release lists `Nook-v1.1.0.dmg`.

- [ ] **Step 4: Release notes**

```bash
gh release edit v1.1.0 -R nook-browser/Nook --notes-file - <<'EOF'
Nook has a new maintainer and a new home: this repo. The app's bundle id changed to `com.gstudios.nook`, so:

- If you are on 1.0.x, the updater cannot install this version for you. Download the DMG, replace Nook in Applications, and launch it. Your spaces, tabs, logins and settings carry over on the first launch.
- macOS will ask you to choose Nook as your default browser again.
- Updates from 1.1.0 onward install through the app as before.

Full change list since 1.0.7: ad blocking runs on adblock-rust with EasyList, EasyPrivacy and the uBlock lists; profiles are folded into spaces; a redesigned sidebar and settings; SponsorBlock, YouTube and social media tweaks; an on-device tab organizer; macOS 26 required.
EOF
```

- [ ] **Step 5: Retire the fork and repoint origin**

```bash
git remote set-url origin https://github.com/nook-browser/Nook.git
git remote remove org
git fetch origin --prune
gh repo archive l984-451/Nook --yes
git remote -v; gh repo view l984-451/Nook --json isArchived --jq '.isArchived'
```
Expected: `origin` is the org repo; the fork reports `true`.

- [ ] **Step 6 (Bain): install the released build**

Download `Nook-v1.1.0.dmg` from the release, replace `/Applications/Nook.app`, launch. This Mac's home already migrated in Task 3, so the check is that tabs, logins and settings are there and that Sparkle reports "up to date". Native dialogs, context menus and drag remain on the handoff's manual list.
