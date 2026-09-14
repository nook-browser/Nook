# GUI Remodel Phase 2: Surface and Accent

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the per-space Metal gradient with a neutral system sidebar material, reduce each space's color to a single accent, move space icons from emoji to SF Symbols, and delete the gradient editor, emoji picker, essentials size setting, and every light/dark color branch in the sidebar.

**Architecture:** `SpaceGradient` stays as the persisted type (old data keeps loading) but is only ever written as a single-node gradient from an accent hex. `GradientColorManager` keeps its name and shrinks to one published `accentColor`. The window background becomes `BlurEffectView(material: .sidebar)` behind the window. Space settings (name, icon, accent, profile) live in one dialog reached from every former gradient-editor entry point. Icons render through one `SpaceIconView`; a `SpaceIconPicker` popover replaces the emoji picker. `AppColors` loses its semantic pairs; consumers read `NookDesign.Surface` and system text colors.

**Tech Stack:** Swift 5, SwiftUI, AppKit, macOS 26 SDK. No test target; verification is grep assertions plus a Debug build.

**Spec:** `docs/superpowers/specs/2026-09-14-gui-remodel-design.md` (sections 3 and 4, plus the essentials line in section 5).

## Global Constraints

- Deployment target macOS 26.0, Apple Silicon. Never add `#available` guards below 26. Swift language mode 5.
- No test target. The build command for every verification step (zsh):
  ```bash
  cd /Users/bain/git/Nook && xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | grep -E "error:|BUILD" ; echo "exit $pipestatus[1]"
  ```
  Expected: no `error:` lines and `exit 0`. Use a 600000 ms timeout.
- Tokens: every radius, font, animation, shadow, and fill must come from `NookDesign` (`Nook/Design/NookDesign.swift`). No new literals. Text colors are `.primary`, `.secondary`, `.tertiary`.
- Materials other than the sidebar (`.headerView` in DialogManager, `.hudWindow` in SplitCardView and Onboarding) are Phase 4. Do not touch them.
- Do not edit `Onboarding/` or `Nook/ThirdParty/`.
- Xcode uses filesystem-synchronized groups: creating or `git rm`-ing a file updates the target automatically. No pbxproj edits. Deleting the Metal shader requires no build-phase edit either.
- Persisted data must keep loading: `SpaceEntity.gradientData`, `SpaceEntity.icon` (emoji strings), and user keyboard shortcut raw values are unchanged.
- Every commit message ends with the line `AI-assisted: implemented with Claude Code.`
- Do not run the app mid-task; the manual checklist runs once at the end of the phase.

---

### Task 1: Accent model and a one-color GradientColorManager

**Files:**
- Create: `Nook/Models/Space/SpaceAccent.swift`
- Modify: `Nook/Models/Space/SpaceGradient.swift:30-35` (`default`)
- Modify: `Nook/Models/Space/Space.swift` (add computed accent)
- Modify: `Nook/Managers/GradientColorManager/GradientColorManager.swift` (rewrite)
- Modify: `Nook/Managers/BrowserManager/BrowserManager.swift:455-486` (`updateGradient`, `refreshGradientsForSpace`)
- Modify: every consumer of `gradientColorManager.primaryColor` (15 sites: `CommandPalette/CommandPalette Accessories/TabSuggestionItem.swift:49`, `CommandPalette/CommandPaletteView.swift:126,372`, `Nook/Components/MiniWindow/MiniWindowToolbar.swift:98`, `Nook/Components/Sidebar/AIChat/SidebarAIChat.swift:61,479,741`, `Nook/Components/Sidebar/Menu/SidebarMenuHistoryTab.swift:55,465,625,684`, `Nook/Managers/DialogManager/DialogManager.swift:239,240,245`)

**Interfaces:**
- Produces: `enum SpaceAccent { static let presets: [(name: String, hex: String)]; static let defaultHex: String }`; `SpaceGradient.accent(hex: String) -> SpaceGradient`; `Space.accentHex: String`, `Space.accentColor: Color`; `GradientColorManager.accentColor: Color` (published, read-only), `setImmediate(_ gradient: SpaceGradient)`, `transition(to gradient: SpaceGradient)`.
- Removed: `GradientColorManager.displayGradient`, `isDark`, `isEditing`, `isAnimating`, `preferBarycentricDuringAnimation`, `activePrimaryNodeID`, `preferredPrimaryNodeID`, `beginInteractivePreview()`, `endInteractivePreview()`, `primaryColor`, and the `from:duration:animation:` parameters of `transition`. Consumers of `isDark` are fixed in Task 6; consumers of the node IDs and preview methods are deleted in Tasks 2 and 3. Until then the build is red only inside files those tasks delete, so this task's build step deletes nothing and the build will fail on `BarycentricGradientView.swift`, `GradientEditorView.swift`, `GradientCanvasEditor.swift`, `TransparencySlider.swift`, and the `isDark` consumers. **This task therefore does not build alone; its verification is Step 5's grep, and the build gate is at the end of Task 2.** The implementer commits without a build.

- [ ] **Step 1: Add the presets file**

```swift
//
//  SpaceAccent.swift
//  Nook
//
//  Preset accent colors for spaces. A space's accent is its gradient's
//  primary color; new spaces are written as a single-node gradient.
//

import Foundation

enum SpaceAccent {
    static let presets: [(name: String, hex: String)] = [
        ("Teal", "#3A8FA3"),
        ("Orange", "#D6603A"),
        ("Violet", "#6B5BD6"),
        ("Green", "#2F9E6A"),
        ("Red", "#D64545"),
        ("Blue", "#2F6FDB"),
        ("Pink", "#C94F8E"),
        ("Graphite", "#6E6E73"),
    ]

    static let defaultHex = presets[0].hex
}
```

- [ ] **Step 2: Single-node factory and new default in `SpaceGradient.swift`**

Replace the `static var default` block (lines 30-35) with:

```swift
    /// A one-color gradient. Every space written by the app after the
    /// Phase 2 remodel uses this shape; older multi-node data still decodes.
    static func accent(hex: String) -> SpaceGradient {
        SpaceGradient(angle: 0, nodes: [GradientNode(colorHex: hex, location: 0.0)], grain: 0, opacity: 1)
    }

    static var `default`: SpaceGradient {
        accent(hex: SpaceAccent.defaultHex)
    }
```

