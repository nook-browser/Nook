# GUI Remodel Phases 4 and 5: Glass Layer and Settings

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development. The two tracks below are independent and run in parallel in separate git worktrees; each track is one task with its own review.

**Goal:** Track A puts every floating layer on one Liquid Glass entry point and removes the competing blur recipes. Track B turns every settings tab into a native grouped Form, splits the 1100-line settings file, and moves the window to the Settings scene.

**Architecture:** Track A: `View+GlassEffect.swift` is the only glass entry point; `BlurEffectView` survives only as the window background in `WindowView`. Floating layers (command palette, toasts, hover sidebar overlay, find bar, dialog cards, extension library panel and its more-menu, split card preview) get `nookGlassEffect(in:)` at their token radius plus `.nookElevation(.floating)`. Track B: `NookApp` declares a `Settings` scene; `SettingsWindow` keeps its `NavigationSplitView`; each tab is a `Form` with `Section`s in `.formStyle(.grouped)`; `SettingsView.swift` splits into one file per tab under `Tabs/`.

**Tech Stack:** Swift 5, SwiftUI, AppKit, macOS 26 SDK. No test target; verification is grep assertions plus a Debug build and a manual pass.

**Spec:** `docs/superpowers/specs/2026-09-14-gui-remodel-design.md` sections 6 and 7.

## Global Constraints

- Deployment target macOS 26.0. Swift language mode 5. No `#available` guards below 26.
- Build command (zsh, 600000 ms timeout), run in the track's own worktree with its own derived data:
  ```bash
  xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath <worktree>-dd CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | grep -E "^[^ ]+:[0-9]+:[0-9]+: error:|BUILD" ; echo "exit $pipestatus[1]"
  ```
  Expected: no diagnostic `error:` lines and `exit 0`.
- Every radius, font, animation, shadow, fill, padding, and spacing in touched files reads from `NookDesign` (`Nook/Design/NookDesign.swift`). Add a token only when nothing fits, and name it in the report.
- Text colors `.primary/.secondary/.tertiary`; fills `NookDesign.Surface.*`.
- Track A must not touch `Nook/Components/Settings/`, `Settings/`, `App/NookApp.swift`, `App/NookCommands.swift`. Track B must not touch anything outside `Nook/Components/Settings/`, `Settings/NookSettingsService.swift`, `App/NookApp.swift`, `App/NookCommands.swift`, and `Nook/Design/NookDesign.swift` (tokens only). Neither touches `Onboarding/` or `Nook/ThirdParty/`.
- Behavior preservation: every setting, dialog, palette, toast, find, and extension panel action works as before. Persisted settings keys are unchanged.
- Xcode uses filesystem-synchronized groups; new or moved files need no project edits (except a stale `membershipExceptions` line if `git mv` collides, as happened in Phase 3).
- Commit messages end with the line `AI-assisted: implemented with Claude Code.`

---

### Track A (Phase 4): Glass layer

**Worktree:** `/private/tmp/claude-501/nook-p4`, branch `gui-remodel-p4` from `main`.

**Files:**
- Modify: `Nook/Extensions/View+GlassEffect.swift`, `Nook/Managers/DialogManager/DialogManager.swift` (`DialogCard`, `DialogHeader`), `Nook/Components/Dialog/DialogView.swift`, `CommandPalette/CommandPaletteView.swift`, `Nook/Components/Toast/ToastView.swift`, `Nook/Components/Sidebar/SidebarHoverOverlayView.swift`, `Nook/Components/FindBar/FindBarView.swift`, `Nook/Components/Extensions/ExtensionLibraryPanel.swift`, `Nook/Components/Extensions/ExtensionLibraryMoreMenu.swift`, `Nook/Components/Browser/Window/SplitCardView.swift`, `Nook/Components/WebsiteView/WebsiteView.swift`, `Nook/Components/WebsiteView/PageLoadingProgressBar.swift`, `Nook/Components/Sidebar/AIChat/SidebarAIChat.swift`
- Delete if unused afterwards: nothing (keep `Nook/Utils/BlurEffectView.swift` for `WindowView`).

**Requirements:**

1. `View+GlassEffect.swift` becomes the single entry point:
   ```swift
   extension View {
       /// Liquid Glass for a layer that floats over content. Never for the sidebar or rows.
       func nookGlassEffect<S: Shape>(in shape: S) -> some View {
           self.glassEffect(.regular, in: shape).nookElevation(.floating)
       }
       func nookClearGlassEffect(tint: Color) -> some View {
           self.glassEffect(.regular.tint(tint), in: .circle)
       }
   }
   ```
   Call sites that already add `.nookElevation(.floating)` next to `nookGlassEffect` drop the duplicate.
