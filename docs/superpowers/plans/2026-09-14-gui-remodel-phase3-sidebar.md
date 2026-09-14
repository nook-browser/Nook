# GUI Remodel Phase 3: Sidebar and Menus

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the sidebar to the spec's section 5 geometry (32pt rows, 2pt gaps, 8pt insets, hover-only controls, accent-tinted space and folder icons) and collapse the eleven inline context menus into three shared builders.

**Architecture:** Every sidebar view reads its geometry from `NookDesign`; a handful of new tokens are added for values the sidebar needs that no token covers. Row views (`SpaceTab`, `SplitTabRow`, `TabFolderView`, the New Tab row) share one geometry: `Size.row` tall, `Radius.md`, `Spacing.rowPadding` sides, `Spacing.rowGap` between rows. Context menus become three `@ViewBuilder` structs in `Nook/Components/Sidebar/ContextMenus/`: `TabContextMenu(tab:context:)`, `FolderContextMenu(folder:)`, and the existing `SpaceContextMenu` (moved). Action closures move verbatim from the inline menus; nothing a menu could do before is lost.

**Tech Stack:** Swift 5, SwiftUI, AppKit, macOS 26 SDK. No test target; verification is grep assertions plus a Debug build and a manual pass.

**Spec:** `docs/superpowers/specs/2026-09-14-gui-remodel-design.md` section 5.

## Global Constraints

- Deployment target macOS 26.0. Swift language mode 5. No `#available` guards below 26.
- No test target. Build command (zsh, 600000 ms timeout):
  ```bash
  cd /Users/bain/git/Nook && xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build CODE_SIGN_IDENTITY="-" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO -quiet 2>&1 | grep -E "^[^ ]+:[0-9]+:[0-9]+: error:|BUILD" ; echo "exit $pipestatus[1]"
  ```
  Expected: no diagnostic `error:` lines and `exit 0`.
- Every radius, font, animation, shadow, fill, padding, spacing, and size in the sidebar reads from `NookDesign` (`Nook/Design/NookDesign.swift`). A number may appear at a call site only as a token. Tokens added in Task 1 are the only additions allowed; if a later task needs another, add it to `NookDesign.swift` in that task and name it in the report.
- Text colors are `.primary`, `.secondary`, `.tertiary`. Fills are `NookDesign.Surface.*`. Accent is `space.accentColor`.
- Behavior preservation: every context menu action available today stays available (it may move within the menu). Drag and drop, split view, rename, folders, pinning, and the drag session's cell caches keep working. The drag session's `itemCellSize`/`itemCellSpacing` caches must equal the rendered row height and gap.
- Do not edit `Onboarding/`, `Nook/ThirdParty/`, the top bar (`TopBarView.swift`), the AI chat sidebar, or the sidebar menu panels (`Nook/Components/Sidebar/Menu/`). Glass and dialogs are Phase 4; settings are Phase 5.
- Xcode uses filesystem-synchronized groups; creating or `git mv`-ing a file needs no project edits.
- Every commit message ends with the line `AI-assisted: implemented with Claude Code.`
- Do not run the app mid-task; the manual checklist runs once at the end.

---

### Task 1: Tokens, container, header, nav row, URL bar

**Files:**
- Modify: `Nook/Design/NookDesign.swift`
- Modify: `Navigation/Sidebar/SpacesSideBarView.swift:62-111,190-207,306-347`
- Modify: `Navigation/Sidebar/SidebarHeader.swift:19,44-48,58-85`
- Modify: `Nook/Components/Sidebar/NavButtonsView.swift:110-186`
- Modify: `Nook/Components/Sidebar/URLBarView.swift:21-107,125-127`
- Modify: `Nook/Components/Sidebar/SidebarHoverOverlayView.swift:18-20,56-57`

**Interfaces:**
- Produces new tokens: `NookDesign.Spacing.sidebarTop: CGFloat = 34`, `NookDesign.Size.rowGlyph: CGFloat = 13` (inline glyphs: audio speaker, URL lock, folder chevron), `NookDesign.Size.rowButton: CGFloat = 20` (close/unload button), `NookDesign.Spacing.titleFade: CGFloat = 20`. Later tasks consume these names exactly.

- [ ] **Step 1: Tokens**

In `NookDesign.swift`, `enum Spacing`, after `folderIndent` add:
```swift
        static let sidebarTop: CGFloat = 34     // clears the traffic lights when the sidebar is on the left
        static let titleFade: CGFloat = 20      // trailing fade on long row titles
```
In `enum Size`, after `spaceIcon` add:
```swift
        static let rowGlyph: CGFloat = 13       // inline glyphs in a row: audio, lock, chevron
        static let rowButton: CGFloat = 20      // hover-only close/unload button in a row
```

- [ ] **Step 2: Container**

In `SpacesSideBarView.swift`:
- L62 `VStack(spacing: 8)` → `VStack(spacing: NookDesign.Spacing.sectionGap)`.
- L79 `.frame(minHeight: 40)` → `.frame(minHeight: NookDesign.Size.bottomBar)`.
- L91-92 `.padding(.horizontal, 8).padding(.bottom, 8)` → `NookDesign.Spacing.sidebarInset` for both.
- L110 `.padding(.top, sidebarPosition == .left ? 30 : 8)` → `.padding(.top, nookSettings.sidebarPosition == .left ? NookDesign.Spacing.sidebarTop : NookDesign.Spacing.sidebarInset)` (keep whatever expression currently yields the position; only the numbers change). L111 `.padding(.bottom, 8)` → `NookDesign.Spacing.sidebarInset`.
- Empty state L190-207: `VStack(spacing: 16)` → `NookDesign.Spacing.xl`; inner `VStack(spacing: 8)` → `NookDesign.Spacing.md`.
- `makeSpaceView` L318-319: `.padding(.horizontal, 8).padding(.bottom, 8)` → `.padding(.horizontal, NookDesign.Spacing.sidebarInset).padding(.bottom, NookDesign.Spacing.sectionGap)`.