Leave `incognito` as is.

- [ ] **Step 3: Accent accessors on `Space`**

In `Nook/Models/Space/Space.swift`, after the `gradient` property (line 21), add:

```swift
    /// Hex of the space's accent color (the gradient's primary node).
    var accentHex: String { gradient.primaryColorHex }

    /// The space's accent color, used for its icon and switcher item.
    var accentColor: Color { gradient.primaryColor }
```

Add `import SwiftUI` at the top if the file only imports Foundation.

- [ ] **Step 4: Rewrite `GradientColorManager.swift`**

Replace the entire file with:

```swift
//
//  GradientColorManager.swift
//  Nook
//
//  Publishes the active space's accent color. The type name predates the
//  Phase 2 remodel; it no longer holds a gradient, only the one color
//  derived from it.
//

import SwiftUI

@MainActor
final class GradientColorManager: ObservableObject {
    @Published private(set) var accentColor: Color = SpaceGradient.default.primaryColor

    /// Set the accent with no animation (window setup, non-active windows).
    func setImmediate(_ gradient: SpaceGradient) {
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            accentColor = gradient.primaryColor
        }
    }

    /// Animate to a space's accent (active window space switch).
    func transition(to gradient: SpaceGradient) {
        withAnimation(NookDesign.Motion.standard) {
            accentColor = gradient.primaryColor
        }
    }
}
```

- [ ] **Step 5: Fix BrowserManager transition calls and rename consumers**

In `Nook/Managers/BrowserManager/BrowserManager.swift`, both occurrences of
```swift
gradientColorManager.transition(to: newGradient, duration: 0.25, animation: .easeInOut(duration: 0.25))
```
and
```swift
gradientColorManager.transition(to: space.gradient, duration: 0.25, animation: .easeInOut(duration: 0.25))
```
lose their `duration:` and `animation:` arguments. The two calls inside `showGradientEditor` (lines ~1125 and ~1139) are deleted with that method in Task 3; leave them for now.

Rename every consumer:

```bash
cd /Users/bain/git/Nook && grep -rl "gradientColorManager.primaryColor" --include='*.swift' Nook Navigation App CommandPalette UI | xargs perl -pi -e 's/gradientColorManager\.primaryColor/gradientColorManager.accentColor/g'
grep -rn "gradientColorManager.primaryColor\|\.displayGradient\|preferBarycentricDuringAnimation" --include='*.swift' Nook Navigation App CommandPalette UI | grep -v "Nook/Components/ColorPicker/\|BarycentricGradientView.swift\|SpaceGradientBackgroundView.swift"; echo "grep exit $? (1 means clean)"
```

Expected: no output, `grep exit 1`.

- [ ] **Step 6: Commit (no build; see Interfaces note)**

```bash
cd /Users/bain/git/Nook && git add Nook/Models/Space/SpaceAccent.swift Nook/Models/Space/SpaceGradient.swift Nook/Models/Space/Space.swift Nook/Managers/GradientColorManager/GradientColorManager.swift Nook/Managers/BrowserManager/BrowserManager.swift CommandPalette Nook/Components Nook/Managers/DialogManager && git commit -m "feat(space): single accent color per space, GradientColorManager publishes only accentColor

AI-assisted: implemented with Claude Code."
```

---

### Task 2: Sidebar material window background, gradient views and material setting deleted

**Files:**
- Modify: `Nook/Utils/BlurEffectView.swift`
- Modify: `App/Window/WindowView.swift:175-186` (`WindowBackground`)
- Modify: `Nook/Components/Sidebar/SidebarHoverOverlayView.swift:47-58`
- Delete: `Nook/Components/Browser/Window/SpaceGradientBackgroundView.swift`, `Nook/Utils/BarycentricGradientView.swift`, `Nook/Utils/Shaders/BarycentricShaders.metal`
- Modify: `Settings/NookSettingsService.swift` (remove `currentMaterialRaw`, `currentMaterial`, `materialKey`, its load line ~374, and the `materials` array at ~613-630)
- Modify: `Nook/Components/Settings/Tabs/Appearance.swift` (remove the Background Material picker and the `Liquid Glass` toggle)

**Interfaces:**
- Produces: `BlurEffectView(material:blendingMode:state:)` with `blendingMode: NSVisualEffectView.BlendingMode = .withinWindow`.
- Consumes: nothing from Task 1 directly; Task 1's deletions make `BarycentricGradientView.swift` fail to compile, which this task removes.
- After this task the build still fails on `Nook/Components/ColorPicker/*` (Task 3 deletes) and the `isDark` consumers (Task 6). **The build gate for Tasks 1 and 2 is the grep in Step 6; the first green build is at the end of Task 3.**

- [ ] **Step 1: `BlurEffectView` gains a blending mode**

Replace the struct in `Nook/Utils/BlurEffectView.swift` with:

```swift
struct BlurEffectView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .withinWindow
    var state: NSVisualEffectView.State

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = state
    }
}
```

Existing call sites pass `material:` and `state:` only, so they keep compiling.

- [ ] **Step 2: Window background**

In `App/Window/WindowView.swift`, replace the body of `WindowBackground()` (the `ZStack { BlurEffectView(...); SpaceGradientBackgroundView() }`) with:

```swift
    @ViewBuilder
    private func WindowBackground() -> some View {
        BlurEffectView(material: .sidebar, blendingMode: .behindWindow, state: .followsWindowActiveState)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backgroundDraggable()
            .environment(windowState)
    }
```

Leave the `.contextMenu` on its call site alone (Task 3 retargets it).

- [ ] **Step 3: Hover overlay background**

In `Nook/Components/Sidebar/SidebarHoverOverlayView.swift`, inside the `.background { ... }` block, replace the `SpaceGradientBackgroundView()` element and its three modifiers (`.environmentObject(browserManager)`, `.environmentObject(browserManager.gradientColorManager)`, `.environment(windowState)`) with:

```swift
                            BlurEffectView(material: .sidebar, blendingMode: .behindWindow, state: .active)
                                .clipShape(NookDesign.Radius.shape(cornerRadius))
```

Keep the `Rectangle().fill(Color.clear).nookGlassEffect(...)` that follows.

- [ ] **Step 4: Delete the gradient views and shader**

```bash
cd /Users/bain/git/Nook && git rm -q Nook/Components/Browser/Window/SpaceGradientBackgroundView.swift Nook/Utils/BarycentricGradientView.swift Nook/Utils/Shaders/BarycentricShaders.metal && ls Nook/Utils/Shaders/ 2>/dev/null || echo "Shaders dir gone or empty"
```

If `Nook/Utils/Shaders/` is now empty, remove the directory: `rmdir Nook/Utils/Shaders`.

- [ ] **Step 5: Delete the material setting**

In `Settings/NookSettingsService.swift`:
- Delete `private let materialKey = ...` (search `materialKey`).
- Delete the `currentMaterialRaw` stored property with its `didSet`, and the `currentMaterial` computed property (lines ~60-72).
- Delete the load line `self.currentMaterialRaw = userDefaults.integer(forKey: materialKey)` (~374) and any `materialKey:` entry in the `register(defaults:)` dictionary.
- Delete the `public let materials: [(name: String, value: NSVisualEffectView.Material)] = [...]` array at the bottom (~613-630). If `import AppKit` at that spot is now unused by the rest of the file, remove that import line too (the file still needs Foundation).

In `Nook/Components/Settings/Tabs/Appearance.swift`, delete the `Picker("Background Material", ...)` block and the `Toggle("Liquid Glass", isOn: .constant(true))` line.

- [ ] **Step 6: Verify by grep**

```bash
cd /Users/bain/git/Nook && grep -rn "SpaceGradientBackgroundView\|BarycentricGradientView\|currentMaterial\|materialKey\|\bmaterials\b" --include='*.swift' Nook Navigation App CommandPalette UI Settings; echo "grep exit $? (1 means clean)"
```

Expected: no output, `grep exit 1`.

- [ ] **Step 7: Commit (no build yet)**

```bash
cd /Users/bain/git/Nook && git add -A App Nook Settings && git commit -m "feat(window): sidebar material window background, remove Metal space gradient and material setting

AI-assisted: implemented with Claude Code."
```

---

### Task 3: Gradient editor out, one Space Settings entry point in

**Files:**
- Delete: `Nook/Components/ColorPicker/` (four files)
- Modify: `Nook/Managers/BrowserManager/BrowserManager.swift:1073-1148` (delete `GradientDraft` and `showGradientEditor`, add `showSpaceSettings(for:)`)
- Modify: `App/NookCommands.swift:393-398`, `App/Window/WindowView.swift:27-31`, `Navigation/Sidebar/SpaceContextMenu.swift:61-66`, `Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift:535-536`, `Nook/Models/KeyboardShortcut/KeyboardShortcut.swift:139`
- Modify: `Navigation/Sidebar/SpacesSideBarView.swift:380-~410` (`showSpaceEditDialog`), `Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:113-125,182-195`, `Navigation/Sidebar/SpacesList/SpacesListItem.swift:151-~180` (three copies of the edit-dialog closure collapse to the BrowserManager method)

**Interfaces:**
- Produces: `BrowserManager.showSpaceSettings(for space: Space)` and `BrowserManager.showSpaceSettings()` (current space, or a "No Space" dialog). The dialog's `onSave` signature stays `(String, String, UUID?) -> Void` in this task; Task 4 extends it with the accent.
- Consumes: `GradientColorManager.transition(to:)` from Task 1.

- [ ] **Step 1: Delete the editor**

```bash
cd /Users/bain/git/Nook && git rm -rq Nook/Components/ColorPicker && ls Nook/Components/ColorPicker 2>&1 | head -1
```

- [ ] **Step 2: Replace `showGradientEditor` in BrowserManager**

Delete the `// MARK: - Appearance / Gradient Editing` section: the `private final class GradientDraft` and the whole `func showGradientEditor()` (through its closing brace, ~lines 1073-1148). In their place add:

```swift
    // MARK: - Space Settings

    /// Opens Space Settings for the current space, or a notice when there is none.
    func showSpaceSettings() {
        guard let space = tabManager.currentSpace else {
            dialogManager.showDialog {
                StandardDialog(
                    header: {
                        DialogHeader(
                            icon: "square.grid.2x2",
                            title: "No Space Available",
                            subtitle: "Create a space to change its settings."
                        )
                    },
                    content: { Color.clear.frame(height: 0) },
                    footer: {
                        DialogFooter(rightButtons: [
                            DialogButton(text: "OK", variant: .primary) { [weak self] in
                                self?.closeDialog()
                            }
                        ])
                    }
                )
            }
            return
        }
        showSpaceSettings(for: space)
    }

    /// The single presentation path for the space edit dialog (name, icon, profile).
    func showSpaceSettings(for space: Space) {
        dialogManager.showDialog(
            SpaceEditDialog(
                space: space,
                mode: .icon,
                onSave: { [weak self] newName, newIcon, newProfileId in
                    guard let self else { return }
                    do {
                        if newIcon != space.icon {
                            try self.tabManager.updateSpaceIcon(spaceId: space.id, icon: newIcon)
                        }
                        if newName != space.name {
                            try self.tabManager.renameSpace(spaceId: space.id, newName: newName)
                        }
                        if newProfileId != space.profileId, let profileId = newProfileId {
                            self.tabManager.assign(spaceId: space.id, toProfile: profileId)
                        }
                    } catch {
                        print("Failed to update space: \(error)")
                    }
                    self.closeDialog()
                },
                onCancel: { [weak self] in
                    self?.closeDialog()
                }
            )
        )
    }
```

If the existing copies in `SpacesListItem.swift` / `SpacesSideBarView.swift` do anything beyond icon, rename, profile assign, and close (read them before deleting), carry that behavior into this method so nothing is lost.

- [ ] **Step 3: Retarget the three former editor entry points**

