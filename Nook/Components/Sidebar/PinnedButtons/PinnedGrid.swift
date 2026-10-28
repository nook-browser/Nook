// Licensed under GPL-3.0. See LICENSE.
//
//      PinnedGrid.swift
//      Nook
//
//      Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import NookDesign
import NookTabsCore
import NookWeb
import NookUI

struct PinnedGrid: View {
    let width: CGFloat
    let spaceID: UUID?

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @ObservedObject private var dragSession = NookDragSessionManager.shared
    private let maxColumns = 4

    init(width: CGFloat, spaceID: UUID? = nil) {
        self.width = width
        self.spaceID = spaceID
    }

    private var tabs: TabsController { browserManager.tabs }

    @ViewBuilder
    var body: some View {
        let effectiveSpaceID = spaceID ?? windowState.spaceID
        let items: [Item] = effectiveSpaceID.map { tabs.favorites(of: $0) } ?? []
        let colsCount: Int = columnCount(for: width, itemCount: items.count)

        let shouldAnimate = (windowRegistry.activeWindow?.id == windowState.id) && !browserManager.isSwitchingSpace

        if let spaceID = effectiveSpaceID {
            let zone = DropZoneID.favorites(spaceID: spaceID)
            if items.isEmpty {
                let isDragging = dragSession.isDragging

                NookDropZoneHostView(
                    zoneID: zone,
                    layout: .grid(count: 0, columns: colsCount),
                    manager: dragSession,
                    onDrop: { id, position in tabs.dropOnFavorites(id, spaceID: spaceID, index: position.index) }
                ) {
                    VStack(spacing: NookDesign.Spacing.md) {
                        Image(systemName: "star.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        VStack(spacing: NookDesign.Spacing.xxs) {
                            Text("Drag to add Favorites")
                                .font(NookDesign.Font.label)
                                .foregroundStyle(.secondary)

                            Text("Favorites keep your most\nused sites and apps close")
                                .font(NookDesign.Font.secondary)
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NookDesign.Spacing.xl)
                    .padding(.horizontal, NookDesign.Spacing.lg)
                    .background {
                        NookDesign.Radius.shape(NookDesign.Radius.lg)
                            .strokeBorder(style: StrokeStyle(lineWidth: NookDesign.Size.hairlineWidth, dash: [NookDesign.Spacing.sm, NookDesign.Spacing.xs]))
                            .foregroundStyle(isDragging ? NookDesign.Surface.dropBorderActive : NookDesign.Surface.dropBorderIdle)
                    }
                    .background {
                        NookDesign.Radius.shape(NookDesign.Radius.lg)
                            .fill(isDragging ? NookDesign.Surface.fillPressed : Color.clear)
                    }
                    .animation(NookDesign.Motion.quick, value: isDragging)
                }
            } else {
                NookDropZoneHostView(
                    zoneID: zone,
                    layout: .grid(count: items.count, columns: colsCount),
                    manager: dragSession,
                    onDrop: { id, position in tabs.dropOnFavorites(id, spaceID: spaceID, index: position.index) }
                ) {
                    let preview = favoritePreview(in: zone, items: items)
                    let displayedIDs = preview?.itemIDs ?? items.map(\.id)
                    let previewColumns = columnCount(for: width, itemCount: displayedIDs.count)
                    LazyVGrid(columns: makeColumns(count: previewColumns), alignment: .center, spacing: NookDesign.Spacing.favoriteGap) {
                        ForEach(displayedIDs, id: \.self) { id in
                            if preview?.placeholderID == id {
                                essentialsPlaceholder
                            } else if let item = items.first(where: { $0.id == id }) {
                                PinnedTile(item: item, zone: zone, spaceID: spaceID)
                                    .opacity(dragSession.draggedItem?.tabId == id ? 0.0 : 1.0)
                            }
                        }
                    }
                    .animation(NookDesign.Motion.spring, value: displayedIDs)
                }
                .contentShape(Rectangle())
                .fixedSize(horizontal: false, vertical: true)
                .animation(shouldAnimate ? NookDesign.Motion.standard : nil, value: colsCount)
                .animation(shouldAnimate ? NookDesign.Motion.standard : nil, value: items.count)
                .allowsHitTesting(!browserManager.isSwitchingSpace)
            }
        }
    }

    /// Preview the committed order without mutating the favorites while dragging.
    private func favoritePreview(in zone: DropZoneID, items: [Item]) -> FavoriteDropPreview? {
        guard dragSession.isDragging, dragSession.activeZone == zone,
              let position = dragSession.dropPosition, position.zone == zone,
              let draggedID = dragSession.draggedItem?.tabId else { return nil }
        return FavoriteDropPreview(itemIDs: items.map(\.id), draggedID: draggedID,
                                   destinationBoundary: position.index)
    }

    private var essentialsPlaceholder: some View {
        NookDesign.Radius.shape(NookDesign.Radius.lg)
            .fill(NookDesign.Surface.fillPressed)
            .frame(minWidth: NookDesign.Size.favoriteTile, minHeight: NookDesign.Size.favoriteTile)
    }

    private func columnCount(for width: CGFloat, itemCount: Int) -> Int {
        guard width > 0, itemCount > 0 else { return 1 }
        var cols = min(maxColumns, itemCount)
        while cols > 1 {
            let needed = CGFloat(cols) * NookDesign.Size.favoriteTile + CGFloat(cols - 1) * NookDesign.Spacing.favoriteGap
            if needed <= width { break }
            cols -= 1
        }
        return max(1, cols)
    }

    private func makeColumns(count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: NookDesign.Size.favoriteTile),
                spacing: NookDesign.Spacing.favoriteGap,
                alignment: .center
            ),
            count: count
        )
    }
}

