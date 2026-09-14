# GUI Remodel Phase 1: Tokens and Sweep

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one token file, `NookDesign`, and replace every literal corner radius, font size, animation curve, and shadow in the UI layer with a token, so later phases restyle by editing one file.

**Architecture:** `Nook/Design/NookDesign.swift` holds nested enums (Radius, Spacing, Size, Font, Motion, Surface, Elevation). The sweep is mechanical: literal in, token out, no layout or behavior change beyond continuous corners and radius snapping. Three duplicate icon button styles collapse into `NookIconButtonStyle`. Dead OS-availability helpers are deleted.

**Tech Stack:** Swift 5, SwiftUI, macOS 26 SDK, Xcode 26.6. No test target; verification is `grep` assertions plus a Debug build.

**Spec:** `docs/superpowers/specs/2026-09-14-gui-remodel-design.md` (sections 1 and 2).

## Global Constraints

- Deployment target macOS 26.0, Apple Silicon. Never add `#available` guards below 26.
- Swift language mode 5. Do not enable strict concurrency.
- No test target exists. The build command for every verification step is:
  ```bash
  cd /Users/bain/git/Nook && xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | grep -E "error:|BUILD" ; echo "exit ${PIPESTATUS[0]}"
  ```
  Expected: no `error:` lines and `exit 0`. Warnings are acceptable.
- Sweep scope directories: `Navigation/`, `Nook/Components/`, `UI/`, `CommandPalette/`, `Nook/Managers/DialogManager/`.
- Sweep exclusions (deleted or reworked in later phases; leave untouched): `Nook/Components/ColorPicker/`, `Nook/Components/EmojiPicker.swift`, `Onboarding/`, `Nook/ThirdParty/`.
- Materials and blur recipes (`.ultraThinMaterial`, `BlurEffectView(...)`, `NSVisualEffectView`) are Phase 4. Do not touch them here.
- `AppColors` semantic color pairs are removed in Phase 2. Do not touch `Nook/Utils/Colors.swift` here.
- Xcode uses filesystem-synchronized groups: creating a file under `Nook/` adds it to the target automatically. No pbxproj edits.
- Every commit message ends with the line `AI-assisted: implemented with Claude Code.`
- Do not run the app or ask for manual checks mid-task; the manual checklist runs once at the end of the phase.

---

### Task 1: Create the token file

**Files:**
- Create: `Nook/Design/NookDesign.swift`

**Interfaces:**
- Produces: `enum NookDesign` with nested `Radius`, `Spacing`, `Size`, `Font`, `Motion`, `Surface`, `Elevation`; `View.nookElevation(_:)`; `NookDesign.Radius.shape(_:)`. Every later task consumes these exact names.

- [ ] **Step 1: Write the file**

