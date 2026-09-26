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
        let columns: [GridItem] = makeColumns(count: colsCount)

        let shouldAnimate = (windowRegistry.activeWindow?.id == windowState.id) && !browserManager.isSwitchingSpace

        if let spaceID = effectiveSpaceID {
            let zone = DropZoneID.favorites(spaceID: spaceID)
            let isAddingBookmark = dragSession.isDragging
                && !dragSession.isSettlingDrop
                && dragSession.draggedItem?.isFolder != true
                && dragSession.sourceZone != zone
            let showsFavorites = !items.isEmpty || isAddingBookmark

            Group {
                if items.isEmpty {
                    NookDropZoneHostView(
                        zoneID: zone,
                        layout: .grid(count: 0, columns: colsCount),
                        manager: dragSession,
                        onDrop: { id, position in tabs.dropOnFavorites(id, spaceID: spaceID, index: position.index) }
                    ) {
                        if isAddingBookmark {
                            LazyVGrid(columns: columns, alignment: .center, spacing: NookDesign.Spacing.sm) {
                                bookmarkDropPlaceholder
                            }
                        } else {
                            Color.clear
                                .frame(maxWidth: .infinity)
                                .frame(height: 0)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .allowsHitTesting(!browserManager.isSwitchingSpace)
                } else {
                    NookDropZoneHostView(
                        zoneID: zone,
                        layout: .grid(count: items.count, columns: colsCount),
                        manager: dragSession,
                        onDrop: { id, position in tabs.dropOnFavorites(id, spaceID: spaceID, index: position.index) }
                    ) {
                        LazyVGrid(columns: columns, alignment: .center, spacing: NookDesign.Spacing.sm) {
                            let insertionIdx = insertionIndex(in: zone, items: items)

                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                let isDraggedItem = dragSession.draggedItem?.tabId == item.id

                                if let ins = insertionIdx, ins == index, !isDraggedItem {
                                    insertionPlaceholder(in: zone)
                                }

                                PinnedTile(item: item, zone: zone)
                                    .opacity(isDraggedItem
                                             ? (dragSession.isSettlingDrop ? 0 : NookDesign.Surface.unloadedOpacity)
                                             : 1)
                                    .animation(NookDesign.Motion.quick, value: isDraggedItem)
                            }

                            if let ins = insertionIdx, ins >= items.count {
                                insertionPlaceholder(in: zone)
                            }
                        }
                        .animation(NookDesign.Motion.quick, value: insertionIndex(in: zone, items: items))
                        .animation(NookDesign.Motion.quick, value: items.map(\.id))
                    }
                    .contentShape(Rectangle())
                    .fixedSize(horizontal: false, vertical: true)
                    .animation(shouldAnimate ? NookDesign.Motion.quick : nil, value: colsCount)
                    .animation(shouldAnimate ? NookDesign.Motion.quick : nil, value: items.count)
                    .allowsHitTesting(!browserManager.isSwitchingSpace)
                }
            }
            .padding(.bottom, showsFavorites ? NookDesign.Spacing.sectionGap : 0)
        }
    }

    /// The insertion index for the grid during a drag, or nil when no placeholder should show.
    private func insertionIndex(in zone: DropZoneID, items: [Item]) -> Int? {
        guard dragSession.isDragging,
              !dragSession.isSettlingDrop,
              dragSession.draggedItem?.isFolder != true else {
            return nil
        }
        // A tab coming from another section is offered at the end of the bookmark list for the
        // whole drag. Reordering bookmarks keeps following the pointer as before.
        if dragSession.sourceZone != zone {
            return items.count
        }
        guard dragSession.activeZone == zone,
              let position = dragSession.dropPosition, position.zone == zone else {
            return nil
        }
        // Reordering within the grid: no placeholder at the dragged tile's own slot.
        if dragSession.sourceZone == zone,
           let dragged = dragSession.draggedItem?.tabId,
           let from = items.firstIndex(where: { $0.id == dragged }),
           position.index == from || position.index == from + 1 {
            return nil
        }
        return position.index
    }

    @ViewBuilder
    private func insertionPlaceholder(in zone: DropZoneID) -> some View {
        if dragSession.sourceZone == zone {
            essentialsPlaceholder
        } else {
            bookmarkDropPlaceholder
        }
    }

    private var bookmarkDropPlaceholder: some View {
        NookDesign.Radius.shape(NookDesign.Radius.lg)
            .fill(Color.clear)
            .frame(minWidth: NookDesign.Size.essentialsTile, minHeight: NookDesign.Size.essentialsTile)
            .overlay {
                NookDesign.Radius.shape(NookDesign.Radius.lg)
                    .strokeBorder(
                        NookDesign.Surface.dropBorderActive,
                        style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                    )
            }
    }

    private var essentialsPlaceholder: some View {
        NookDesign.Radius.shape(NookDesign.Radius.lg)
            .fill(NookDesign.Surface.fillPressed)
            .frame(minWidth: NookDesign.Size.essentialsTile, minHeight: NookDesign.Size.essentialsTile)
    }

    private func columnCount(for width: CGFloat, itemCount: Int) -> Int {
        guard width > 0, itemCount > 0 else { return 1 }
        var cols = min(maxColumns, itemCount)
        while cols > 1 {
            let needed = CGFloat(cols) * NookDesign.Size.essentialsTile + CGFloat(cols - 1) * NookDesign.Spacing.sm
            if needed <= width { break }
            cols -= 1
        }
        return max(1, cols)
    }

    private func makeColumns(count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: NookDesign.Size.essentialsTile),
                spacing: NookDesign.Spacing.sm,
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
                action: { tabs.select(item.id, in: windowState) }
            )
            .frame(maxWidth: .infinity)
            .contextMenu {
                TabContextMenu(itemID: item.id, context: .favorite)
                    .environment(windowState)
                    .environment(tabs)
                    .environment(\.tabActions, browserManager)
            }
            .onHoverTracking { hovering in
                browserManager.hoveredPinnedTabId = hovering ? item.id : nil
            }
        }
    }
}
