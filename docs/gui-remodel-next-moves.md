# GUI remodel: next moves

Status 2026-09-14: all five phases of the remodel are on `main` and pushed. The spec is `docs/superpowers/specs/2026-09-14-gui-remodel-design.md`; the design canvas is at https://claude.ai/code/artifact/c02bed25-93d0-4f60-9dfe-884ef2df0d08. The app builds and runs from `main` at commit 5cb5164.

## Verify on screen first

Two screens were changed in ways a build cannot check. Look at these before anything else.

1. Extension library panel (toolbar puzzle icon). It is the first place the app draws Liquid Glass inside a transparent `NSPanel`. If it reads as a flat, nearly invisible fill over the page, the fix is `NSGlassEffectView` as the panel's content view with the `NSHostingView` inside it. The file is `Nook/Components/Extensions/ExtensionLibraryPanel.swift`; the more-menu in `ExtensionLibraryMoreMenu.swift` has the same structure.
2. Settings, Privacy, Manage Cookies, on a profile with a real cookie count. The entry list is a virtualized `List` under a grouped `Form` that has `.scrollDisabled(true)` and `.fixedSize(horizontal: false, vertical: true)`. That layout was reasoned about, never rendered. If the Form fights the List for height, drop the `fixedSize` and give the Form a fixed frame.

Then the rest of the manual pass: light and dark, sidebar on both sides, every context menu (regular tab, pinned tab, folder child, essential tile, split half, space header, space switcher), drag a tab into a folder, hide the sidebar and hover its edge, open the palette, a dialog, a toast, the find bar, and click through every settings tab.

## Known defects to fix

Each of these was found in review and deliberately left for a later pass. None blocks daily use.

1. Duplicate in the tab context menu duplicates the active tab, whatever row was right-clicked. This predates the remodel. `TabManager` has no duplicate-by-tab API; adding one and calling it from `TabContextMenu.swift` fixes it in every context at once.
2. Close Other Tabs and Close All Below are hidden on pinned rows because `TabManager.closeOtherTabs` closes the whole regular list of the space. If you want them on pinned rows, the manager needs a variant that excludes the clicked tab by identity rather than by list position.
3. The split-view active row draws its hairline per half, so a rounded corner appears at the divider. `SplitTabRow.swift`; an `UnevenRoundedRectangle` per side fixes it.
4. Folder headers do not register as drop zones. Only an open folder's children highlight when a tab is dragged over them. Wrapping the header in the same `.folder(id)` drop zone in `TabFolderView.swift` makes closed folders targets too.
5. Move to Space in the tab menu shows the current space disabled instead of checked, and has no New Space item. The spec asked for both.
6. `ShortcutCategory.icon` in the settings models is dead since the category filter chips went away. Delete it.
7. The URL bar's placeholder icon grew from 12pt to 13pt with the row glyph token. Fine if you like it; the token to change is `Size.rowGlyph`, which also drives the audio speaker and folder chevron.

## Visual calls you can retune in one file

Everything below is a single value in `Nook/Design/NookDesign.swift`.

| If this reads wrong | Change |
|---|---|
| Hover fills too faint in dark mode | `Surface.fill` (0.045) and `Surface.fillPressed` (0.08) |
| Hairlines and the command palette divider too faint | `Surface.hairline` (0.08) |
| Dialogs and toasts throw too much shadow | `Elevation.floating` values in `NookElevationModifier` |
| Palette or dialog bounce feels flat | `Motion.spring` (`.snappy(duration: 0.3)`) |
| Rows too tight | `Size.row` (32) and `Spacing.rowGap` (2); the drag caches read the same tokens |
| Space header text sits 6pt left of tab text | `SpaceTitle.swift` uses `Spacing.sm` where rows use `Spacing.rowPadding` |

## Larger follow-ups

These were out of scope for the remodel and are the natural next projects.

1. AI chat sidebar. It kept its legacy `contrastText` logic, which computes text color against the space accent even though the accent no longer paints the background. It needs the same treatment the main sidebar got: system text colors, `Surface` fills, tokenized geometry. Around 800 lines in `Nook/Components/Sidebar/AIChat/SidebarAIChat.swift`.
2. Top bar address mode (`TopBarView.swift`). It was tokenized but never redesigned, and it still derives its colors from the page's theme color. Either restyle it to match the sidebar URL bar or consider whether the mode still earns its keep.
3. Onboarding. Untouched by design; it has its own Metal transition and predates the token file. When it is next opened, the first job is a literal sweep.
4. Dialogs are still the in-window overlay with a dimming scrim. They look right on glass now, and the only thing left from the spec is the icon circle's tinted glass, which stayed. A later pass could move them to native sheets if the overlay ever fights a WebKit popup.
5. `Spacing` carries both a numeric scale (`xs` through `xxxl`) and semantic names (`rowPadding`, `sectionGap`, `folderIndent`). Phase 3 used the semantic names. Decide whether the numeric scale stays; if it goes, most remaining uses are in dialogs and settings.
6. `BrowserManager.currentTab(for:)` rebuilds the whole tab set on every call through `allTabs()`. Phase 3 cut the URL bar from seven calls per render to one, but the function is still the hot path for any view that reads the current tab. A cached lookup keyed by window would remove the cost everywhere.

## Release

Nothing in the remodel changed the release pipeline. When you want this out, fast-forward `release` to `main` and push; the notarize workflow runs on the `macos-26` runner and has not succeeded since v1.0.6, so expect the first push to be a pipeline test as much as a release. Bump the marketing version first; 1.2.1 build 121 is what the project currently says.