```swift
//
//  NookDesign.swift
//  Nook
//
//  Single source of truth for radii, spacing, sizes, type, motion,
//  surfaces, and elevation. No literal radius, font size, shadow, or
//  animation duration may appear in the UI layer outside this file.
//

import SwiftUI

enum NookDesign {

    // MARK: - Radius (all continuous / squircle)

    enum Radius {
        static let xs: CGFloat = 4      // favicon
        static let sm: CGFloat = 6      // icon button, menu item, small chip
        static let md: CGFloat = 8      // tab row, nav button, URL bar
        static let lg: CGFloat = 12     // essentials tile, card, settings group
        static let xl: CGFloat = 16     // dialog, toast
        static let xxl: CGFloat = 24    // command palette

        static func shape(_ radius: CGFloat) -> RoundedRectangle {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
        }
    }

    // MARK: - Spacing

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 20
        static let xxxl: CGFloat = 24

        static let sidebarInset: CGFloat = 8
        static let rowGap: CGFloat = 2
        static let sectionGap: CGFloat = 10
        static let rowPadding: CGFloat = 8
        static let folderIndent: CGFloat = 20
    }

    // MARK: - Size

    enum Size {
        static let row: CGFloat = 32
        static let iconButton: CGFloat = 28
        static let favicon: CGFloat = 16
        static let essentialsTile: CGFloat = 44
        static let urlBar: CGFloat = 32
        static let navRow: CGFloat = 28
        static let bottomBar: CGFloat = 40
    }

    // MARK: - Type

    enum Font {
        static let hero = SwiftUI.Font.system(size: 48, weight: .semibold)        // empty-state glyphs only
        static let display = SwiftUI.Font.system(size: 28, weight: .semibold)     // empty-state titles
        static let titleLarge = SwiftUI.Font.system(size: 20, weight: .semibold)  // panel titles
        static let heading = SwiftUI.Font.system(size: 17, weight: .semibold)     // settings pane title, dialog title
        static let title = SwiftUI.Font.system(size: 15, weight: .semibold)       // palette input, toast title
        static let label = SwiftUI.Font.system(size: 13, weight: .semibold)       // space name, folder name
        static let body = SwiftUI.Font.system(size: 13, weight: .medium)          // tab title, menu item, settings row
        static let bodyRegular = SwiftUI.Font.system(size: 13, weight: .regular)  // paragraphs, descriptions
        static let secondary = SwiftUI.Font.system(size: 12, weight: .medium)     // URL bar, popup button
        static let caption = SwiftUI.Font.system(size: 11, weight: .medium)       // counts, shortcuts, subtitles
        static let captionStrong = SwiftUI.Font.system(size: 11, weight: .semibold) // section headers
        static let micro = SwiftUI.Font.system(size: 9, weight: .semibold)        // badges only
    }

    // MARK: - Motion

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.12)      // hover, press
        static let standard = Animation.smooth(duration: 0.22)    // selection, reveal, fold
        static let spring = Animation.bouncy(duration: 0.3)       // palette, dialog, toast
    }

    // MARK: - Surface

    enum Surface {
        static let fill = Color.primary.opacity(0.045)           // hover, URL bar, idle tile
        static let fillPressed = Color.primary.opacity(0.08)
        static let hairline = Color.primary.opacity(0.08)
        static let raised = Color(nsColor: .controlBackgroundColor) // active row, active tile
    }

    // MARK: - Elevation

    enum Elevation {
        case raised    // hairline + tight shadow: active row, tile, settings group
        case floating  // menu, palette, toast, dialog, popover
    }
}

// MARK: - View helpers

private struct NookElevationModifier: ViewModifier {
    let level: NookDesign.Elevation

    func body(content: Content) -> some View {
        switch level {
        case .raised:
            content.shadow(color: .black.opacity(0.05), radius: 2, y: 1)
        case .floating:
            content
                .shadow(color: .black.opacity(0.16), radius: 32, y: 12)
                .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        }
    }
}

extension View {
    func nookElevation(_ level: NookDesign.Elevation) -> some View {
        modifier(NookElevationModifier(level: level))
    }
}
```

- [ ] **Step 2: Build**

Run the build command from Global Constraints.
Expected: no `error:` lines, `exit 0`.

- [ ] **Step 3: Commit**

```bash
cd /Users/bain/git/Nook && git add Nook/Design/NookDesign.swift && git commit -m "feat(design): add NookDesign token file

AI-assisted: implemented with Claude Code."
```

---

### Task 2: One icon button style, delete conditional modifiers

**Files:**
- Modify: `UI/Buttons/NavButtons/NavButton.swift`
- Modify: `Navigation/Sidebar/SpacesList/SpacesListItem.swift` (remove `SpaceListItemButtonStyle`, fix one `.conditionally` call)
- Modify: `Nook/Components/Sidebar/URLBarView.swift` (remove `URLBarButtonStyle`)
- Modify: `Nook/Managers/DialogManager/DialogManager.swift` (fix one `.conditionally` call)
- Delete: `UI/ConditionalModifiers.swift`

**Interfaces:**
- Produces: `struct NookIconButtonStyle: ButtonStyle` with `init(size: CGFloat = NookDesign.Size.iconButton, radius: CGFloat = NookDesign.Radius.md)`. `RectNavButtonStyle` is unchanged.
- Consumes: `NookDesign.Size.iconButton`, `NookDesign.Radius.shape`, `NookDesign.Motion.quick`, `NookDesign.Surface.fill`, `NookDesign.Surface.fillPressed`.

- [ ] **Step 1: Replace `NavButtonStyle` in `NavButton.swift`**

Replace the whole `struct NavButtonStyle: ButtonStyle { ... }` (from its declaration to the closing brace before `/// Rectangular variant`) with:

```swift
/// Square icon button. Hover shows a fill, press shows a stronger fill and a 0.95 scale.
/// Sizes and radii come from NookDesign; pass overrides only for the space switcher (14pt glyph) or URL bar (28).
struct NookIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovering = false

    let size: CGFloat
    let radius: CGFloat

    init(size: CGFloat = NookDesign.Size.iconButton, radius: CGFloat = NookDesign.Radius.md) {
        self.size = size
        self.radius = radius
    }

    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            NookDesign.Radius.shape(radius)
                .fill(fill(isPressed: configuration.isPressed))
                .frame(width: size, height: size)
            configuration.label
                .foregroundStyle(.primary)
        }
        .opacity(isEnabled ? 1.0 : 0.3)
        .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
        .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
        .animation(NookDesign.Motion.quick, value: configuration.isPressed)
        .animation(NookDesign.Motion.quick, value: isHovering)
        .onHoverTracking { hovering in isHovering = hovering }
    }

    private func fill(isPressed: Bool) -> Color {
        guard isEnabled else { return .clear }
        if isPressed { return NookDesign.Surface.fillPressed }
        if isHovering { return NookDesign.Surface.fill }
        return .clear
    }
}
```

Keep `RectNavButtonStyle` as is except: change its `private var cornerRadius: CGFloat { 8 }` to `NookDesign.Radius.md`, and its two `.animation(.easeInOut(duration: ...))` lines to `.animation(NookDesign.Motion.quick, ...)`. In both `#Preview` blocks replace `NavButtonStyle()` with `NookIconButtonStyle()`.

- [ ] **Step 2: Rename every `NavButtonStyle(` call site**

```bash
cd /Users/bain/git/Nook && grep -rl "NavButtonStyle(" --include='*.swift' Navigation Nook UI CommandPalette App | grep -v RectNavButtonStyle | xargs sed -i '' -E 's/\bNavButtonStyle\(/NookIconButtonStyle(/g'
```

Then check any call that passed `size: .small` style `ControlSize` arguments:

```bash
grep -rn "NookIconButtonStyle(size:" --include='*.swift' Navigation Nook UI CommandPalette App
```

For each hit that passes a `ControlSize` (`.mini`, `.small`, `.regular`, `.large`), replace with the CGFloat it mapped to: mini 24, small 28, regular 32, large 40. Also grep for `.controlSize(` applied to a button using this style and remove the modifier, replacing with an explicit `size:` argument using the same mapping.

- [ ] **Step 3: Delete `SpaceListItemButtonStyle` and fix its `.conditionally` call**

In `Navigation/Sidebar/SpacesList/SpacesListItem.swift`:
- Delete the entire `struct SpaceListItemButtonStyle: ButtonStyle { ... }` at the end of the file.
- Replace `.buttonStyle(SpaceListItemButtonStyle())` with `.buttonStyle(NookIconButtonStyle(radius: NookDesign.Radius.lg))`.
- Replace
  ```swift
  Text(space.icon)
      .conditionally(if: !isActive, apply: { view in
          view.colorMultiply(.gray).blendMode(.luminosity)
      })
  ```
  with
  ```swift
  Text(space.icon)
      .colorMultiply(isActive ? .white : .gray)
      .blendMode(isActive ? .normal : .luminosity)
  ```

- [ ] **Step 4: Delete `URLBarButtonStyle`**

In `Nook/Components/Sidebar/URLBarView.swift` delete `// MARK: - URL Bar Button Style` and the whole `struct URLBarButtonStyle` below it. Replace every `.buttonStyle(URLBarButtonStyle())` in that file with `.buttonStyle(NookIconButtonStyle(size: 28, radius: NookDesign.Radius.lg))`.

- [ ] **Step 5: Fix the dialog `.conditionally` call and delete the helper file**

In `Nook/Managers/DialogManager/DialogManager.swift` around line 294, the pattern is:

```swift
.conditionally(if: OSVersion.supportsGlassEffect) { View in
    View
        .tint(Color("plainBackgroundColor").opacity(colorScheme == .light ? 0.8 : 0.4))
        ...
}
```

The condition is always true on macOS 26. Unwrap it: delete the `.conditionally(if: OSVersion.supportsGlassEffect) { View in` line and its closing `}`, and apply the inner modifiers directly to the preceding view (keeping the same indentation chain). Then:

```bash
cd /Users/bain/git/Nook && git rm -q UI/ConditionalModifiers.swift && grep -rn "conditionally(\|OSVersion\.\|SpaceListItemButtonStyle\|URLBarButtonStyle\|[^t]NavButtonStyle(" --include='*.swift' Navigation Nook UI CommandPalette App ; echo "grep exit $? (1 means clean)"
```

Expected: no output lines, `grep exit 1`.

- [ ] **Step 6: Build**

Run the build command. Expected: no `error:` lines, `exit 0`.

- [ ] **Step 7: Commit**

```bash
cd /Users/bain/git/Nook && git add -A UI Navigation Nook && git commit -m "refactor(ui): one NookIconButtonStyle, delete ConditionalModifiers

AI-assisted: implemented with Claude Code."
```

---

### Task 3: Radius sweep

**Files:**
- Modify: every file in scope that matches `cornerRadius:` or `.cornerRadius(`. Current list (36 files):
  `CommandPalette/CommandPalette Accessories/CommandPaletteSuggestionView.swift`, `.../GenericSuggestionItem.swift`, `.../HistorySuggestionItem.swift`, `.../TabSuggestionItem.swift`, `CommandPalette/CommandPaletteView.swift`, `Navigation/Sidebar/SpacesList/SpacesListItem.swift`, `Nook/Components/Browser/Window/SplitCardView.swift`, `Nook/Components/DragDrop/NookDragPreviewWindow.swift`, `Nook/Components/Extensions/ExtensionActionView.swift`, `Nook/Components/Extensions/ExtensionLibraryMoreMenu.swift`, `Nook/Components/Extensions/ExtensionLibraryView.swift`, `Nook/Components/FindBar/FindBarView.swift`, `Nook/Components/MiniWindow/MiniWindowToolbar.swift`, `Nook/Components/Peek/PeekOverlayView.swift`, `Nook/Components/PulseTextField/PulseTextField.swift`, `Nook/Components/Settings/CacheDetailsView.swift`, `.../CacheManagementView.swift`, `.../CookieDetailsView.swift`, `.../CookieManagementView.swift`, `.../ProfilePickerView.swift`, `.../ProfileRowView.swift`, `.../SettingsView.swift`, `.../SettingsWindow.swift`, `.../ShortcutRecorderView.swift`, `.../Tabs/AI.swift`, `.../Tabs/AdBlocker.swift`, `Nook/Components/Sidebar/AIChat/AISidebarResizeView.swift`, `.../AIChat/SidebarAIChat.swift`, `.../CopyURLToast/CopyURLToast.swift`, `.../MediaControls/MediaControlsView.swift`, `.../Menu/SidebarMenuDownloadsHover.swift`, `.../Menu/SidebarMenuDownloadsTab.swift`, `.../Menu/SidebarMenuHistoryTab.swift`, plus the remaining files the grep in Step 1 lists (the list above is the first 36; the grep is authoritative).

**Interfaces:**
- Consumes: `NookDesign.Radius.{xs,sm,md,lg,xl,xxl}`, `NookDesign.Radius.shape(_:)`.

- [ ] **Step 1: List the work**

```bash
cd /Users/bain/git/Nook && grep -rnE "cornerRadius: ?[0-9.]+|\.cornerRadius\([0-9.]+\)|cornerRadius: ?[a-zA-Z]" --include='*.swift' Navigation Nook/Components UI CommandPalette Nook/Managers/DialogManager | grep -v "Nook/Components/ColorPicker/" | grep -v "EmojiPicker.swift" | grep -v "NookDesign.swift"
```

- [ ] **Step 2: Apply the snap table to every hit**

| Literal | Token |
|---|---|
| 1, 3, 4, 5 | `NookDesign.Radius.xs` |
| 6, 7 | `NookDesign.Radius.sm` |
| 8, 9, 10 | `NookDesign.Radius.md` |
| 12, 14 | `NookDesign.Radius.lg` |
| 16 | `NookDesign.Radius.xl` |
| 24, 26 | `NookDesign.Radius.xxl` |
| 100, 999 | `Capsule()` (replace the whole shape expression) |