- [ ] **Step 3: Header and nav row**

In `SidebarHeader.swift`:
- L19 `VStack(spacing: 8)` → `NookDesign.Spacing.sectionGap`.
- L44-48 nav row: `HStack(spacing: 2)` → `NookDesign.Spacing.xxs`; `.padding(.horizontal, 8)` → `NookDesign.Spacing.sidebarInset`; `.frame(height: 30)` → `NookDesign.Size.navRow`.
- `SidebarWindowControlsView` L58-85: `HStack(spacing: 8)` → `NookDesign.Spacing.md`; `.frame(height: 28)` → `NookDesign.Size.navRow`.

In `NavButtonsView.swift`:
- L110 `HStack(spacing: 2)` → `NookDesign.Spacing.xxs`; L129 inner `HStack(spacing: 8)` → `NookDesign.Spacing.xxs` (the mockup has back/forward/reload touching, 2pt apart).
- The collapse thresholds at L102-104 (`215/180`, `200/165`, `195`) stay as they are: they are layout-mode breakpoints, not styling. Add the comment `// width breakpoints for collapsing nav buttons into the ellipsis menu` above them if absent.
- Disabled buttons (back/forward with no history) must render `.tertiary`: `NookIconButtonStyle` already applies `.opacity(0.3)` when disabled, which reads as tertiary; no change.

- [ ] **Step 4: URL bar**

In `URLBarView.swift`:
- L21 `HStack(spacing: 8)` → `NookDesign.Spacing.sm`.
- The URL text (L25-41): when a tab exists, render host and path separately:
  ```swift
                    HStack(spacing: NookDesign.Spacing.xs) {
                        Image(systemName: isSecure ? "lock.fill" : "globe")
                            .font(.system(size: NookDesign.Size.rowGlyph, weight: .medium))
                            .foregroundStyle(.secondary)
                        (Text(displayHost).foregroundStyle(.primary) + Text(displayPath).foregroundStyle(.tertiary))
                            .font(NookDesign.Font.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
  ```
  with three private computed properties added to the view:
  ```swift
    private var currentURL: URL? { browserManager.currentTab(for: windowState)?.url }
    private var isSecure: Bool { currentURL?.scheme == "https" }
    private var displayHost: String { currentURL?.host ?? displayURL }
    private var displayPath: String {
        guard let url = currentURL, url.host != nil else { return "" }
        let path = url.path
        return path == "/" ? "" : path
    }
  ```
  Keep `displayURL` (whatever it computes today) as the fallback for hosts that fail to parse. The placeholder branch (`magnifyingglass` + "Search or Enter URL...") keeps `Font.secondary` and `.secondary`, with the icon at `NookDesign.Size.rowGlyph`.
- L96-97 `.padding(.leading, 12).padding(.trailing, 8)` → `.padding(.horizontal, NookDesign.Spacing.rowPadding)`.
- L99 `minHeight/maxHeight: 36` → `NookDesign.Size.urlBar` for both.
- L107 clip `Radius.lg` → `NookDesign.Radius.md`; the progress bar clip L103-106 `UnevenRoundedRectangle(bottomLeadingRadius: Radius.lg, bottomTrailingRadius: Radius.lg, style: .continuous)` → `Radius.md` for both corners.
- Hover Copy Link button L52-59: `NookIconButtonStyle(size: 28, radius: NookDesign.Radius.lg)` → `NookIconButtonStyle(size: NookDesign.Size.rowButton, radius: NookDesign.Radius.sm)`.
- Background L125-127 stays `Surface.fillPressed` on hover, `Surface.fill` otherwise.

- [ ] **Step 5: Hover overlay insets**

In `SidebarHoverOverlayView.swift`: `horizontalInset = 7`, `verticalInset = 7` → both `NookDesign.Spacing.md`. (The spec said 7; 8 is the nearest token. The docs commit at the end of the phase amends the spec.)

- [ ] **Step 6: Verify and build**

```bash
cd /Users/bain/git/Nook && grep -nE "spacing: [0-9]|padding\([^)]*[0-9]|frame\([^)]*(height|width|minHeight|maxHeight): [0-9]" Navigation/Sidebar/SpacesSideBarView.swift Navigation/Sidebar/SidebarHeader.swift Nook/Components/Sidebar/NavButtonsView.swift Nook/Components/Sidebar/URLBarView.swift Nook/Components/Sidebar/SidebarHoverOverlayView.swift | grep -v "NookDesign\." ; echo "grep exit $? (1 means clean)"
```
Expected: no output, `grep exit 1`. Then run the build command. Expected: no diagnostic errors, `exit 0`.

- [ ] **Step 7: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Nook/Design Navigation Nook/Components/Sidebar && git commit -m "feat(sidebar): tokenize container, header, nav row, URL bar geometry; host/path URL styling

