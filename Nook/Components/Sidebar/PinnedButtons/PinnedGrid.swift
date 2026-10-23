// Licensed under GPL-3.0. See LICENSE.
//
//      PinnedGrid.swift
//      Nook
//
//      Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI
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
                if dragSession.isDragging {
                    NookDropZoneHostView(
                        zoneID: zone,
                        layout: .grid(count: 0, columns: colsCount),
                        manager: dragSession,
                        onDrop: { id, position in tabs.dropOnFavorites(id, spaceID: spaceID, index: position.index) }
                    ) {
                        HStack(spacing: NookDesign.Spacing.md) {
                            Image(systemName: "star")
                            Text("Drag to add Favorites")
                        }
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: NookDesign.Size.essentialsTile)
                        .nookFavoriteSurface(selected: false, hovered: dragSession.activeZone == zone)
                    }
                    .transition(.opacity)
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
                    LazyVGrid(columns: makeColumns(count: previewColumns), alignment: .center, spacing: NookDesign.Spacing.xs) {
                        ForEach(displayedIDs, id: \.self) { id in
                            if preview?.placeholderID == id {
                                essentialsPlaceholder
                            } else if let item = items.first(where: { $0.id == id }) {
                                PinnedTile(item: item, zone: zone)
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

    /// Preview the committed order, including its column count, without changing the
    /// original grid's drop boundaries or mutating the favorites while dragging.
    private func favoritePreview(in zone: DropZoneID, items: [Item]) -> FavoriteDropPreview? {
        guard dragSession.isDragging, dragSession.activeZone == zone,
              let position = dragSession.dropPosition, position.zone == zone,
              let draggedID = dragSession.draggedItem?.tabId else { return nil }
        return FavoriteDropPreview(itemIDs: items.map(\.id), draggedID: draggedID,
                                   destinationBoundary: position.index)
    }

    private var essentialsPlaceholder: some View {
        NookDesign.Radius.shape(NookDesign.Tab.radius)
            .fill(NookDesign.Surface.fillPressed)
            .frame(minWidth: NookDesign.Size.essentialsTile, minHeight: NookDesign.Size.essentialsTile)
    }

    private func columnCount(for width: CGFloat, itemCount: Int) -> Int {
        guard width > 0, itemCount > 0 else { return 1 }
        var cols = min(maxColumns, itemCount)
        while cols > 1 {
            let needed = CGFloat(cols) * NookDesign.Size.essentialsTile + CGFloat(cols - 1) * NookDesign.Spacing.xs
            if needed <= width { break }
            cols -= 1
        }
        return max(1, cols)
    }

    private func makeColumns(count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: NookDesign.Size.essentialsTile),
                spacing: NookDesign.Spacing.xs,
                alignment: .center
            ),
            count: count
        )
    }
}

private struct PinnedTile: View {
    let item: Item
    let zone: DropZoneID

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @ObservedObject private var dragSession = NookDragSessionManager.shared

    private var tabs: TabsController { browserManager.tabs }
    @Environment(\.colorScheme) private var colorScheme
    private var appearance: SpaceAppearance {
        let fallback = SpaceAppearance(accentHex: "#7C7C7C")
        guard case .favorites(let spaceID) = zone else { return fallback }
        return tabs.space(spaceID)?.resolvedAppearance ?? fallback
    }
    private var favoriteScheme: ColorScheme {
        appearance.mode == .system ? colorScheme : (appearance.mode == .dark ? .dark : .light)
    }
    private var favoritePrimaryColor: Color {
        let nodes = appearance.normalized.nodes
        return Color(hex: nodes.isEmpty ? "#8E8E93" : nodes[nodes.count / 2].colorHex)
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
                primaryColor: favoritePrimaryColor,
                isUnloaded: session?.isUnloaded ?? true,
                hasLeftPinnedURL: tabs.hasLeftHome(item.id),
                onResetToPinnedURL: { tabs.resetToHome(item.id) },
                action: {
                    FavoritePreview.shared.dismiss()
                    tabs.select(item.id, in: windowState)
                }
            )
            .environment(\.colorScheme, favoriteScheme)
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