2. Floating layers use it at these shapes: command palette `Radius.xxl`; toasts (`ToastView`, `CopyURLToast` if it has its own chrome) `Radius.xl`; hover sidebar overlay `Radius.lg`; find bar `Capsule()`; `DialogCard` `Radius.xl`; extension library panel and more-menu `Radius.lg`; `SplitCardView` `Radius.lg`.
3. Competing recipes removed at those sites: `BlurEffectView(material: .headerView ...)` in `DialogCard`; the hand-built `NSVisualEffectView` wrapper near the bottom of `CommandPaletteView.swift`; `BlurEffectView` + clear glass `Rectangle` pair in `SidebarHoverOverlayView` (becomes one `nookGlassEffect` on the overlay's content); the `NSVisualEffectView` construction in `ExtensionLibraryPanel` and `ExtensionLibraryMoreMenu` (host the SwiftUI content in an `NSHostingView` whose root view carries `nookGlassEffect`, panel background clear, `layer?.cornerCurve` lines go with the visual effect view); `BlurEffectView(material: .hudWindow ...)` in `SplitCardView`.
4. `.ultraThinMaterial` / `.regularMaterial` / `.thinMaterial` in `WebsiteView.swift`, `PageLoadingProgressBar.swift`, `SidebarAIChat.swift`: classify each. A layer that floats over page or sidebar content becomes `nookGlassEffect(in:)` at the nearest token radius; a static surface becomes `NookDesign.Surface.fill` or `.raised`. Report each classification with file:line.
5. `DialogView.swift`: the presentation transition uses `NookDesign.Motion.spring` (replace whatever `.bouncy(duration: 0.2)`-derived token is there if it is not already `Motion.spring`); scrim stays `Color.black.opacity(0.4)` but the value moves to `NookDesign.Surface.scrim` (add the token: `static let scrim = Color.black.opacity(0.4)`).
6. `DialogCard` loses any remaining stroke/shadow modifiers other than the elevation the glass wrapper provides; padding and max width become tokens (`Spacing.xl` 16, and add `Size.dialogMaxWidth = 500`).
7. `DialogHeader`'s icon circle keeps `nookClearGlassEffect(tint:)`.

**Verification (Track A):**
```bash
cd /private/tmp/claude-501/nook-p4 && echo "BlurEffectView uses:"; grep -rn "BlurEffectView(" --include='*.swift' App Nook Navigation CommandPalette UI | grep -v "BlurEffectView.swift"; echo "raw materials:"; grep -rnE "ultraThinMaterial|regularMaterial|thinMaterial|NSVisualEffectView\(" --include='*.swift' Nook Navigation CommandPalette UI | grep -v "BlurEffectView.swift"; echo "glassEffect outside wrapper:"; grep -rn "\.glassEffect(" --include='*.swift' App Nook Navigation CommandPalette UI | grep -v "View+GlassEffect.swift"; echo "done"
```
Expected: exactly one `BlurEffectView(` use (in `App/Window/WindowView.swift`); no raw materials; no `.glassEffect(` outside the wrapper. Then the build command, green.

**Commit:** one commit, `feat(glass): one Liquid Glass entry point for every floating layer; blur recipes removed`.

---

### Track B (Phase 5): Settings

**Worktree:** `/private/tmp/claude-501/nook-p5`, branch `gui-remodel-p5` from `main`.

**Files:**
- Modify: `App/NookApp.swift` (scene), `App/NookCommands.swift` (settings command), `Nook/Components/Settings/SettingsWindow.swift`, `Nook/Components/Settings/SettingsUtils.swift` (only if a tab enum member needs it), every file under `Nook/Components/Settings/Tabs/`, `Nook/Components/Settings/PrivacySettingsView.swift`, `CacheManagementView.swift`, `CookieManagementView.swift`, `CacheDetailsView.swift`, `CookieDetailsView.swift`, `ShortcutRecorderView.swift`, `ProfilePickerView.swift`, `ProfileRowView.swift`
- Split: `Nook/Components/Settings/SettingsView.swift` → `Tabs/Profiles.swift`, `Tabs/Shortcuts.swift`, `Tabs/Extensions.swift`, `Tabs/Advanced.swift`, `Tabs/SiteSearch.swift`; delete `SettingsView.swift` when empty (or leave only a type that other code references, noted in the report).

**Requirements:**

1. `NookApp.swift`: replace `Window("Nook Settings", id: "nook-settings") { ... }` with `Settings { <same content> }` (same environment injection). `NookCommands.swift`: remove the custom command that called `openWindow(id: "nook-settings")`; the `Settings` scene supplies the standard Settings… item with ⌘,. Any other code path that opened the settings window by id (grep `nook-settings` and `openWindow`) switches to `@Environment(\.openSettings)` / `openSettings()`; if a path needs to land on a specific tab, keep using `nookSettings.currentSettingsTab` before calling `openSettings()`.
2. `SettingsWindow.swift`: keep `NavigationSplitView` and the fixed size; sidebar rows `Size.navRow` (28) tall with `Radius.sm`; the tinted icon chips `22pt` (add `Size.settingsChip = 22`) at `Radius.sm`; selection through the `List(selection:)` as today.
3. Every tab's root is `Form { Section("<Title>") { ... } ... }.formStyle(.grouped)`. Rows use `LabeledContent("Label") { control }` where a label-plus-control is needed, `Toggle("Label", isOn:)`, `Picker("Label", selection:)` with `.pickerStyle(.menu)` (default) or `.segmented` for two or three fixed choices. Descriptions under a row use `Text(...).font(NookDesign.Font.caption).foregroundStyle(.secondary)` inside the `LabeledContent` label or as the `Section` footer. No custom row structs where a standard control covers the case; `ProfileRowView`, `ShortcutRecorderView`, and the extension row keep their custom bodies but sit inside grouped `Section`s.
4. Tab files: `General.swift`, `Appearance.swift`, `AI.swift`, `AdBlocker.swift`, `SponsorBlock.swift`, `AirTrafficControlSettingsView.swift` (already under `Tabs/`), plus the five split out of `SettingsView.swift`. `PrivacySettingsView.swift` and the cache/cookie management views stay where they are but get the same Form treatment. Each tab file holds one `View` and its private helpers only.
5. Geometry and colors in these files read from `NookDesign`; `AppColors.*` semantic members are gone already, so only `textPrimary/Secondary/Tertiary` may remain (prefer `.primary/.secondary/.tertiary`).
6. Nothing about what a setting does changes. Every `nookSettings.<key>` binding present before is present after.

**Verification (Track B):**
```bash
cd /private/tmp/claude-501/nook-p5 && echo "window scene:"; grep -rn 'Window("Nook Settings"\|"nook-settings"' --include='*.swift' App Nook; echo "tabs without grouped form:"; for f in Nook/Components/Settings/Tabs/*.swift Nook/Components/Settings/PrivacySettingsView.swift Nook/Components/Settings/CacheManagementView.swift Nook/Components/Settings/CookieManagementView.swift; do grep -q "formStyle(.grouped)" "$f" || echo "$f"; done; echo "SettingsView.swift lines: $(wc -l < Nook/Components/Settings/SettingsView.swift 2>/dev/null || echo deleted)"; echo "raw geometry in Settings:"; grep -rnE "spacing: [0-9]|padding\([^)]*[0-9]|frame\([^)]*(height|width|minHeight|maxHeight|minWidth|maxWidth): [0-9]|cornerRadius: [0-9]|\.font\(\.system\(size: ?[0-9]" --include='*.swift' Nook/Components/Settings | grep -vE "NookDesign\.|: 0\)|: 1\)" | wc -l; echo "settings bindings before/after:"; git diff main --unified=0 -- Nook/Components/Settings Settings | grep -oE "^[-+].*\\\$?(settings|nookSettings)\.[a-zA-Z]+" | sed -E 's/^([-+]).*(settings|nookSettings)\.([a-zA-Z]+).*/\1 \3/' | sort | uniq -c | awk '$2=="-"{m[$3]=$1} $2=="+"{p[$3]=$1} END{for(k in m) if(!(k in p)) print "LOST binding:", k}'
```
Expected: no window-scene hits; no tab listed; `SettingsView.swift` deleted or under 60 lines; raw geometry `0`; no `LOST binding` lines (a key that appears in removed lines but never in added lines has been dropped; any hit must be explained in the report). Then the build command, green. Also open the built app once: Cmd-comma opens Settings, every tab renders.

**Commit:** one commit, `feat(settings): grouped Form settings, one file per tab, native Settings scene`.

---

### Gate (both tracks)

Merge Track A to main (fast-forward), rebase Track B onto main, merge, build main once, manual pass: open the palette, a dialog, a toast, the find bar, the extension library panel, hide the sidebar and hover its edge, open a split, then Cmd-comma and click through every settings tab in light and dark. Append `Done <date>, commits ...` for phases 4 and 5 in the spec and commit `docs: mark GUI remodel phases 4 and 5 done`.
