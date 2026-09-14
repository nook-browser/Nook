# GUI Remodel: Design Spec

Date: 2026-09-14
Status: approved
Design canvas: https://claude.ai/code/artifact/c02bed25-93d0-4f60-9dfe-884ef2df0d08

## Goal

Make Nook's chrome feel refined and native on macOS 26: a neutral sidebar surface, continuous (squircle) corners everywhere, one token file that every view reads from, Liquid Glass only on layers that float over content, and native grouped settings. The visual reference is the design canvas above; the numbers below are the source of truth where the two disagree.

## Non-goals

- Onboarding screens (one-time, own Metal transitions). Untouched.
- Web content area, top bar address mode layout (tokens apply, no redesign).
- Any behavior change to tabs, spaces, drag-drop, persistence, or extensions.
- iOS. Token file stays AppKit-free where that costs nothing.

## 1. Token file

`Nook/Design/NookDesign.swift`. One `enum NookDesign` with nested namespaces. No other file in the UI layer may contain a literal corner radius, font size, shadow, or animation duration after the sweep.

```swift
enum NookDesign {
    enum Radius {  // all continuous
        static let xs: CGFloat = 4    // favicon
        static let sm: CGFloat = 6    // icon button, menu item
        static let md: CGFloat = 8    // tab row, nav button, URL bar
        static let lg: CGFloat = 12   // essentials tile, card, settings group
        static let xl: CGFloat = 16   // dialog, toast
        static let xxl: CGFloat = 24  // command palette
        static func shape(_ r: CGFloat) -> RoundedRectangle  // .continuous
    }
    enum Spacing {
        static let xxs: CGFloat = 2, xs = 4, sm = 6, md = 8, lg = 12, xl = 16, xxl = 20, xxxl = 24
        static let sidebarInset: CGFloat = 8
        static let rowGap: CGFloat = 2
        static let sectionGap: CGFloat = 10
        static let rowPadding: CGFloat = 8
        static let folderIndent: CGFloat = 20
    }
    enum Size {
        static let row: CGFloat = 32
        static let iconButton: CGFloat = 28
        static let favicon: CGFloat = 16
        static let essentialsTile: CGFloat = 44
        static let urlBar: CGFloat = 32
        static let navRow: CGFloat = 28
        static let bottomBar: CGFloat = 40
    }
    enum Font {
        static let heading = Font.system(size: 17, weight: .semibold)   // pane title, dialog title
        static let title = Font.system(size: 15, weight: .semibold)     // palette input, toast title
        static let label = Font.system(size: 13, weight: .semibold)     // space name, folder name
        static let body = Font.system(size: 13, weight: .medium)        // tab title, menu item, settings row
        static let secondary = Font.system(size: 12, weight: .medium)   // URL bar, popup button
        static let caption = Font.system(size: 11, weight: .medium)     // counts, shortcuts, subtitles
        static let captionStrong = Font.system(size: 11, weight: .semibold) // section headers
    }
    enum Motion {
        static let quick = Animation.easeOut(duration: 0.12)      // hover, press
        static let standard = Animation.smooth(duration: 0.22)    // selection, reveal, fold
        static let spring = Animation.snappy(duration: 0.3)       // palette, dialog, toast, drag reorder, gesture-tracked motion
    }
    enum Surface {
        static let fill = Color.primary.opacity(0.045)      // hover, URL bar, tile idle
        static let fillPressed = Color.primary.opacity(0.08)
        static let hairline = Color.primary.opacity(0.08)
        static let raised = Color(nsColor: .controlBackgroundColor)  // active row, active tile
        // sidebar surface is BlurEffectView(material: .sidebar), not a Color
    }
    enum Elevation {  // View modifier .nookElevation(_:), branch-free so identity is stable
        case flat      // no shadow; for conditional elevation (isActive ? .raised : .flat)
        case raised    // shadow(0.05, r2, y1)
        case floating  // shadow(0.16, r32, y12) + shadow(0.06, r2, y1)
    }
}
```

Text colors are `.primary`, `.secondary`, `.tertiary`. No custom text colors in the sidebar.

`AppColors` keeps `Color(hex:)`, `toHexString`, `perceivedBrightness`, `isPerceivedDark`, and the four system role colors. The fourteen semantic pairs (`spaceTab*`, `pinnedTab*`, `sidebarText*`, `iconActive*`, `controlBackground*`) are deleted.

## 2. Sweep

Scope: `Navigation/`, `Nook/Components/`, `UI/`, `CommandPalette/`, `Nook/Managers/DialogManager/`, `Nook/Components/Settings/`.