private struct PinnedTile: View {
    let item: Item
    let zone: DropZoneID
    let spaceID: UUID

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.nookSettings) private var settings
    @ObservedObject private var dragSession = NookDragSessionManager.shared

    private var tabs: TabsController { browserManager.tabs }

    /// Tile colors from the chrome the sidebar actually shows: the theme stop or the accent's
    /// gradient top, blended toward the window background as the chrome blends it.
    private var tileColors: SpaceTheme.TileColors? {
        guard !windowState.isIncognito, let space = tabs.space(spaceID), !space.isAgent else { return nil }
        let isActive = windowRegistry.activeWindowId == windowState.id
        let scheme = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
        func blend(_ base: NSColor, toward amount: Double) -> ThemeRGB? {
            var out: NSColor?
            scheme?.performAsCurrentDrawingAppearance {
                out = base.blended(withFraction: amount, of: .windowBackgroundColor)?.usingColorSpace(.sRGB)
            }
            guard let c = out else { return nil }
            return ThemeRGB(r: Double(c.redComponent), g: Double(c.greenComponent), b: Double(c.blueComponent))
        }
        if let theme = space.theme {
            let resolved = theme.resolve(systemDark: colorScheme == .dark, dimmed: !isActive)
            guard let stop = resolved.stops.first else { return nil }
            let opacity = reduceTransparency || !settings.themeTranslucency ? 1 : NookDesign.Surface.themeTintOpacity(intensity: theme.intensity)
            let base = NSColor(srgbRed: stop.r, green: stop.g, blue: stop.b, alpha: 1)
            guard let chrome = blend(base, toward: 1 - opacity) else { return nil }
            return SpaceTheme.tileColors(chrome: chrome, dark: resolved.isDark)
        }
        guard let chrome = blend(NSColor(space.accentColor), toward: isActive ? 0.55 : 0.8) else { return nil }
        return SpaceTheme.tileColors(chrome: chrome, dark: colorScheme == .dark)
    }

    var body: some View {
        let session = tabs.session(for: item.id)
        let url = tabs.currentURL(for: item)?.absoluteString ?? ""
        NookDragSourceView(
            item: NookDragItem(tabId: item.id, title: tabs.title(for: item), urlString: url),
            icon: session?.favicon,
            zoneID: zone,
            manager: dragSession
        ) {
            PinnedTabView(
                tabName: tabs.title(for: item),
                tabURL: url,
                tabIcon: ItemFavicon(item: item, session: session),
                isActive: tabs.selectedItemID(in: windowState) == item.id,
                isUnloaded: session?.isUnloaded ?? true,
                hasLeftPinnedURL: tabs.hasLeftHome(item.id),
                onResetToPinnedURL: { tabs.resetToHome(item.id) },
                colors: tileColors,
                action: {
                    FavoritePreview.shared.dismiss()
                    tabs.select(item.id, in: windowState)
                }
            )
            .frame(maxWidth: .infinity)
            .anchorPreference(key: FavoritePreviewAnchorKey.self, value: .bounds) {
                FavoritePreview.shared.itemID == item.id && FavoritePreview.shared.windowID == windowState.id ? $0 : nil
            }
            .contextMenu {
                TabContextMenu(itemID: item.id, context: .favorite)
                    .environment(windowState)
                    .environment(tabs)
                    .environment(\.tabActions, browserManager)
            }
            .onHoverTracking { hovering in
                browserManager.hoveredPinnedTabId = hovering ? item.id : nil
                FavoritePreview.shared.tileHover(item, hovering: hovering, in: windowState, tabs: tabs)
            }
        }
    }
}