Rewrite forms:
- `RoundedRectangle(cornerRadius: N)` and `RoundedRectangle(cornerRadius: N, style: .continuous)` → `NookDesign.Radius.shape(NookDesign.Radius.<token>)`
- `.cornerRadius(N)` → `.clipShape(NookDesign.Radius.shape(NookDesign.Radius.<token>))`
- `.clipShape(.rect(cornerRadius: N))` → `.clipShape(NookDesign.Radius.shape(NookDesign.Radius.<token>))`
- `UnevenRoundedRectangle(topLeadingRadius: N, ...)` keeps its type; replace each numeric argument with the token and add `style: .continuous` if absent.
- A `private let cornerRadius: CGFloat = N` or a computed `var cornerRadius` in a view: keep the property, set it to the token, and add `style: .continuous` wherever it is used in a `RoundedRectangle`. This includes `PinnedTabsConfiguration.cornerRadius` in `Settings/NookSettingsService.swift`: leave that enum alone (Phase 2 deletes it) but make sure `PinnedTabView.swift` keeps `style: .continuous`.
- `DialogCard` in `DialogManager.swift` (radius 12) → `NookDesign.Radius.xl` (the spec moves dialogs to 16; do it now since this file is being touched).
- `CommandPaletteView.swift` radius 26 → `NookDesign.Radius.xxl`.
- `ToastView.swift` radius 16 → `NookDesign.Radius.xl`.
- `SidebarHoverOverlayView.swift` radius 12 → `NookDesign.Radius.lg`.

- [ ] **Step 3: Verify nothing literal remains**

```bash
cd /Users/bain/git/Nook && grep -rnE "cornerRadius: ?[0-9.]+|\.cornerRadius\([0-9.]+\)|RoundedRectangle\(cornerRadius: [^,)]+\)" --include='*.swift' Navigation Nook/Components UI CommandPalette Nook/Managers/DialogManager | grep -v "Nook/Components/ColorPicker/" | grep -v "EmojiPicker.swift" | grep -v "NookDesign.swift" ; echo "grep exit $? (1 means clean)"
```

Expected: no output, `grep exit 1`. The third pattern catches any `RoundedRectangle(cornerRadius: x)` that lacks `style: .continuous`; every remaining `RoundedRectangle` must go through `Radius.shape`.

- [ ] **Step 4: Build**

Run the build command. Expected: no `error:` lines, `exit 0`.

- [ ] **Step 5: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Navigation Nook UI CommandPalette && git commit -m "refactor(ui): radius sweep to NookDesign.Radius, continuous corners everywhere

