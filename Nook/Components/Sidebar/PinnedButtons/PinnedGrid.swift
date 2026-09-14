//
//      PinnedGrid.swift
//      Nook
//
//      Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI
import UniformTypeIdentifiers

struct PinnedGrid: View {
    let width: CGFloat
    let profileId: UUID?


    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var tabManager: TabManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @ObservedObject private var dragSession = NookDragSessionManager.shared
    private let maxColumns = 4

    init(width: CGFloat, profileId: UUID? = nil) {
        self.width = width
        self.profileId = profileId
    }

    @ViewBuilder
    var body: some View {
        // Use profile-filtered essentials
        let effectiveProfileId = profileId ?? windowState.currentProfileId ?? browserManager.currentProfile?.id
        let items: [Tab] = effectiveProfileId != nil
            ? tabManager.essentialTabs(for: effectiveProfileId)
            : []
        let colsCount: Int = columnCount(for: width, itemCount: items.count)
        let columns: [GridItem] = makeColumns(count: colsCount)

        let shouldAnimate = (windowRegistry.activeWindow?.id == windowState.id) && !browserManager.isTransitioningProfile

        // For embedded use, return proper sized container even when empty to support transitions
        if items.isEmpty {
            let isDragging = dragSession.isDragging

            NookDropZoneHostView(
                zoneID: .essentials,
                isVertical: false,
                manager: dragSession
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
            .onAppear {
                dragSession.itemCellSize[.essentials] = NookDesign.Size.essentialsTile
                dragSession.itemCellSpacing[.essentials] = NookDesign.Spacing.sm
                dragSession.itemCounts[.essentials] = 0
                dragSession.gridColumnCount[.essentials] = colsCount
            }
            .onChange(of: dragSession.pendingDrop) { _, drop in
                handleEssentialsDrop(drop, items: [])
            }
        } else {
            ZStack { // Container to support transitions
                VStack(spacing: NookDesign.Spacing.sm) {
                    ZStack(alignment: .top) {
                        NookDropZoneHostView(
                            zoneID: .essentials,
                            isVertical: false,
                            manager: dragSession
                        ) {
                            LazyVGrid(columns: columns, alignment: .center, spacing: NookDesign.Spacing.sm) {
                                let insertionIdx = essentialsInsertionIndex(itemCount: items.count)

                                ForEach(Array(items.enumerated()), id: \.element.id) { index, tab in
                                    let isActive: Bool = (browserManager.currentTab(for: windowState)?.id == tab.id)
                                    let title: String = safeTitle(tab)
                                    let isDraggedItem = dragSession.draggedItem?.tabId == tab.id

                                    // Insert a placeholder before this item if insertion index matches
                                    if let ins = insertionIdx, ins == index, !isDraggedItem {
                                        essentialsPlaceholder
                                    }

                                    NookDragSourceView(
                                        item: NookDragItem(tabId: tab.id, title: title, urlString: tab.url.absoluteString),
                                        tab: tab,
                                        zoneID: .essentials,
                                        index: index,
                                        manager: dragSession
                                    ) {
                                        PinnedTile(
                                            tab: tab,
                                            title: title,
                                            urlString: tab.url.absoluteString,
                                            icon: tab.favicon,
                                            isActive: isActive,
                                            onActivate: { browserManager.selectTab(tab, in: windowState) }
                                        )
                                        .environmentObject(browserManager)
                                        .onHoverTracking { hovering in
                                            browserManager.hoveredPinnedTabId = hovering ? tab.id : nil
                                        }
                                    }
                                    .opacity(isDraggedItem ? 0.0 : 1.0)
                                }

                                // Insertion placeholder at the end
                                if let ins = insertionIdx, ins >= items.count {
                                    essentialsPlaceholder
                                }
                            }
                            .animation(NookDesign.Motion.spring, value: essentialsInsertionIndex(itemCount: items.count))
                        }
                        .onAppear {
                            dragSession.itemCellSize[.essentials] = NookDesign.Size.essentialsTile
                            dragSession.itemCellSpacing[.essentials] = NookDesign.Spacing.sm
                            dragSession.itemCounts[.essentials] = items.count
                            dragSession.gridColumnCount[.essentials] = colsCount
                        }
                        .onChange(of: items.count) { _, newCount in
                            dragSession.itemCounts[.essentials] = newCount
                        }
                        .onChange(of: colsCount) { _, newCols in
                            dragSession.gridColumnCount[.essentials] = newCols
                        }
                    }
                    .contentShape(Rectangle())
                    .fixedSize(horizontal: false, vertical: true)
                }
                // Natural updates; avoid cross-profile transition artifacts
            }
            .animation(shouldAnimate ? NookDesign.Motion.standard : nil, value: colsCount)
            .animation(shouldAnimate ? NookDesign.Motion.standard : nil, value: items.count)
            .allowsHitTesting(!browserManager.isTransitioningProfile)
            .onChange(of: dragSession.pendingDrop) { _, drop in
                handleEssentialsDrop(drop, items: items)
            }
            .onChange(of: dragSession.pendingReorder) { _, reorder in
                handleEssentialsReorder(reorder, items: items)
            }
        }
    }

    // MARK: - Drop Handling

    private func handleEssentialsDrop(_ drop: PendingDrop?, items: [Tab]) {
        guard let drop = drop, drop.targetZone == .essentials else { return }
        let allTabs = tabManager.allTabs()
        guard let tab = allTabs.first(where: { $0.id == drop.item.tabId }) else { return }
        let op = dragSession.makeDragOperation(from: drop, tab: tab)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragSession.clearDrag()
            tabManager.handleDragOperation(op)
        }
        dragSession.pendingDrop = nil
    }