- `App/NookCommands.swift`: `Button("Customize Space Gradient...") { browserManager.showGradientEditor() }` → `Button("Space Settings...") { browserManager.showSpaceSettings() }`. Keep `.modifier(dynamicShortcut(.customizeSpaceGradient))` and the `.disabled` line.
- `App/Window/WindowView.swift`: the `.contextMenu` on `WindowBackground()`: `Button("Customize Space Gradient...") { browserManager.showGradientEditor() }` → `Button("Space Settings...") { browserManager.showSpaceSettings() }`.
- `Navigation/Sidebar/SpaceContextMenu.swift`: delete the `// Customize appearance` button (`Label("Customize Appearance", systemImage: "paintpalette")`) and the `Divider()` directly after it if that leaves two adjacent dividers.
- `Nook/Managers/KeyboardShortcutManager/KeyboardShortcutManager.swift`: `case .customizeSpaceGradient: browserManager.showGradientEditor()` → `browserManager.showSpaceSettings()`.
- `Nook/Models/KeyboardShortcut/KeyboardShortcut.swift:139`: display name `"Customize Space Gradient"` → `"Space Settings"`. Do not rename the enum case or its raw value; users' saved shortcuts reference it.

- [ ] **Step 4: Collapse the three edit-dialog copies**

- `Navigation/Sidebar/SpacesList/SpacesListItem.swift`: delete `private func showSpaceEditDialog()` and change its one caller (`showSpaceEditDialog()` inside `spaceContextMenu`) to `browserManager.showSpaceSettings(for: space)`.
- `Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift`: both `onOpenSettings:` closures that build a `SpaceEditDialog(...)` become `onOpenSettings: { browserManager.showSpaceSettings(for: space) }`. If `updateSpace(name:icon:profileId:)` in that file is then unused, delete it.
- `Navigation/Sidebar/SpacesSideBarView.swift`: `private func showSpaceEditDialog(mode:)` becomes:
  ```swift
    private func showSpaceEditDialog(mode: SpaceEditDialog.Mode) {
        guard let targetSpace = resolveCurrentSpace() else { return }
        browserManager.showSpaceSettings(for: targetSpace)
    }
  ```
  (Keep the signature so its callers compile.)

- [ ] **Step 5: Verify and build**

```bash
cd /Users/bain/git/Nook && grep -rn "showGradientEditor\|GradientDraft\|GradientEditorView\|beginInteractivePreview\|endInteractivePreview\|activePrimaryNodeID\|preferredPrimaryNodeID" --include='*.swift' Nook Navigation App CommandPalette UI; echo "grep exit $? (1 means clean)"
```

Expected: no output, `grep exit 1`. Then run the build command. It will still fail on the `isDark` consumers (Task 6) and on `AppColors` members only if Task 6 has already run; at this point the expected remaining errors are exactly `Value of type 'GradientColorManager' has no member 'isDark'` in `SpacesList.swift`, `SpacesListItem.swift`, `SpaceSeparator.swift`, `TopBarView.swift`. Any other error is this task's to fix. Paste the error list into the report.

- [ ] **Step 6: Commit**

```bash
cd /Users/bain/git/Nook && git add -A App Nook Navigation && git commit -m "refactor(space): delete gradient editor, one showSpaceSettings entry point

AI-assisted: implemented with Claude Code."
```

---

### Task 4: Accent picker in the space dialogs

**Files:**
- Create: `Nook/Managers/DialogManager/Dialogs/SpaceAccentPicker.swift`
- Modify: `Nook/Managers/DialogManager/Dialogs/SpaceEditDialog.swift`
- Modify: `Nook/Managers/DialogManager/Dialogs/SpaceCreationDialog.swift`
- Modify: `Nook/Managers/BrowserManager/BrowserManager.swift` (`showSpaceSettings(for:)` from Task 3)
- Modify: `Navigation/Sidebar/SpacesSideBarView.swift:351-378` (`showSpaceCreationDialog`)

**Interfaces:**
- Produces: `SpaceAccentPicker(selectedHex: Binding<String>)`. `SpaceEditDialog.onSave: (String, String, UUID?, String) -> Void` (name, icon, profileId, accentHex). `SpaceCreationDialog.onCreate: (String, String, UUID?, String) -> Void`.
- Consumes: `SpaceAccent.presets`, `SpaceGradient.accent(hex:)`, `Space.accentHex` (Task 1); `BrowserManager.refreshGradientsForSpace(_:animate:)` (existing).

- [ ] **Step 1: The picker**

```swift
//
//  SpaceAccentPicker.swift
//  Nook
//
//  Eight preset swatches plus a system color well for a custom accent.
//

import SwiftUI

struct SpaceAccentPicker: View {
    @Binding var selectedHex: String

    private var customColor: Binding<Color> {
        Binding(
            get: { Color(hex: selectedHex) },
            set: { selectedHex = $0.toHexString() ?? selectedHex }
        )
    }

    var body: some View {
        HStack(spacing: NookDesign.Spacing.md) {
            ForEach(SpaceAccent.presets, id: \.hex) { preset in
                Button {
                    selectedHex = preset.hex
                } label: {
                    Circle()
                        .fill(Color(hex: preset.hex))
                        .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
                        .overlay {
                            if preset.hex.caseInsensitiveCompare(selectedHex) == .orderedSame {
                                Circle()
                                    .strokeBorder(Color.primary, lineWidth: 2)
                                    .padding(NookDesign.Spacing.xxs)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
            ColorPicker("", selection: customColor, supportsOpacity: false)
                .labelsHidden()
                .help("Custom color")
        }
    }
}
```

`Color(hex:)` and `toHexString()` already exist in `Nook/Utils/Colors.swift`.

- [ ] **Step 2: Edit dialog carries the accent**

In `SpaceEditDialog.swift`:
- Add `private let originalAccentHex: String` and `@State private var accentHex: String`; in `init`, read `let accent = MainActor.assumeIsolated { space.accentHex }`, set both.
- Change `onSaveChanges` to `(String, String, UUID?, String) -> Void` and the `init` `onSave` parameter to match.
- `dialogFooter()`: the Save action becomes `onSaveChanges(effectiveName, iconValue, selectedProfileId, accentHex)`.
- `dialogContent()`: pass `accentHex: $accentHex` to `SpaceEditContent`; add `@Binding var accentHex: String` there and, between the icon section and the profile section, a new section:
  ```swift
            VStack(alignment: .leading, spacing: 10) {
                Text("Accent")
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.primary)
                SpaceAccentPicker(selectedHex: $accentHex)
            }
  ```