- Every `RoundedRectangle(cornerRadius:)` and `.cornerRadius()` becomes `NookDesign.Radius.shape(...)`. Radius values snap to the nearest token; 100/999 become `Capsule()`.
- Every `.font(.system(size:))` maps to a `NookDesign.Font` role.
- Every `.animation` / `withAnimation` literal maps to a `Motion` curve.
- Every `.shadow` becomes `.nookElevation`.
- `NavButtonStyle`, `SpaceListItemButtonStyle`, `URLBarButtonStyle` collapse into one `NookIconButtonStyle(size:)` in `UI/Buttons/`. `RectNavButtonStyle` stays as the labeled variant.
- `View+GlassEffect.swift` is the only glass entry point. `.ultraThinMaterial`, `BlurEffectView(.headerView)`, `BlurEffectView(.hudWindow)`, and hand-built `NSVisualEffectView` instances in CommandPalette and the extension panels are replaced (see section 6). `BlurEffectView` survives only for the sidebar material.
- `ConditionalModifiers.swift` and `OSVersion.supportsGlassEffect` are deleted (the target is 26).

## 3. Surface and accent

- `WindowView` no longer composites `SpaceGradientBackgroundView` over a blur. The window background is `BlurEffectView(material: .sidebar, blendingMode: .behindWindow)`. The web view area is opaque and unaffected.
- `Space` keeps a single accent color. Storage: the existing `SpaceGradient` persists unchanged; `GradientColorManager` is renamed `SpaceAccent` in spirit but keeps its type name for the diff, and exposes only `accentColor` (today's `primaryColor`) plus the transition animation. `displayGradient` and `isDark` are removed.
- Accent is applied to: space icon in the header, active space item in the switcher, folder icons, rename focus ring. Nowhere else.
- Deleted: `BarycentricGradientView`, `BarycentricShaders.metal`, `SpaceGradientBackgroundView`, `Nook/Components/ColorPicker/` (gradient editor). The space edit and creation dialogs get a swatch row (eight preset accents) plus a `ColorPicker` for custom. `SpaceGradient` is written as a single-node gradient from the chosen color so old persisted data keeps loading.
- All `gradientColorManager.isDark` and `colorScheme == .dark ? light : dark` branching in the sidebar is removed. System colors and the sidebar material adapt on their own.

## 4. Space icons

- `Space.icon` stays a `String`. New values are SF Symbol names. Rendering: if `NSImage(systemSymbolName:)` resolves, draw `Image(systemName:)` tinted with the accent; otherwise draw `Text(icon)` so existing emoji values still render after upgrade.
- `EmojiPicker.swift` is deleted. Replacement: `SpaceIconPicker`, a grid of ~48 curated symbols (work, home, star, book, cart, gamecontroller, music, film, briefcase, graduationcap, heart, leaf, flame, bolt, globe, code, terminal, hammer, wrench, paintbrush, camera, photo, map, airplane, car, house, building, person, people, envelope, message, phone, calendar, clock, folder, tray, doc, note, chart, dollar, creditcard, tag, bookmark, flag, pin, bell, gear, sparkles). Default for new spaces: `square.grid.2x2`.
- Space switcher items show the symbol at 14pt, `.tertiary` when inactive, accent when active with a `Surface.fill` background.

## 5. Sidebar

Container padding: 34pt top (left position, clears traffic lights), 8pt sides, 10pt between sections.

- **Nav row**: 28pt tall. Sidebar toggle at leading, then spacer, then back / forward / reload. Icon buttons are `Size.iconButton` square, `Radius.md`, `.secondary` tint, disabled state `.tertiary`.
- **URL bar**: 32pt, `Radius.md`, `Surface.fill` background, hover to `fillPressed`. 13pt lock/globe icon, then host in `.primary` and path in `.tertiary`, `Font.secondary`. Loading progress bar stays, clipped to the same shape.
- **Essentials**: `LazyVGrid`, four columns, 6pt gap, tiles `Size.essentialsTile` tall, `Radius.lg`. Idle `Surface.fill`; active `Surface.raised` + `.raised` elevation. Favicon 20pt. The `PinnedTabsConfiguration` setting and its UI are deleted; one size.
- **Space header**: 28pt. Symbol 14pt in accent, name in `Font.label`, spacer, ellipsis icon button visible on hover only.
- **Tab row**: `Size.row` tall, `Radius.md`, `Spacing.rowGap` between rows, `Spacing.rowPadding` horizontal, 8pt favicon-to-title gap. Favicon `Size.favicon` clipped to `Radius.xs`. Title `Font.body`, `.primary`, single line, tail truncation. States: hover `Surface.fill`; active `Surface.raised` + `.raised` elevation (padding drops to 7 to absorb the 1pt hairline); unloaded whole row at 55% opacity; audio shows a 13pt speaker icon after the favicon, `.secondary`, click toggles mute; close button 20pt `Radius.sm` appears on row hover only; rename is an inline text field with no box, row shows `raised` with a 1pt accent stroke.
- **Folder row**: chevron 12pt `.tertiary` (rotates 90 on open, `Motion.standard`), folder symbol 15pt in accent, name `Font.label`, trailing child count in `Font.caption` `.tertiary`. Children indent by `Spacing.folderIndent`.
- **Separator** between pinned and regular tabs: hairline with 8pt side margins; Clear and Organize appear on hover at the trailing end in `Font.caption` `.tertiary`.
- **New Tab row**: same geometry as a tab row, plus icon and label in `.tertiary`, hover shows fill and the ⌘T hint at the trailing end.
- **Bottom bar**: 40pt. Menu icon button leading, space switcher centered (items 28pt square, 2pt gap), plus icon button trailing.
- **Hover sidebar overlay** (sidebar hidden): same content, wrapped in glass at `Radius.lg` with 7pt insets, `.floating` elevation.

Context menus: three shared `@ViewBuilder` builders, `TabContextMenu`, `FolderContextMenu`, `SpaceContextMenu`, in `Nook/Components/Sidebar/ContextMenus/`. `SpaceTab`, `SplitTabRow`, `PinnedGrid` use `TabContextMenu`; `SpacesListItem` and `SpaceTitle` use `SpaceContextMenu`. Item order for tabs: Pin, Move to Space (submenu, current space checked, New Space at the bottom) / Rename, Duplicate, Copy Link, Open in Split View / Mute, Unload / Close Tab, Close Other Tabs. Every item has an SF Symbol. Menus stay native `.contextMenu`; macOS 26 renders them as glass.

## 6. Glass layer

`nookGlassEffect(in:)` is used for, and only for: command palette (`Radius.xxl`), toasts (`Radius.xl`), hover sidebar overlay (`Radius.lg`), find bar (`Capsule`), dialog cards (`Radius.xl`), extension library panel and its more-menu (`Radius.lg`). Each gets `.floating` elevation. Dialog presentation stays the in-window ZStack overlay with the 0.4 black scrim; the transition uses `Motion.spring`. `DialogCard` loses its stroke and shadow literals.

## 7. Settings

- Window becomes a SwiftUI `Settings` scene. The `openWindow` call in `NookCommands` is replaced by the system Settings command (Cmd-comma comes free).
- `SettingsWindow` keeps `NavigationSplitView`, sidebar rows 28pt `Radius.sm`, tinted 22pt chips at `Radius.sm`.
- Every tab is `Form { Section("...") { ... } }.formStyle(.grouped)`. Rows use `LabeledContent`, `Toggle`, `Picker` with `.menu` or `.segmented` style. Custom row structs are deleted where a standard control covers them; `ProfileRowView`, `ShortcutRecorderView`, and the extension row keep custom bodies but live inside grouped sections.
- `SettingsView.swift` splits into `Tabs/Profiles.swift`, `Tabs/Shortcuts.swift`, `Tabs/Extensions.swift`, `Tabs/Advanced.swift`, `Tabs/SiteSearch.swift`. `SettingsTabs` enum and `SettingsUtils.swift` are unchanged.

## Phases

Each phase is one commit on `main` that builds with `xcodebuild -scheme Nook -configuration Debug -arch arm64` and passes the manual checklist below.

1. **Tokens and sweep.** Add `NookDesign.swift`, replace literals, collapse button styles, delete `ConditionalModifiers`. Visual change is whatever the tokens define: continuous corners, snapped radii, 28pt icon buttons, new hover fill, elevation scale, type roles. Done 2026-09-14, commits 206859b..197ba61 on `gui-remodel`.
2. **Surface and accent.** Gradient off, sidebar material on, `GradientColorManager` reduced to accent, gradient editor replaced by swatches, space icons to symbols with emoji fallback, `EmojiPicker` deleted. Incognito windows use a neutral gray accent. Done 2026-09-14, commits d5b2363..c2866a8 on `gui-remodel-p2`.
3. **Sidebar and menus.** Rows, essentials, header, URL bar, nav row, bottom bar, folders, separator, new tab row rebuilt to section 5. Context menus extracted.
4. **Glass layer.** Section 6.
5. **Settings.** Section 7.

## Manual checklist (every phase)

Light and dark appearance. Sidebar left and right. Top bar address mode on and off. Two windows open on the same space. Drag a tab between spaces and into a folder. Hide the sidebar and use the hover overlay. Open a split view. Open the command palette, a dialog, and trigger a toast. Quit and relaunch: spaces, icons, and accents persist.