    private func handleEssentialsReorder(_ reorder: PendingReorder?, items: [Tab]) {
        guard let reorder = reorder, reorder.zone == .essentials else { return }
        guard reorder.fromIndex < items.count else {
            dragSession.pendingReorder = nil
            return
        }
        let tab = items[reorder.fromIndex]
        let op = dragSession.makeDragOperation(from: reorder, tab: tab)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragSession.clearDrag()
            tabManager.handleDragOperation(op)
        }
        dragSession.pendingReorder = nil
    }

    /// Returns the insertion index for the essentials grid during a drag, or nil if no insertion should be shown.
    private func essentialsInsertionIndex(itemCount: Int) -> Int? {
        guard dragSession.isDragging,
              dragSession.activeZone == .essentials,
              let idx = dragSession.insertionIndex[.essentials] else {
            return nil
        }
        // During same-zone reorder, skip showing placeholder at the dragged item's original position
        if dragSession.sourceZone == .essentials,
           let from = dragSession.sourceIndex,
           idx == from {
            return nil
        }
        return idx
    }

    private var essentialsPlaceholder: some View {
        NookDesign.Radius.shape(NookDesign.Radius.lg)
            .fill(NookDesign.Surface.fillPressed)
            .frame(minWidth: NookDesign.Size.essentialsTile, minHeight: NookDesign.Size.essentialsTile)
    }

    private func safeTitle(_ tab: Tab) -> String {
        let t = tab.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (tab.url.host ?? "New Tab") : t
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
    @ObservedObject var tab: Tab
    let title: String
    let urlString: String
    let icon: Image
    let isActive: Bool
    let onActivate: () -> Void

    var body: some View {
        PinnedTabView(
            tabName: title,
            tabURL: urlString,
            tabIcon: icon,
            isActive: isActive,
            isUnloaded: tab.isUnloaded,
            action: onActivate
        )
        .frame(maxWidth: .infinity)
        .contextMenu {
            TabContextMenu(tab: tab, context: .essential)
        }
    }
}

// MARK: - Preference Keys
// no-op