- [ ] **Step 3: Creation dialog carries the accent**

In `SpaceCreationDialog.swift`:
- Add `@State private var accentHex: String` initialized to `SpaceAccent.defaultHex`.
- `onCreate` becomes `(String, String, UUID?, String) -> Void`; `handleCreate` passes `accentHex` as the fourth argument.
- `dialogContent()` passes `accentHex: $accentHex`; `SpaceCreationContent` gains `@Binding var accentHex: String` and the same "Accent" section as Step 2, placed between the icon and profile sections.

- [ ] **Step 4: Callers**

In `BrowserManager.showSpaceSettings(for:)`, the `onSave` closure gains a fourth parameter and writes the accent when it changed:

```swift
                onSave: { [weak self] newName, newIcon, newProfileId, newAccentHex in
                    guard let self else { return }
                    do {
                        if newIcon != space.icon {
                            try self.tabManager.updateSpaceIcon(spaceId: space.id, icon: newIcon)
                        }
                        if newName != space.name {
                            try self.tabManager.renameSpace(spaceId: space.id, newName: newName)
                        }
                        if newProfileId != space.profileId, let profileId = newProfileId {
                            self.tabManager.assign(spaceId: space.id, toProfile: profileId)
                        }
                    } catch {
                        print("Failed to update space: \(error)")
                    }
                    if newAccentHex.caseInsensitiveCompare(space.accentHex) != .orderedSame {
                        space.gradient = .accent(hex: newAccentHex)
                        self.refreshGradientsForSpace(space, animate: true)
                        self.tabManager.persistSnapshot()
                    }
                    self.closeDialog()
                },
```

In `SpacesSideBarView.showSpaceCreationDialog()`, the `onCreate` closure gains `accentHex` and creates the space with it:

```swift
                onCreate: { name, icon, profileId, accentHex in
                    let finalName = name.isEmpty ? "New Space" : name
                    let finalIcon = icon.isEmpty ? "square.grid.2x2" : icon
                    let newSpace = tabManager.createSpace(
                        name: finalName,
                        icon: finalIcon,
                        gradient: .accent(hex: accentHex)
                    )
```
(the rest of that closure is unchanged). Note the default icon changes from `"✨"` to `"square.grid.2x2"`, per spec section 4.

- [ ] **Step 5: Build**

Run the build command. Expected remaining errors: only the four `isDark` files named in Task 3 Step 5. Anything else is this task's to fix.

- [ ] **Step 6: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Nook Navigation && git commit -m "feat(space): accent swatch picker in space creation and settings dialogs

AI-assisted: implemented with Claude Code."
```

---

### Task 5: SF Symbol space icons, one icon view, one icon picker

**Files:**
- Create: `Nook/Models/Space/SpaceIcon.swift` (`String.isEmojiIcon`, `SpaceIconView`)
- Create: `Nook/Components/Sidebar/SpaceSection/SpaceIconPicker.swift`
- Modify: `Nook/Design/NookDesign.swift` (add `Size.spaceIcon`)
- Delete: `Nook/Components/EmojiPicker/EmojiPicker.swift` (and the directory if empty)
- Modify: `Navigation/Sidebar/SpacesList/SpacesListItem.swift`, `Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift`, `Nook/Managers/DialogManager/Dialogs/SpaceEditDialog.swift`, `Nook/Managers/DialogManager/Dialogs/SpaceCreationDialog.swift` (emoji picker consumers)
- Modify: the other `isEmoji` copies: `Nook/Managers/DialogManager/Dialogs/SpaceDeleteConfirmationDialog.swift:82`, `Nook/Components/Sidebar/SpaceSection/SpaceTab.swift:324`, `Nook/Components/Settings/SettingsView.swift:446`, `CommandPalette/CommandPaletteView.swift:344`

**Interfaces:**
- Produces: `extension String { var isEmojiIcon: Bool }`; `SpaceIconView(icon: String, size: CGFloat, tint: Color)`; `SpaceIconPicker(selected: String, onPick: (String) -> Void)`; `NookDesign.Size.spaceIcon: CGFloat = 14`.
- Consumes: `Space.accentColor` (Task 1).

- [ ] **Step 1: Token**

In `NookDesign.swift`, `enum Size`, add `static let spaceIcon: CGFloat = 14      // switcher and header symbol`.

- [ ] **Step 2: Icon helpers**

```swift
//
//  SpaceIcon.swift
//  Nook
//
//  Space icons are SF Symbol names. Values saved before Phase 2 may be
//  emoji; those still render as text so nothing breaks on upgrade.
//

import SwiftUI

extension String {
    /// True when the string is an emoji glyph rather than an SF Symbol name.
    var isEmojiIcon: Bool {
        unicodeScalars.contains { scalar in
            scalar.properties.isEmojiPresentation
                || (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF)
                || (scalar.value >= 0x2600 && scalar.value <= 0x26FF)
                || (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }
}

/// Renders a space icon: SF Symbol tinted with the space accent, or legacy emoji as text.
struct SpaceIconView: View {
    let icon: String
    var size: CGFloat = NookDesign.Size.spaceIcon
    var tint: Color = .secondary

    var body: some View {
        Group {
            if icon.isEmojiIcon {
                Text(icon)
                    .font(.system(size: size))
            } else {
                Image(systemName: icon.isEmpty ? "square.grid.2x2" : icon)
                    .font(.system(size: size, weight: .medium))
                    .foregroundStyle(tint)
            }
        }
        .frame(width: size + NookDesign.Spacing.sm, height: size + NookDesign.Spacing.sm)
    }
}
```

(The `size` argument is a variable, not a literal, so the Phase 1 font audit stays clean.)

- [ ] **Step 3: Icon picker**