AI-assisted: implemented with Claude Code."
```

---

### Task 2: Tab rows

**Files:**
- Modify: `Nook/Components/Sidebar/SpaceSection/SpaceTab.swift`
- Modify: `Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift`
- Modify: `Nook/Components/Sidebar/SpaceSection/SpaceView.swift:150-166,254-265,363-445,520-557,585-607,611-612,663-668,692-700,722-743,827`

**Interfaces:**
- Consumes: `Size.row`, `Size.favicon`, `Size.rowGlyph`, `Size.rowButton`, `Spacing.rowGap`, `Spacing.rowPadding`, `Spacing.titleFade`, `Radius.md`, `Radius.xs`, `Radius.sm`, `Surface.*`, `Elevation.raised/.flat`.
- Produces: the row geometry every later task matches: height `Size.row`, `Radius.md`, `Spacing.rowPadding` horizontal, `Spacing.rowGap` between rows.

- [ ] **Step 1: `SpaceTab.swift`**

- `titleFade` L26-34: `.frame(width: 20)` → `NookDesign.Spacing.titleFade`; `.frame(width: isHovering ? 32 : 0)` → `isHovering ? NookDesign.Size.row : 0`.
- L48 `HStack(spacing: 8)` → `NookDesign.Spacing.md`.
- Favicon L52-53: `.frame(width: 18, height: 18)` → `NookDesign.Size.favicon` both; `.clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))` → `Radius.xs`. Keep the unloaded `.opacity(0.5)` on the favicon out: the whole row goes to 55% (below).
- Audio button L55-75: replace the button chrome with a plain glyph the row can still click:
  ```swift
                if tab.hasAudioContent || tab.hasPlayingAudio || tab.isAudioMuted {
                    Button(action: onMute) {
                        Image(systemName: tab.isAudioMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .contentTransition(.symbolEffect(.replace))
                            .font(.system(size: NookDesign.Size.rowGlyph, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(tab.isAudioMuted ? "Unmute" : "Mute")
                }
  ```
  Delete `isSpeakerHovering` and its `onHoverTracking`.
- Close overlay L111-128: `.frame(width: 24, height: 24)` → `NookDesign.Size.rowButton` both; background `isCloseHovering ? NookDesign.Surface.fillPressed : Color.clear` (the ternary on `isCurrentTab` was removed in Phase 2; confirm).
- Row L129-135: `.padding(.horizontal, 10)` → `NookDesign.Spacing.rowPadding`; `.frame(height: 36)` → `NookDesign.Size.row`; `.clipShape(Radius.lg)` → `Radius.md`.
- Active hairline: after the `.background(backgroundColor)` add
  ```swift
            .overlay {
                if isCurrentTab {
                    NookDesign.Radius.shape(NookDesign.Radius.md)
                        .strokeBorder(NookDesign.Surface.hairline, lineWidth: 1)
                }
            }
  ```
  (a `strokeBorder` draws inside the shape, so no padding change is needed; the spec's "padding drops to 7" is superseded by this).
- Rename state: when `tab.isRenaming`, the overlay stroke is the accent instead of the hairline:
  ```swift
                if tab.isRenaming {
                    NookDesign.Radius.shape(NookDesign.Radius.md)
                        .strokeBorder(space.accentColor, lineWidth: 1)
                } else if isCurrentTab { ...hairline as above... }
  ```
  `space` is not currently in scope in `SpaceTab`; use `browserManager.gradientColorManager.accentColor` instead (the active window's accent, which is the row's space when the row is visible).
- Unloaded: on the whole row (the `HStack` after `.clipShape`) add `.opacity(tab.isUnloaded ? 0.55 : 1)`. Add `static let unloadedOpacity: Double = 0.55` to `NookDesign.Surface` and use it (`NookDesign.Surface.unloadedOpacity`); remove the favicon-only opacity.

- [ ] **Step 2: `SplitTabRow.swift`**

- L16 `HStack(spacing: 1)` → `HStack(spacing: 0)`; the divider carries its own width. Divider L24-27: `Rectangle().fill(NookDesign.Surface.hairline).frame(width: 1).padding(.vertical, NookDesign.Spacing.sm)` (drop the `separatorColor.opacity(0.6)` and the fixed 24 height).
- L36 `.frame(height: 34)` → `NookDesign.Size.row`; L37 stays `Radius.md`.
- `SplitHalfTab` L65-96: `HStack(spacing: 8)` → `NookDesign.Spacing.md`; favicon `frame(18,18)` → `NookDesign.Size.favicon`, `Radius.xs` stays; `Spacer(minLength: 4)` → `NookDesign.Spacing.xs`; close `.frame(24,24)` → `NookDesign.Size.rowButton`; `.padding(.horizontal, 8)` → `NookDesign.Spacing.rowPadding`.
- Dragged opacity L119 `0.25` → `0` (match `SpaceView`'s dragged rows).
- Add the same active hairline overlay as Task 2 Step 1 on the active half (`isActive`).

- [ ] **Step 3: `SpaceView.swift` geometry and dead code**

- L150 `VStack(spacing: 4)` → `NookDesign.Spacing.xs`; L166 `.padding(.horizontal, 8)` → `NookDesign.Spacing.sidebarInset`; L82 `innerWidth = outerWidth - 16` → `outerWidth - NookDesign.Spacing.sidebarInset * 2`.
- L254 and L257 `VStack(spacing: 8)` → `NookDesign.Spacing.sectionGap`.
- Scroll arrows L283-336: `.frame(width: 24, height: 24)` → `NookDesign.Size.iconButton` (28) for the tappable circle; `Color.white.opacity(0.9)` → `NookDesign.Surface.raised`; `.padding(.horizontal, 8)` → `Spacing.sidebarInset`; `.padding(.top/.bottom, 4)` → `Spacing.xs`; hairline `frame(height: 1)` stays 1 (a hairline is 1pt by definition; add `static let hairlineWidth: CGFloat = 1` to `NookDesign.Size` and use it here and in `SplitTabRow`'s divider).
- L371 pinned `VStack(spacing: 0)` → `VStack(spacing: NookDesign.Spacing.rowGap)`.
- Drag caches L410-411 and L611-612: `itemCellSize = 36` → `NookDesign.Size.row`; `itemCellSpacing = 2` → `NookDesign.Spacing.rowGap`.
- L520 and L585 `VStack(spacing: 2)` → `NookDesign.Spacing.rowGap`; L556 and L665 `.padding(.top, 2)` → `NookDesign.Spacing.rowGap`.
- L552 trailing drag spacer `frame(height: 100)` and L663 `minHeight: 100`: add `static let dropTail: CGFloat = 100` to `NookDesign.Size` (`// empty drop target height below the last row`) and use it.
- Delete `windowDragSpacer` L692-700 (unreferenced; confirm with grep).
- `updateContentHeight()` L722-743: rewrite the per-row arithmetic in tokens: title row `NookDesign.Size.row`, each tab row `NookDesign.Size.row + NookDesign.Spacing.rowGap`, separator block `NookDesign.Size.row` (the new-tab row) plus `NookDesign.Spacing.sectionGap`. Keep the function's shape and callers; only the constants change. Note in the report what the old constants were.
- `scrollToTop` L827 targets `"space-separator-top"` which nothing declares: add `.id("space-separator-top")` on the `SpaceTitle` host at L153-159 so the target exists.

- [ ] **Step 4: Verify and build**

```bash
cd /Users/bain/git/Nook && grep -nE "spacing: [0-9]|padding\([^)]*[0-9]|frame\([^)]*(height|width|minHeight|maxHeight|minWidth): [0-9]|opacity\(0\.[0-9]" Nook/Components/Sidebar/SpaceSection/SpaceTab.swift Nook/Components/Sidebar/SpaceSection/SplitTabRow.swift Nook/Components/Sidebar/SpaceSection/SpaceView.swift | grep -vE "NookDesign\.|opacity\(0\.0|: 0\)|: 1\)" ; echo "grep exit $? (1 means clean)"
```
Expected: no output, `grep exit 1` (the `: 0)` and `: 1)` exclusions allow `spacing: 0` and `lineWidth: 1`). Then run the build. Expected green.

- [ ] **Step 5: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Nook/Design Nook/Components/Sidebar && git commit -m "feat(sidebar): 32pt tab rows with 2pt gap, hairline active state, glyph audio indicator, tokenized SpaceView geometry

AI-assisted: implemented with Claude Code."
```

---

### Task 3: Folder rows

**Files:**
- Modify: `Nook/Components/Sidebar/SpaceSection/TabFolderView.swift`
- Modify (only if needed for drop targeting): `Nook/Components/DragDrop/NookDropZoneHostView.swift`

**Interfaces:**
- Consumes: row geometry from Task 2, `Spacing.folderIndent`, `Size.rowGlyph`, `Size.spaceIcon`, `space.accentColor`, `Font.label`, `Font.caption`.

- [ ] **Step 1: Header row**

Rebuild the header `HStack` (L100-196) to: chevron, folder symbol, name, spacer, count, hover-only ellipsis menu.

```swift
        HStack(spacing: NookDesign.Spacing.md) {
            Image(systemName: "chevron.right")
                .font(.system(size: NookDesign.Size.rowGlyph - 1, weight: .semibold))
                .foregroundStyle(.tertiary)
                .rotationEffect(.degrees(folder.isOpen ? 90 : 0))
                .animation(NookDesign.Motion.standard, value: folder.isOpen)
            Image(systemName: folder.isOpen ? "folder.fill" : "folder")
                .font(.system(size: NookDesign.Size.spaceIcon, weight: .medium))
                .foregroundStyle(space.accentColor)
            // existing name Text / rename TextField, font NookDesign.Font.label, foregroundStyle(.primary)
            Spacer(minLength: NookDesign.Spacing.xs)
            if !isHovering {
                Text("\(tabCount)")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.tertiary)
            }
            if isHovering {
                // existing ellipsis Menu, restyled with NookIconButtonStyle(size: NookDesign.Size.rowButton, radius: NookDesign.Radius.sm)
            }
        }
        .padding(.horizontal, NookDesign.Spacing.rowPadding)
        .frame(height: NookDesign.Size.row)
```
`tabCount` is the folder's tab count as the view already computes it for its content (use the same source `folderTabs.count` or equivalent); `folder.isOpen` is whatever property the view currently toggles on tap (keep the existing name). Delete the `.symbolEffect(.bounce)` on the folder icon and the `.padding(.vertical, 12)`. Name color `AppColors.textSecondary` → `.primary`. Background stays `isDropTargeted → Surface.fillPressed`, `isHovering → Surface.fill`, else clear, in `Radius.md` (was `Radius.lg`).

- [ ] **Step 2: Children**

`folderContent` L216-261: `VStack(spacing: 0)` → `NookDesign.Spacing.rowGap`; `.padding(.horizontal, 10)` → remove (children align with the row grid); `.padding(.vertical, 4)` → `.padding(.vertical, NookDesign.Spacing.xxs)`; background `Radius.md` fill: remove the background entirely (children sit on the sidebar surface, indented). Child indent L279 `.padding(.leading, 12)` → `NookDesign.Spacing.folderIndent`. Cell caches L248-249 `36`/`2` → `NookDesign.Size.row` / `NookDesign.Spacing.rowGap`.

- [ ] **Step 3: Drop-target highlight**

`isDropTargeted` (L22) is never set. Look at `Nook/Components/DragDrop/NookDropZoneHostView.swift` and `NookDragSessionManager`: if the session exposes the currently targeted zone (a property like `activeDropZone`/`targetZoneID`), derive the highlight from it: `private var isDropTargeted: Bool { dragSession.isDragging && dragSession.<targetZone> == .folder(folder.id) }` and delete the dead `@State`. If no such property exists, add `@Published var targetedZone: DropZoneID?` to `NookDragSessionManager`, set it wherever the manager resolves the zone under the cursor (one assignment at the resolution site, cleared on drag end), and derive from that. Report which path you took.

- [ ] **Step 4: Verify and build**

```bash
cd /Users/bain/git/Nook && grep -nE "spacing: [0-9]|padding\([^)]*[0-9]|frame\([^)]*(height|width): [0-9]|size: [0-9]" Nook/Components/Sidebar/SpaceSection/TabFolderView.swift | grep -vE "NookDesign\.|: 0\)" ; echo "grep exit $? (1 means clean)"; grep -n "isDropTargeted" Nook/Components/Sidebar/SpaceSection/TabFolderView.swift | head -3
```
Expected: first grep empty (`exit 1`); the second shows `isDropTargeted` as a computed property or a `dragSession`-derived value, not an unset `@State`. Build green.

- [ ] **Step 5: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Nook/Components && git commit -m "feat(sidebar): folder rows with chevron, accent icon, count, 20pt indent; live drop-target highlight

AI-assisted: implemented with Claude Code."
```

---

### Task 4: Space header, separator, New Tab row, essentials, bottom bar

**Files:**
- Modify: `Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift:8,20-31,65-113`
- Modify: `Nook/Components/Sidebar/SpaceSection/SpaceSeparator.swift`
- Modify: `Nook/Components/Sidebar/SpaceSection/SpaceView.swift:481-518` (`newTabButtonSection`, `newTabButtonSectionWithClear`)
- Modify: `Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift:43-89,242-246`
- Modify: `Nook/Components/Sidebar/PinnedButtons/PinnedTabView.swift`
- Modify: `Navigation/Sidebar/SidebarBottomBar.swift:21-56`
- Modify: `Navigation/Sidebar/SpacesList/SpacesList.swift:79-81,120-145`
- Modify: `Navigation/Sidebar/SpacesList/SpacesListItem.swift:24`

**Interfaces:**
- Consumes: tokens from Tasks 1 and 2, `SpaceIconView`, `NookIconButtonStyle`.

- [ ] **Step 1: Space header (`SpaceTitle.swift`)**

- L8 `iconSize: CGFloat = 12` → `NookDesign.Size.spaceIcon`; L21 `SpaceIconView(icon: space.icon, size: iconSize, tint: space.accentColor)`.
- L20 `HStack(spacing: 6)` → `NookDesign.Spacing.sm`.
- Ellipsis L68-92: replace `.opacity(isHovering ? 1 : 0)` with `if isHovering { Menu {...} }` so it is not hit-testable when hidden; button style `NookIconButtonStyle(size: NookDesign.Size.rowButton, radius: NookDesign.Radius.sm)`.
- L107-109 paddings → `.padding(.horizontal, NookDesign.Spacing.sm)` and `.frame(height: NookDesign.Size.navRow)` (28); drop the vertical padding.
- Background `Radius.lg` → `Radius.md`.
- The duplicated `.contextMenu` at L126-142 stays (Task 5 keeps it pointed at `SpaceContextMenu`).

- [ ] **Step 2: Separator (`SpaceSeparator.swift`)**

- Container `.frame(height: 2)` L73 → `.frame(height: NookDesign.Size.rowGlyph + NookDesign.Spacing.xxs)` (15pt; enough for the caption labels).
- Hairline L48-50 stays `Surface.hairline`, height `NookDesign.Size.hairlineWidth`; add `.padding(.horizontal, NookDesign.Spacing.md)` on the hairline only.
- Both Organize and Clear move to the trailing side, after the hairline, in the order Organize then Clear, each `HStack(spacing: NookDesign.Spacing.xs)`, `Font.caption`, `.foregroundStyle(isXHovered ? .primary : .tertiary)`, `.padding(.horizontal, NookDesign.Spacing.xs)`; delete the `HStack(spacing: 7)`. Keep the `tabCount >= 5` gate on Organize and the `ProgressView().controlSize(.mini)` while organizing.

- [ ] **Step 3: New Tab row (`SpaceView.swift` L481-518)**

Replace `newTabButtonSection` with a row that matches the tab row geometry:

```swift
    @State private var isNewTabHovering = false

    private var newTabButtonSection: some View {
        Button {
            commandPalette.open()
        } label: {
            HStack(spacing: NookDesign.Spacing.md) {
                Image(systemName: "plus")
                    .font(.system(size: NookDesign.Size.favicon, weight: .medium))
                Text("New Tab")
                    .font(NookDesign.Font.body)
                Spacer(minLength: 0)
                if isNewTabHovering {
                    Text("⌘T")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .foregroundStyle(isNewTabHovering ? .secondary : .tertiary)
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(height: NookDesign.Size.row)
            .frame(maxWidth: .infinity)
            .background(isNewTabHovering ? NookDesign.Surface.fill : Color.clear)
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        }
        .buttonStyle(.plain)
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) { isNewTabHovering = hovering }
        }
    }
```
`newTabButtonSectionWithClear` L495-518: `VStack(spacing: 0)` → `NookDesign.Spacing.xs`; the separator's `.padding(.horizontal, 8).padding(.top, 4)` → `.padding(.horizontal, NookDesign.Spacing.md)` only. Remove the `.padding(.top, 8)` that was on the old button.

- [ ] **Step 4: Essentials (`PinnedGrid.swift`, `PinnedTabView.swift`)**

`PinnedTabView.swift`: delete the blurred-favicon active overlay (L38-39 `.overlay { if isActive { tabIcon.blur(radius: 30).opacity(0.5) } }`), the `faviconStrokeOverlay` function (L94-131) and its call site (L67-75), and the `faviconScale`/`faviconBlur` tunables (L23-24). The tile becomes: `Radius.lg` fill (`backgroundColor` as today: active `raised`, hover `fillPressed`, idle `fill`), favicon centered at `Size.essentialsFavicon`, `.frame(height: Size.essentialsTile)`, and `.nookElevation(isActive ? .raised : .flat)`, plus the same active hairline overlay used on tab rows (`strokeBorder(Surface.hairline, lineWidth: Size.hairlineWidth)` in `Radius.lg` when active). Keep `.opacity(isUnloaded ? NookDesign.Surface.unloadedOpacity : 1)` on the favicon. Delete `NookDesign.Size.essentialsStroke` from `NookDesign.swift` if nothing else reads it (grep first).

`PinnedGrid.swift`: L89 `VStack(spacing: 6)` → `NookDesign.Spacing.sm`; empty state L43-83: `VStack(spacing: 8)` → `Spacing.md`, `.padding(.vertical, 16)` → `Spacing.xl`, `.padding(.horizontal, 12)` → `Spacing.lg`, `StrokeStyle(lineWidth: 1, dash: [6, 4])` → `StrokeStyle(lineWidth: NookDesign.Size.hairlineWidth, dash: [NookDesign.Spacing.sm, NookDesign.Spacing.xs])`, dashed shape `Radius.xl` → `Radius.lg`; placeholder L242-246 `Color.primary.opacity(0.08)` → `NookDesign.Surface.fillPressed`.

- [ ] **Step 5: Bottom bar and switcher**

`SidebarBottomBar.swift`: L21 `HStack(alignment: .center, spacing: NookDesign.Spacing.xxs)`; add `.frame(height: NookDesign.Size.bottomBar)` on the HStack and remove `.fixedSize(horizontal: false, vertical: true)`; L37 `.padding(.horizontal, 8)` → `NookDesign.Spacing.sidebarInset`; `DownloadIndicator().offset(x: 12, y: -12)` → `.offset(x: NookDesign.Spacing.lg, y: -NookDesign.Spacing.lg)`.

`SpacesList.swift`: L79-81 `Spacer().frame(minWidth: 1, maxWidth: 8)` → `.frame(minWidth: NookDesign.Size.hairlineWidth, maxWidth: NookDesign.Spacing.md)`; in `SpacesListLayoutMode.determine` L120-145: `minSpacing 4.0` → `NookDesign.Spacing.xs`, `dotSize 6.0` → `NookDesign.Spacing.sm`, and delete the final dead `else` branch that returns `.compact` identically to the branch above it (fold the two into one).

`SpacesListItem.swift`: L24 `dotSize = 6` → `NookDesign.Spacing.sm`.

- [ ] **Step 6: Verify and build**

```bash
cd /Users/bain/git/Nook && grep -nE "spacing: [0-9]|padding\([^)]*[0-9]|frame\([^)]*(height|width|minWidth|maxWidth): [0-9]|offset\([^)]*[0-9]|size: [0-9]|opacity\(0\.[1-9]|blur\(" Nook/Components/Sidebar/SpaceSection/SpaceTitle.swift Nook/Components/Sidebar/SpaceSection/SpaceSeparator.swift Nook/Components/Sidebar/PinnedButtons/PinnedGrid.swift Nook/Components/Sidebar/PinnedButtons/PinnedTabView.swift Navigation/Sidebar/SidebarBottomBar.swift Navigation/Sidebar/SpacesList/SpacesList.swift Navigation/Sidebar/SpacesList/SpacesListItem.swift | grep -vE "NookDesign\.|: 0\)" ; echo "grep exit $? (1 means clean)"
```
Expected: empty, `exit 1`. Build green.

- [ ] **Step 7: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Nook/Design Nook/Components Navigation && git commit -m "feat(sidebar): space header, separator, New Tab row, essentials tiles, bottom bar to spec geometry

AI-assisted: implemented with Claude Code."
```

---

### Task 5: Three shared context menus

**Files:**
- Create: `Nook/Components/Sidebar/ContextMenus/TabContextMenu.swift`
- Create: `Nook/Components/Sidebar/ContextMenus/FolderContextMenu.swift`
- Move: `Navigation/Sidebar/SpaceContextMenu.swift` → `Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift` (`git mv`, no content change beyond what Step 4 says)
- Modify: `Nook/Components/Sidebar/SpaceSection/SpaceTab.swift:154-358` (delete `Options()` and its four sections), `SpaceView.swift:442-479,642-661` (delete `pinnedTabContextMenu`, `regularTabContextMenu`), `SplitTabRow.swift:106-116`, `PinnedGrid.swift:303-333`, `TabFolderView.swift:142-164,187-189,285,290-360`, `Navigation/Sidebar/SpacesList/SpacesListItem.swift:60-62,81-95`

**Interfaces:**
- Produces:
  ```swift
  enum TabMenuContext { case regular, spacePinned, folder, essential, split }
  struct TabContextMenu: View { let tab: Tab; let context: TabMenuContext; var body: some View }
  struct FolderContextMenu: View { let folder: TabFolder; var body: some View }
  ```
  (`TabFolder` is whatever the folder model type is named; use the existing name.) Both read `browserManager`, `tabManager`, `windowState`, and `splitManager` from the environment the way the inline menus do today.
- Consumes: nothing new.

- [ ] **Step 1: Canonical tab menu**

Build `TabContextMenu.body` in this order, with each item's action closure moved verbatim from the inline menu that has it today (source noted). Items whose condition is not met are omitted (no disabled placeholders except where noted).

Section 1, placement:
- **Pin to Space** (regular: `SpaceView.swift:647-661` "Pin to Space") / **Unpin from Space** (spacePinned: `SpaceView.swift:447-479` "Unpin from Space")
- **Add to Favorites** (regular, spacePinned, folder: `SpaceTab.swift:177-202` "Add to Favorites"; source also "Pin Globally" in `SpaceView`) / **Remove from Favorites** (essential: `PinnedGrid.swift:303-333` "Remove pinned tab")
- **Add to Folder ▸** submenu (regular, spacePinned: `SpaceTab.swift:177-202`)
- **Move to Space ▸** submenu (all but essential: `SpaceTab.swift:307-318`)

Divider.

Section 2, edit:
- **Rename** (`SpaceTab.swift:205-267`), **Reset Tab Name** (when renamed; same source, also `SplitTabRow`, `PinnedGrid`, `TabFolderView`)
- **Duplicate** (`SpaceTab.swift:300`)
- **Copy Link** (`SpaceTab.swift:205-267`), **Share** (same)
- **Open in Split View ▸** with **Right** and **Left** (`SpaceTab.swift:282-288`; `SpaceView`, `PinnedGrid`, `TabFolderView` have the same pair inline)
- **Reset to Pinned URL**, **Edit Pinned URL** (spacePinned, essential: `SpaceTab.swift:205-267` / `PinnedGrid`)

Divider.

Section 3, state:
- **Mute** / **Unmute** (when the tab has audio: `TabFolderView.swift:309-360` "Mute/Unmute Audio")
- **Unload Tab** (disabled when already unloaded: `TabFolderView.swift:309-360`)
- **Unload All Inactive Tabs** (same source)

Divider.

Section 4, close:
- **Close Tab** with `.keyboardShortcut("w", modifiers: .command)` shown as the shortcut hint (`SpaceTab.swift:335-358` "Close"; `role: .destructive`)
- **Close Other Tabs** (regular, spacePinned: `SpaceTab.swift:335-358` "Close Others")
- **Close All Below** (regular: same source)

Every item gets a `Label(_:systemImage:)` with these symbols: pin `pin`, unpin `pin.slash`, favorites `star` / `star.slash`, folder `folder.badge.plus`, move `arrow.right.square`, rename `pencil`, reset name `arrow.uturn.backward`, duplicate `plus.square.on.square`, copy link `link`, share `square.and.arrow.up`, split `rectangle.split.2x1`, reset URL `arrow.counterclockwise`, edit URL `link.badge.plus`, mute `speaker.slash`, unmute `speaker.wave.2`, unload `moon.zzz`, unload all `moon.zzz.fill`, close `xmark`, close others `xmark.circle`, close below `arrow.down.to.line`.

**Move Up / Move Down** from `regularTabContextMenu` are dropped (drag reorder covers them). Say so in the report.

- [ ] **Step 2: Folder menu**

`FolderContextMenu.body`, from `TabFolderView.swift:290-307` verbatim: **Rename Folder** (`pencil`), **Add Tab to Folder** (`plus`), Divider, **Alphabetize Tabs** (`textformat.abc`), Divider, **Delete Folder** (`trash`, `role: .destructive`).

- [ ] **Step 3: Wire the call sites**

- `SpaceTab.swift`: `.contextMenu { Options() }` → `.contextMenu { TabContextMenu(tab: tab, context: menuContext) }` where `SpaceTab` gains `var menuContext: TabMenuContext = .regular`. Delete `Options()`, `addToMenuSection`, `editMenuSection`, `actionsMenuSection`, `closeMenuSection` and any helpers only they used.
- `SpaceView.swift`: `pinnedTabView` passes `menuContext: .spacePinned` and drops its `.contextMenu { pinnedTabContextMenu }`; regular tabs pass `.regular` and drop `.contextMenu { regularTabContextMenu }`. Delete both menu builders. If `SpaceTab` is constructed with a positional initializer, add the parameter at the end with its default.
- `TabFolderView.swift`: `folderTabView` passes `menuContext: .folder` and drops `.contextMenu { folderTabContextMenu }`; delete `folderTabContextMenu`. The header's hover `Menu { ... }` and the `.contextMenu` both become `FolderContextMenu(folder: folder)`; delete `folderContextMenu`.
- `SplitTabRow.swift`: `.contextMenu { TabContextMenu(tab: tab, context: .split) }` for each half; delete the inline items.
- `PinnedGrid.swift`: `.contextMenu { TabContextMenu(tab: tab, context: .essential) }`; delete the inline items.
- `SpacesListItem.swift`: `.contextMenu { SpaceContextMenu(space: space, canDelete: tabManager.spaces.count > 1, onEditName: nil, onEditIcon: nil, onOpenSettings: { browserManager.showSpaceSettings(for: space) }, onDeleteSpace: { showDeleteConfirmation() }) }` (match the parameter labels the struct actually has); delete `spaceContextMenu` and, if now unused, `showDeleteConfirmation`'s duplicate of what `SpaceContextMenu` already does (keep whichever one is called).

- [ ] **Step 4: Move `SpaceContextMenu`**

```bash
cd /Users/bain/git/Nook && mkdir -p Nook/Components/Sidebar/ContextMenus && git mv Navigation/Sidebar/SpaceContextMenu.swift Nook/Components/Sidebar/ContextMenus/SpaceContextMenu.swift
```
Give every item in it a `Label(_:systemImage:)` if any lacks one (rename `pencil`, change icon `square.grid.2x2`, settings `gearshape`, delete `trash`).

- [ ] **Step 5: Verify and build**

```bash
cd /Users/bain/git/Nook && echo "contextMenu sites:"; grep -rn "\.contextMenu {" --include='*.swift' Navigation Nook/Components/Sidebar | grep -v "Nook/Components/Sidebar/Menu/"; echo "inline builders left:"; grep -rnE "func Options\(|pinnedTabContextMenu|regularTabContextMenu|folderTabContextMenu|var folderContextMenu|var spaceContextMenu" --include='*.swift' Navigation Nook/Components/Sidebar; echo "grep exit $? (1 means clean)"
```
Expected: every remaining `.contextMenu {` line's body is a `TabContextMenu(`, `FolderContextMenu(`, `SpaceContextMenu(`, `NavigationHistoryContextMenu(`, or the sidebar background menu in `SpacesSideBarView`; the second grep is empty (`exit 1`). Build green.

- [ ] **Step 6: Commit**

```bash
cd /Users/bain/git/Nook && git add -A Nook/Components Navigation && git commit -m "refactor(sidebar): TabContextMenu, FolderContextMenu, SpaceContextMenu replace eleven inline menus

AI-assisted: implemented with Claude Code."
```

---

### Task 6: Phase gate

- [ ] **Step 1: Audit**

```bash
cd /Users/bain/git/Nook && D=(Navigation Nook/Components/Sidebar/SpaceSection Nook/Components/Sidebar/PinnedButtons Nook/Components/Sidebar/URLBarView.swift Nook/Components/Sidebar/NavButtonsView.swift Nook/Components/Sidebar/SidebarHoverOverlayView.swift Nook/Components/Sidebar/ContextMenus); \
echo "raw geometry: $(grep -rnE 'spacing: [0-9]|padding\([^)]*[0-9]|frame\([^)]*(height|width|minHeight|maxHeight|minWidth|maxWidth): [0-9]|offset\([^)]*[0-9]|size: [0-9]' --include='*.swift' "${D[@]}" | grep -vE 'NookDesign\.|: 0\)|: 1\)' | wc -l | tr -d ' ')"; \
echo "inline menus: $(grep -rnE 'func Options\(|pinnedTabContextMenu|regularTabContextMenu|folderTabContextMenu|var folderContextMenu|var spaceContextMenu' --include='*.swift' "${D[@]}" | wc -l | tr -d ' ')"; \
echo "AppColors in sidebar: $(grep -rn 'AppColors\.' --include='*.swift' "${D[@]}" | wc -l | tr -d ' ')"; \
echo "font literals: $(grep -rnE '\.font\(\.system\(size: ?[0-9]' --include='*.swift' Navigation Nook/Components UI CommandPalette Nook/Managers/DialogManager | grep -v NookDesign.swift | wc -l | tr -d ' ')"
```
Expected: all four counts `0`. (The nav-button width breakpoints in `NavButtonsView.swift` are compared, not passed to a modifier, so the grep does not catch them.)

- [ ] **Step 2: Build and manual checklist**

Run the build command, then a signed build (`xcodebuild -scheme Nook -configuration Debug -arch arm64 -derivedDataPath build -allowProvisioningUpdates -quiet`) and open `build/Build/Products/Debug/Nook.app`. Check: rows are 32pt with a 2pt gap; the active tab has a white card with a hairline; hover shows the close button and the title fades before it; a playing tab shows the speaker glyph and clicking it mutes; an unloaded tab is dimmed as a whole; renaming shows the accent ring; folders show chevron, accent icon, name, count, and rotate the chevron on open; children indent 20pt; dragging a tab over a folder highlights it; the space header shows the accent icon and the ellipsis only on hover; the separator shows Clear and Organize on hover at the trailing end; New Tab shows ⌘T on hover; essentials are plain tiles, active one raised with a hairline; the bottom bar is 40pt; the URL bar shows lock, host, and dimmed path at 32pt; nav buttons are 28pt; every context menu (tab, split half, essential tile, folder header, folder child, space switcher, space header) opens with icons and the documented order; dragging tabs between sections and into folders still works; split view still opens from the menu; light and dark; sidebar left and right; hover overlay with the sidebar hidden.

- [ ] **Step 3: Record**

Append `Done <date>, commits <first>..<last>.` to phase 3 under `## Phases` in the spec; change the hover overlay inset in section 5 from `7pt` to `Spacing.md (8pt)`; commit:

```bash
cd /Users/bain/git/Nook && git add docs/superpowers/specs/2026-09-14-gui-remodel-design.md && git commit -m "docs: mark GUI remodel phase 3 done

AI-assisted: implemented with Claude Code."
```