AI-assisted: implemented with Claude Code."
```

---

### Task 4: Font sweep

**Files:**
- Modify: every file in scope matching `.font(.system(size:` (59 files at time of writing; grep is authoritative).

**Interfaces:**
- Consumes: `NookDesign.Font.*` roles from Task 1.

- [ ] **Step 1: List the work**

```bash
cd /Users/bain/git/Nook && grep -rnE "\.font\(\.system\(size:" --include='*.swift' Navigation Nook/Components UI CommandPalette Nook/Managers/DialogManager | grep -v "Nook/Components/ColorPicker/" | grep -v "EmojiPicker.swift"
```

- [ ] **Step 2: Apply the role table**

Match on size first, then weight. `design: .monospaced` variants keep their design: use `NookDesign.Font.<role>.monospaced()`.

| Size | Weight | Role |
|---|---|---|
| 8, 9, 10 | any | `caption` (use `micro` only for a numeric badge overlay on an icon) |
| 11 | semibold, bold | `captionStrong` |
| 11 | other | `caption` |
| 12, 12.5 | any | `secondary` |
| 13 | semibold, bold | `label` |
| 13 | regular, light | `bodyRegular` |
| 13 | medium or unspecified | `body` |
| 14 | semibold, bold | `label` |
| 14 | regular, light | `bodyRegular` |
| 14 | medium or unspecified | `body` |
| 15, 16 | any | `title` |
| 17, 18 | any | `heading` |
| 20, 24, 25 | any | `titleLarge` |
| 28, 32 | any | `display` |
| 48 | any | `hero` |

Rewrite `.font(.system(size: N, weight: .w))` → `.font(NookDesign.Font.<role>)`. If the call site is `Image(systemName:)` and the size drives the glyph size rather than text, keep the mapping anyway; the role sizes are within 1pt of the originals except 14→13 and 16→15, which is intended.

Two hits show `size: .` (a variable, e.g. `size: fontSize`) and one shows `size: 1048576`; leave any `size:` that is not inside `.font(.system(` alone. Those are frame or image arguments, not fonts.

- [ ] **Step 3: Verify**

```bash
cd /Users/bain/git/Nook && grep -rnE "\.font\(\.system\(size: ?[0-9]" --include='*.swift' Navigation Nook/Components UI CommandPalette Nook/Managers/DialogManager | grep -v "Nook/Components/ColorPicker/" | grep -v "EmojiPicker.swift" ; echo "grep exit $? (1 means clean)"
```

Expected: no output, `grep exit 1`.

- [ ] **Step 4: Build**

Run the build command. Expected: no `error:` lines, `exit 0`.

- [ ] **Step 5: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Navigation Nook UI CommandPalette && git commit -m "refactor(ui): font sweep to NookDesign.Font roles

AI-assisted: implemented with Claude Code."
```

---

### Task 5: Motion sweep

**Files:**
- Modify: every file in scope matching an animation literal (50 files at time of writing).

**Interfaces:**
- Consumes: `NookDesign.Motion.{quick,standard,spring}`.

- [ ] **Step 1: List the work**

```bash
cd /Users/bain/git/Nook && grep -rnE "\.(easeInOut|easeOut|easeIn|linear|smooth|spring|bouncy|snappy|interactiveSpring|interpolatingSpring)\(" --include='*.swift' Navigation Nook/Components UI CommandPalette Nook/Managers/DialogManager | grep -v "Nook/Components/ColorPicker/" | grep -v "EmojiPicker.swift" | grep -v "NookDesign.swift"
```

- [ ] **Step 2: Apply the mapping**

| Literal | Token |
|---|---|
| `.easeInOut / .easeOut / .easeIn / .linear` with duration ≤ 0.15 | `NookDesign.Motion.quick` |
| `.easeInOut / .easeOut / .easeIn / .linear` with duration > 0.15, or `.smooth(...)` | `NookDesign.Motion.standard` |
| `.spring(...)`, `.bouncy(...)`, `.snappy(...)`, `.interactiveSpring(...)`, `.interpolatingSpring(...)` | `NookDesign.Motion.spring` |
| bare `.easeInOut` / `.easeOut` / `.easeIn` / `.linear` / `.spring` / `.smooth` with no parentheses | same rule by family: ease → `standard`, spring → `spring` |

Applies inside `.animation(_, value:)`, `withAnimation(_) { }`, `.transition(.x.animation(_))`, and `Animation` stored properties. Keep `.repeatForever` / `.delay` chains: `NookDesign.Motion.standard.repeatForever(autoreverses: true)`. A `.linear` used for a progress bar or spinner (continuous motion, not a UI state change) is the one exception: keep it, but move its duration out to a `private let` in that file and leave a comment `// continuous motion, not a state transition`.

- [ ] **Step 3: Verify**

```bash
cd /Users/bain/git/Nook && grep -rnE "\.(easeInOut|easeOut|easeIn|smooth|spring|bouncy|snappy|interactiveSpring|interpolatingSpring)\(" --include='*.swift' Navigation Nook/Components UI CommandPalette Nook/Managers/DialogManager | grep -v "Nook/Components/ColorPicker/" | grep -v "EmojiPicker.swift" | grep -v "NookDesign.swift" ; echo "grep exit $? (1 means clean)"
```

Expected: no output, `grep exit 1`. `.linear(` is deliberately excluded from the check for the spinner exception; confirm by eye that each remaining `.linear(` has the comment.

- [ ] **Step 4: Build**

Run the build command. Expected: no `error:` lines, `exit 0`.

- [ ] **Step 5: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Navigation Nook UI CommandPalette && git commit -m "refactor(ui): animation sweep to NookDesign.Motion

AI-assisted: implemented with Claude Code."
```

---

### Task 6: Elevation sweep

**Files:**
- Modify: `Nook/Components/Sidebar/SpaceSection/SpaceView.swift`, `Nook/Components/Sidebar/SpaceSection/SpaceTab.swift`, `Nook/Components/Sidebar/PinnedButtons/PinnedTabView.swift`, `Nook/Components/FindBar/FindBarView.swift`, `Nook/Components/Toast/ToastView.swift`, `Nook/Components/MiniWindow/MiniWindowButtonStyle.swift`, `Nook/Components/MiniWindow/MiniWindowToolbar.swift`, `Nook/Components/DragDrop/NookDragPreviewWindow.swift`, `Nook/Components/ZoomControls/ZoomPopupView.swift`, `Nook/Components/WebsiteView/WebsiteView.swift`, `Nook/Components/WebsiteView/EmptyWebsiteView.swift`, `Nook/Components/Peek/PeekOverlayView.swift`, `Nook/Managers/DialogManager/DialogManager.swift`

**Interfaces:**
- Consumes: `View.nookElevation(.raised)`, `View.nookElevation(.floating)`.

- [ ] **Step 1: List the work**

```bash
cd /Users/bain/git/Nook && grep -rnE "\.shadow\(" --include='*.swift' Navigation Nook/Components UI CommandPalette Nook/Managers/DialogManager | grep -v "Nook/Components/ColorPicker/" | grep -v "NookDesign.swift"
```

- [ ] **Step 2: Apply the mapping**

| Shadow | Replacement |
|---|---|
| radius ≤ 4 (active tab, tile, small chips) | `.nookElevation(.raised)` |
| radius > 4 (toast, find bar, dialog, peek, drag preview, zoom popup, mini window) | `.nookElevation(.floating)` |
| `.shadow(color: .clear, ...)` or `.shadow(radius: 0)` | delete the modifier |
| shadow guarded by `colorScheme == .light ? ... : .clear` | drop the guard, apply the token unconditionally |

`WebsiteView.swift` draws a shadow on the web content frame; keep that one as `.nookElevation(.raised)`.

- [ ] **Step 3: Verify**

```bash
cd /Users/bain/git/Nook && grep -rnE "\.shadow\(" --include='*.swift' Navigation Nook/Components UI CommandPalette Nook/Managers/DialogManager | grep -v "Nook/Components/ColorPicker/" | grep -v "NookDesign.swift" ; echo "grep exit $? (1 means clean)"
```

Expected: no output, `grep exit 1`.

- [ ] **Step 4: Build**

Run the build command. Expected: no `error:` lines, `exit 0`.

- [ ] **Step 5: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Navigation Nook UI CommandPalette && git commit -m "refactor(ui): shadow sweep to nookElevation

AI-assisted: implemented with Claude Code."
```

---

### Task 7: Phase gate

- [ ] **Step 1: Full literal audit**

```bash
cd /Users/bain/git/Nook && S="Navigation Nook/Components UI CommandPalette Nook/Managers/DialogManager"; X='Nook/Components/ColorPicker/|EmojiPicker.swift|NookDesign.swift'; \
echo "radius: $(grep -rnE 'cornerRadius: ?[0-9]|\.cornerRadius\([0-9]' --include='*.swift' $S | grep -vE "$X" | wc -l)"; \
echo "font:   $(grep -rnE '\.font\(\.system\(size: ?[0-9]' --include='*.swift' $S | grep -vE "$X" | wc -l)"; \
echo "anim:   $(grep -rnE '\.(easeInOut|easeOut|easeIn|smooth|spring|bouncy|snappy)\(' --include='*.swift' $S | grep -vE "$X" | wc -l)"; \
echo "shadow: $(grep -rnE '\.shadow\(' --include='*.swift' $S | grep -vE "$X" | wc -l)"
```

Expected: all four counts are `0`.

- [ ] **Step 2: Build and run the manual checklist**

Run the build command, then open the app from `build/Build/Products/Debug/Nook.app` and check: light and dark appearance; sidebar left and right; top bar address mode on and off; two windows on the same space; drag a tab between spaces and into a folder; hide the sidebar and use the hover overlay; open a split view; open the command palette, a dialog, and a toast. Expected: everything works as before, corners are continuous, nothing is visibly larger or smaller than before by more than a pixel or two.

- [ ] **Step 3: Record**

Append one line to `docs/superpowers/specs/2026-09-14-gui-remodel-design.md` under `## Phases`, item 1: `Done <date>, <commit range>.` Commit:

```bash
cd /Users/bain/git/Nook && git add docs/superpowers/specs/2026-09-14-gui-remodel-design.md && git commit -m "docs: mark GUI remodel phase 1 done

AI-assisted: implemented with Claude Code."
```