```swift
//
//  SpaceIconPicker.swift
//  Nook
//
//  Curated SF Symbol grid shown in a popover. Replaces the emoji picker.
//

import SwiftUI

struct SpaceIconPicker: View {
    let selected: String
    let onPick: (String) -> Void

    static let symbols: [String] = [
        "square.grid.2x2", "briefcase", "house", "star", "book", "cart", "gamecontroller", "music.note",
        "film", "graduationcap", "heart", "leaf", "flame", "bolt", "globe", "chevron.left.forwardslash.chevron.right",
        "terminal", "hammer", "wrench.and.screwdriver", "paintbrush", "camera", "photo", "map", "airplane",
        "car", "building.2", "person", "person.2", "envelope", "message", "phone", "calendar",
        "clock", "folder", "tray", "doc", "note.text", "chart.bar", "dollarsign.circle", "creditcard",
        "tag", "bookmark", "flag", "mappin", "bell", "gearshape", "sparkles", "eye",
    ]

    private let columns = Array(repeating: GridItem(.fixed(NookDesign.Size.iconButton), spacing: NookDesign.Spacing.xs), count: 8)

    var body: some View {
        LazyVGrid(columns: columns, spacing: NookDesign.Spacing.xs) {
            ForEach(Self.symbols, id: \.self) { symbol in
                Button {
                    onPick(symbol)
                } label: {
                    Image(systemName: symbol)
                        .font(NookDesign.Font.title)
                        .foregroundStyle(symbol == selected ? Color.accentColor : .primary)
                        .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
                        .background(
                            NookDesign.Radius.shape(NookDesign.Radius.sm)
                                .fill(symbol == selected ? NookDesign.Surface.fillPressed : .clear)
                        )
                }
                .buttonStyle(.plain)
                .help(symbol)
            }
        }
        .padding(NookDesign.Spacing.lg)
    }
}
```

- [ ] **Step 4: Replace the four emoji picker consumers**

Pattern at each site: delete `@StateObject private var emojiManager = EmojiPickerManager()`, every `.background(EmojiPickerAnchor(manager: emojiManager))`, every `.onChange(of: emojiManager.selectedEmoji) { ... }`, every `emojiManager.toggle()` / `emojiManager.selectedEmoji = ...`; add `@State private var showIconPicker = false`; present the picker with `.popover(isPresented: $showIconPicker) { SpaceIconPicker(selected: <current>, onPick: { ... ; showIconPicker = false }) }`.

- `SpacesListItem.swift`: `spaceIcon` becomes
  ```swift
    @ViewBuilder
    private var spaceIcon: some View {
        if compact && !isActive {
            Circle()
                .fill(Color.secondary)
                .frame(width: dotSize, height: dotSize)
        } else {
            SpaceIconView(icon: space.icon, tint: isActive ? space.accentColor : .secondary)
        }
    }
  ```
  Delete `iconColor` and the private `isEmoji`. The button label loses `.opacity(isActive ? 1.0 : 0.7)`; add `.background(NookDesign.Radius.shape(NookDesign.Radius.md).fill(isActive ? NookDesign.Surface.fill : .clear))` on the button (after `.buttonStyle`). Change `.buttonStyle(NookIconButtonStyle(radius: NookDesign.Radius.lg))` to `.buttonStyle(NookIconButtonStyle())`. This site had no toggle entry point (the picker opened from elsewhere), so no popover here.
- `SpaceTitle.swift`: delete the hidden `TextField("", text: $selectedEmoji)` block and the `selectedEmoji` / `emojiFieldFocused` state; the icon becomes `SpaceIconView(icon: space.icon, size: iconSize, tint: space.accentColor)` with `.onTapGesture(count: 2) { showIconPicker = true }` and the popover whose `onPick` sets `space.icon = $0; tabManager.persistSnapshot()`. `onEditIcon: { emojiManager.toggle() }` (both occurrences) becomes `onEditIcon: { showIconPicker = true }`. Delete the private `isEmoji`.
- `SpaceEditDialog.swift` (`SpaceEditContent`): the icon `Button { emojiManager.toggle() }` becomes `Button { showIconPicker = true }` with `.popover(isPresented: $showIconPicker) { SpaceIconPicker(selected: currentIcon, onPick: { spaceIcon = $0; showIconPicker = false }) }`. Delete the file's private `SpaceIconView` struct and use the shared one: `SpaceIconView(icon: currentIcon, size: NookDesign.Size.iconButton - NookDesign.Spacing.md, tint: .primary)`. Delete the `.onAppear` / `.onChange` that referenced `emojiManager`.
- `SpaceCreationDialog.swift` (`SpaceCreationContent`): same pattern; `SpaceCreationIconPreview` is deleted and replaced by `SpaceIconView(icon: spaceIcon, tint: .primary)`.

- [ ] **Step 5: Dedupe the remaining `isEmoji` copies and delete the emoji picker**

