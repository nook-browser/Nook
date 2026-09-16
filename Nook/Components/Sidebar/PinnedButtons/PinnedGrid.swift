//
//      PinnedGrid.swift
//      Nook
//
//      Created by Maciek Bagiński on 30/07/2025.
//
import NookTabsCore
import SwiftUI
import UniformTypeIdentifiers

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
                    LazyVGrid(columns: columns, alignment: .center, spacing: NookDesign.Spacing.sm) {
                        let insertionIdx = insertionIndex(in: zone, items: items)

                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let isDraggedItem = dragSession.draggedItem?.tabId == item.id

                            if let ins = insertionIdx, ins == index, !isDraggedItem {
                                essentialsPlaceholder
                            }

                            PinnedTile(item: item, zone: zone)
                                .opacity(isDraggedItem ? 0.0 : 1.0)
                        }

                        if let ins = insertionIdx, ins >= items.count {
                            essentialsPlaceholder
                        }
                    }
                    .animation(NookDesign.Motion.spring, value: insertionIndex(in: zone, items: items))
                }
                .contentShape(Rectangle())
                .fixedSize(horizontal: false, vertical: true)
                .animation(shouldAnimate ? NookDesign.Motion.standard : nil, value: colsCount)
                .animation(shouldAnimate ? NookDesign.Motion.standard : nil, value: items.count)
                .allowsHitTesting(!browserManager.isSwitchingSpace)
            }
        }
    }

    /// The insertion index for the grid during a drag, or nil when no placeholder should show.
    private func insertionIndex(in zone: DropZoneID, items: [Item]) -> Int? {
        guard dragSession.isDragging, dragSession.activeZone == zone,
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
                    .environmentObject(browserManager)
                    .environment(windowState)
            }
            .onHoverTracking { hovering in
                browserManager.hoveredPinnedTabId = hovering ? item.id : nil
            }
        }
    }
}