At `SpaceDeleteConfirmationDialog.swift`, `SpaceTab.swift`, `SettingsView.swift`, `CommandPaletteView.swift`: replace each call of the private `isEmoji(x)` with `x.isEmojiIcon` and delete the private function. Where the call site renders `if isEmoji(space.icon) { Text } else { Image }`, replace the whole conditional with `SpaceIconView(icon: space.icon, tint: .primary)` if the surrounding sizing allows (keep the site's existing size argument if it passes one).

```bash
cd /Users/bain/git/Nook && git rm -q Nook/Components/EmojiPicker/EmojiPicker.swift && rmdir Nook/Components/EmojiPicker 2>/dev/null; grep -rn "EmojiPicker\|emojiManager\|func isEmoji\|isEmoji(" --include='*.swift' Nook Navigation App CommandPalette UI; echo "grep exit $? (1 means clean)"
```

Expected: no output, `grep exit 1`.

- [ ] **Step 6: Build**

Run the build command. Expected remaining errors: only the four `isDark` files. Anything else is this task's to fix.

- [ ] **Step 7: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Nook Navigation CommandPalette && git commit -m "feat(space): SF Symbol icons with emoji fallback, SpaceIconPicker replaces the emoji picker

AI-assisted: implemented with Claude Code."
```

---

### Task 6: Remove the light/dark color branches and the AppColors semantic pairs

**Files:**
- Modify: `Nook/Utils/Colors.swift:15-43` (delete the semantic members)
- Modify: `isDark` consumers: `Navigation/Sidebar/SpacesList/SpacesList.swift:112`, `Nook/Components/Sidebar/SpaceSection/SpaceSeparator.swift:79-92`, `Nook/Components/Sidebar/TopBar/TopBarView.swift:326,369-373,393-394`
- Modify: `AppColors` consumers: `Nook/Components/Sidebar/SpaceSection/SpaceTab.swift:62,121,370-378`, `Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift:89,133-144`, `Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:212,218`, `Nook/Components/Sidebar/SpaceSection/TabFolderView.swift:174-175,244`, `Nook/Components/Sidebar/PinnedButtons/PinnedTabView.swift:91-107`, `Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift:77`, `Nook/Components/Sidebar/URLBarView.swift:128-134`
- Modify: remaining `colorScheme == .dark` branches in `Navigation/`, `Nook/Components/Sidebar/`, `CommandPalette/`: `SidebarResizeView.swift:43`, `SpaceSeparator.swift:51`, `DownloadIndicator.swift:48,53,60`, `CommandPaletteView.swift:68,362`, `HistorySuggestionItem.swift:22`, `TabSuggestionItem.swift:19`, `GenericSuggestionItem.swift:18`

**Interfaces:**
- Consumes: `NookDesign.Surface.fill / fillPressed / hairline / raised`.
- Produces: nothing new. After this task the build is green.

- [ ] **Step 1: Mapping table**

| Old expression | New |
|---|---|
| `spaceTabTextLight/Dark`, `sidebarTextLight/Dark`, `iconActiveLight/Dark` (any branch) | `.primary` for tab/space titles and icons; `.secondary` for the space header ellipsis and URL bar icon |
| `spaceTabActiveLight/Dark`, `pinnedTabActiveLight/Dark` | `NookDesign.Surface.raised` |
| `spaceTabHoverLight/Dark`, `pinnedTabIdleLight/Dark`, `controlBackgroundHoverLight` | `NookDesign.Surface.fill` |
| `pinnedTabHoverLight/Dark`, `controlBackgroundActive`, `controlBackgroundHover` | `NookDesign.Surface.fillPressed` |
| `Color.white.opacity(x)` / `Color.black.opacity(x)` picked by `colorScheme` or `isDark` for a hairline (SpaceSeparator line, resize handle) | `NookDesign.Surface.hairline` |
| the same for a text/icon color (SpaceSeparator `clearColor`/`organizeColor`, DownloadIndicator, suggestion items) | `.secondary` at rest, `.primary` when hovered |
| the same for a fill (CommandPaletteView rows, suggestion item backgrounds) | `NookDesign.Surface.fill` at rest, `fillPressed` when selected |
| `TopBarView` fallbacks (`gradientColorManager.isDark ? ... : ...`) | the page-color branches above them stay; the fallback becomes the token from this table (`.primary` text, `Surface.fill` / `fillPressed` background) |

Every `@Environment(\.colorScheme)` declaration that becomes unused after the edit is deleted. `PinnedTabView.shadowColor` was deleted in Phase 1; if `backgroundColor` there is the only remaining branch, replace its body with `isActive ? NookDesign.Surface.raised : (isHovered ? NookDesign.Surface.fillPressed : NookDesign.Surface.fill)`.

- [ ] **Step 2: Delete the members from `Colors.swift`**

Keep `textPrimary`, `textSecondary`, `textTertiary`, `background`, `backgroundSecondary`. Delete `controlBackground`, `controlBackgroundHover`, `controlBackgroundHoverLight`, `controlBackgroundActive`, `iconActiveLight`, `iconActiveDark`, `spaceTabActiveLight`, `spaceTabHoverLight`, `spaceTabTextLight`, `spaceTabActiveDark`, `spaceTabHoverDark`, `spaceTabTextDark`, `pinnedTabActiveLight`, `pinnedTabHoverLight`, `pinnedTabIdleLight`, `pinnedTabActiveDark`, `pinnedTabHoverDark`, `pinnedTabIdleDark`, `sidebarTextLight`, `sidebarTextDark`. Keep everything below the struct (hex helpers, brightness, `NSImage.singlePixelColor`).

- [ ] **Step 3: Apply the table at every site listed in Files**

Use the Edit tool per site. Where a computed property collapses to a constant (for example `iconColor` in SpaceTitle), inline the token and delete the property.

- [ ] **Step 4: Verify and build**

```bash
cd /Users/bain/git/Nook && grep -rnE "gradientColorManager\.isDark|AppColors\.(spaceTab|pinnedTab|sidebarText|iconActive|controlBackground)" --include='*.swift' Nook Navigation App CommandPalette UI; echo "grep A exit $? (1 means clean)"; grep -rn "colorScheme == .dark" --include='*.swift' Navigation Nook/Components/Sidebar CommandPalette; echo "grep B exit $? (1 means clean)"
```

Expected: both empty, both `exit 1`. Then run the build command. Expected: no `error:` lines, `exit 0`. This is the first green build of the phase; fix anything left over from Tasks 1 through 5 here and name it in the report.

- [ ] **Step 5: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Nook Navigation CommandPalette && git commit -m "refactor(ui): remove light/dark color branches and AppColors semantic pairs in favor of NookDesign.Surface

AI-assisted: implemented with Claude Code."
```

---

### Task 7: One essentials size

**Files:**
- Delete: `Nook/Components/Sidebar/PinnedButtons/PinnedUtils.swift`
- Modify: `Nook/Design/NookDesign.swift` (`Size.essentialsFavicon`, `Size.essentialsStroke`)
- Modify: `Settings/NookSettingsService.swift` (`pinnedTabsLookKey`, `pinnedTabsLook`, its registered default and load line)
- Modify: `Nook/Components/Settings/Tabs/Appearance.swift` (remove the Favorites Appearance picker)
- Modify: `Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift:30,84-86,102,170-172,250-280`, `Nook/Components/Sidebar/PinnedButtons/PinnedTabView.swift:29,33,47,59,71-72,80-82`, `Nook/Components/DragDrop/NookDragSessionManager.swift:61`, `Nook/Components/DragDrop/NookDragPreviewWindow.swift:132,163,177,186,194,223,232,235,239-240`

**Interfaces:**
- Produces: `NookDesign.Size.essentialsFavicon: CGFloat = 20`, `NookDesign.Size.essentialsStroke: CGFloat = 2`. Tile geometry everywhere: width/height `Size.essentialsTile` (44), radius `Radius.lg`, grid spacing `Spacing.sm`, max 4 columns.

- [ ] **Step 1: Tokens**

In `NookDesign.swift`, `enum Size`, add:
```swift
        static let essentialsFavicon: CGFloat = 20
        static let essentialsStroke: CGFloat = 2
```

- [ ] **Step 2: Replace every `PinnedTabsConfiguration` read**

| Old | New |
|---|---|
| `.faviconHeight` | `NookDesign.Size.essentialsFavicon` |
| `.minWidth`, `.height` | `NookDesign.Size.essentialsTile` |
| `.cornerRadius` | `NookDesign.Radius.lg` |
| `.strokeWidth` | `NookDesign.Size.essentialsStroke` |
| `.gridSpacing` | `NookDesign.Spacing.sm` |
| `.maxColumns` | `4` as a `private let maxColumns = 4` in `PinnedGrid.swift` |

- `PinnedGrid.swift`: delete `let pinnedTabsConfiguration: PinnedTabsConfiguration = nookSettings.pinnedTabsLook` and the two `dragSession.pinnedTabsConfig = ...` lines; replace the rest per the table.
- `PinnedTabView.swift`: delete `let pinnedTabsConfiguration = nookSettings.pinnedTabsLook`; replace per the table; if `nookSettings` is then unused in the file, delete the `@Environment(\.nookSettings)` line.
- `NookDragSessionManager.swift`: delete `@Published var pinnedTabsConfig: PinnedTabsConfiguration = .large`.
- `NookDragPreviewWindow.swift`: delete the `pinnedConfig:` argument at line ~132 and the `let pinnedConfig: PinnedTabsConfiguration` property; replace its uses per the table. Line ~235 `.font(.system(size: pinnedConfig.faviconHeight, weight: .medium))` becomes `.font(.system(size: NookDesign.Size.essentialsFavicon, weight: .medium))`.

- [ ] **Step 3: Delete the setting**

`Settings/NookSettingsService.swift`: delete `pinnedTabsLookKey`, the `pinnedTabsLook` property with its `didSet`, the `pinnedTabsLookKey: "large"` registered default, and the load line `self.pinnedTabsLook = PinnedTabsConfiguration(rawValue: ...)`.
`Appearance.swift`: delete the `Picker("Favorites Appearance", ...)` block.

```bash
cd /Users/bain/git/Nook && git rm -q Nook/Components/Sidebar/PinnedButtons/PinnedUtils.swift && grep -rn "PinnedTabsConfiguration\|pinnedTabsLook\|pinnedTabsConfig\|pinnedConfig" --include='*.swift' Nook Navigation App CommandPalette UI Settings; echo "grep exit $? (1 means clean)"
```

Expected: no output, `grep exit 1`.

- [ ] **Step 4: Build**

Run the build command. Expected: no `error:` lines, `exit 0`.

- [ ] **Step 5: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Nook Settings && git commit -m "refactor(essentials): one tile size from NookDesign, delete PinnedTabsConfiguration and its setting

AI-assisted: implemented with Claude Code."
```

---

### Task 8: Phase gate

- [ ] **Step 1: Audit**

```bash
cd /Users/bain/git/Nook && S=(Navigation Nook/Components UI CommandPalette Nook/Managers App Settings); \
for pat in "SpaceGradientBackgroundView" "BarycentricGradientView" "GradientEditorView" "showGradientEditor" "EmojiPicker" "func isEmoji" "PinnedTabsConfiguration" "currentMaterial" "gradientColorManager.isDark" "displayGradient" "AppColors\.(spaceTab|pinnedTab|sidebarText|iconActive|controlBackground)"; do printf "%-45s %s\n" "$pat" "$(grep -rnE "$pat" --include='*.swift' "${S[@]}" | wc -l | tr -d ' ')"; done; \
echo "colorScheme==.dark in sidebar/palette: $(grep -rn 'colorScheme == .dark' --include='*.swift' Navigation Nook/Components/Sidebar CommandPalette | wc -l | tr -d ' ')"; \
echo "font literals: $(grep -rnE '\.font\(\.system\(size: ?[0-9]' --include='*.swift' Navigation Nook/Components UI CommandPalette Nook/Managers/DialogManager | grep -v NookDesign.swift | wc -l | tr -d ' ')"; \
ls Nook/Components/ColorPicker Nook/Components/EmojiPicker Nook/Utils/Shaders 2>&1 | grep -c "No such file"
```

Expected: every count `0`, and the last line `3` (all three directories gone).

- [ ] **Step 2: Build and manual checklist**

Run the build command, then build signed for running (`xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build -allowProvisioningUpdates -quiet`) and open `build/Build/Products/Debug/Nook.app`. Check: the window background is the system sidebar material with no gradient, in light and dark, with the sidebar on the left and right; existing spaces show their old primary color as the accent on the space icon and switcher; the space edit dialog shows the accent swatches and changing one animates the accent; creating a space picks the default teal; existing emoji icons still render; the icon picker popover opens from the space header double-click, the context menu, and both dialogs; hover and active fills on tabs, essentials, and the URL bar read in both appearances; essentials are four across at 44pt; Cmd-Shift-G opens Space Settings; the hover sidebar overlay has the material background; an incognito window has a dark accent; quit and relaunch keeps every space's accent and icon.

- [ ] **Step 3: Record**

Append `Done <date>, commits <first>..<last>.` to phase 2 under `## Phases` in `docs/superpowers/specs/2026-09-14-gui-remodel-design.md`, and commit:

```bash
cd /Users/bain/git/Nook && git add docs/superpowers/specs/2026-09-14-gui-remodel-design.md && git commit -m "docs: mark GUI remodel phase 2 done

AI-assisted: implemented with Claude Code."
```
