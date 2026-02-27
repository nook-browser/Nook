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
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(WindowRegistry.self) private var windowRegistry
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.nookSettings) var nookSettings
    @ObservedObject private var dragSession = NookDragSessionManager.shared

    init(width: CGFloat, profileId: UUID? = nil) {
        self.width = width
        self.profileId = profileId
    }

    var body: some View {
        let pinnedTabsConfiguration: PinnedTabsConfiguration = nookSettings.pinnedTabsLook
        // Use profile-filtered essentials
        let effectiveProfileId = profileId ?? windowState.currentProfileId ?? browserManager.currentProfile?.id
        let items: [Tab] = effectiveProfileId != nil
            ? browserManager.tabManager.essentialTabs(for: effectiveProfileId)
            : []
        let colsCount: Int = columnCount(for: width, itemCount: items.count)
        let columns: [GridItem] = makeColumns(count: colsCount)

        let shouldAnimate = (windowRegistry.activeWindow?.id == windowState.id) && !browserManager.isTransitioningProfile

        // For embedded use, return proper sized container even when empty to support transitions
        if items.isEmpty {
            let isDragging = dragSession.isDragging

            return AnyView(
                NookDropZoneHostView(
                    zoneID: .essentials,
                    isVertical: false,
                    manager: dragSession
                ) {
                    VStack(spacing: 8) {
                        Image(systemName: "star.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)

                        VStack(spacing: 2) {
                            Text("Drag to add Favorites")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)

                            Text("Favorites keep your most\nused sites and apps close")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.tertiary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .padding(.horizontal, 12)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
                            .foregroundStyle(isDragging ? Color.primary.opacity(0.4) : Color.secondary.opacity(0.3))
                    }
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isDragging
                                ? (colorScheme == .dark ? AppColors.pinnedTabHoverLight : AppColors.pinnedTabHoverDark)
                                : Color.clear
                            )
                    }
                    .animation(.easeInOut(duration: 0.15), value: isDragging)
                }
                .onAppear {
                    dragSession.pinnedTabsConfig = pinnedTabsConfiguration
                    dragSession.itemCellSize[.essentials] = pinnedTabsConfiguration.minWidth
                    dragSession.itemCellSpacing[.essentials] = pinnedTabsConfiguration.gridSpacing
                    dragSession.itemCounts[.essentials] = 0
                    dragSession.gridColumnCount[.essentials] = colsCount
                }
                .onChange(of: dragSession.pendingDrop) { _, drop in
                    handleEssentialsDrop(drop, items: [])
                }
            )
        }

        return AnyView(ZStack { // Container to support transitions
            VStack(spacing: 6) {
                ZStack(alignment: .top) {
                    NookDropZoneHostView(
                        zoneID: .essentials,
                        isVertical: false,
                        manager: dragSession
                    ) {
                        LazyVGrid(columns: columns, alignment: .center, spacing: pinnedTabsConfiguration.gridSpacing) {
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
                                        title: title,
                                        urlString: tab.url.absoluteString,
                                        icon: tab.favicon,
                                        isActive: isActive,
                                        onActivate: { browserManager.selectTab(tab, in: windowState) },
                                        onClose: { browserManager.tabManager.removeTab(tab.id) },
                                        onRemovePin: { browserManager.tabManager.unpinTab(tab) },
                                        onSplitRight: { browserManager.splitManager.enterSplit(with: tab, placeOn: .right, in: windowState) },
                                        onSplitLeft: { browserManager.splitManager.enterSplit(with: tab, placeOn: .left, in: windowState) }
                                    )
                                    .environmentObject(browserManager)
                                }
                                .opacity(isDraggedItem ? 0.0 : 1.0)
                            }

                            // Insertion placeholder at the end
                            if let ins = insertionIdx, ins >= items.count {
                                essentialsPlaceholder
                            }
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: essentialsInsertionIndex(itemCount: items.count))
                    }
                    .onAppear {
                        dragSession.pinnedTabsConfig = pinnedTabsConfiguration
                        dragSession.itemCellSize[.essentials] = pinnedTabsConfiguration.minWidth
                        dragSession.itemCellSpacing[.essentials] = pinnedTabsConfiguration.gridSpacing
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
        .animation(shouldAnimate ? .easeInOut(duration: 0.18) : nil, value: colsCount)
        .animation(shouldAnimate ? .easeInOut(duration: 0.18) : nil, value: items.count)
        .allowsHitTesting(!browserManager.isTransitioningProfile)
        .onChange(of: dragSession.pendingDrop) { _, drop in
            handleEssentialsDrop(drop, items: items)
        }
        .onChange(of: dragSession.pendingReorder) { _, reorder in
            handleEssentialsReorder(reorder, items: items)
        }
        )
    }

    // MARK: - Drop Handling

    private func handleEssentialsDrop(_ drop: PendingDrop?, items: [Tab]) {
        guard let drop = drop, drop.targetZone == .essentials else { return }
        let allTabs = browserManager.tabManager.allTabs()
        guard let tab = allTabs.first(where: { $0.id == drop.item.tabId }) else { return }
        let op = dragSession.makeDragOperation(from: drop, tab: tab)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            browserManager.tabManager.handleDragOperation(op)
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            browserManager.tabManager.handleDragOperation(op)
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
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.primary.opacity(0.08))
            .frame(minWidth: nookSettings.pinnedTabsLook.minWidth, minHeight: nookSettings.pinnedTabsLook.minWidth)
    }

    private func safeTitle(_ tab: Tab) -> String {
        let t = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (tab.url.host ?? "New Tab") : t
    }

    private func columnCount(for width: CGFloat, itemCount: Int) -> Int {
        guard width > 0, itemCount > 0 else { return 1 }
        var cols = min(nookSettings.pinnedTabsLook.maxColumns, itemCount)
        while cols > 1 {
            let needed = CGFloat(cols) * nookSettings.pinnedTabsLook.minWidth + CGFloat(cols - 1) * nookSettings.pinnedTabsLook.gridSpacing
            if needed <= width { break }
            cols -= 1
        }
        return max(1, cols)
    }

    private func makeColumns(count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: nookSettings.pinnedTabsLook.minWidth),
                spacing: nookSettings.pinnedTabsLook.gridSpacing,
                alignment: .center
            ),
            count: count
        )
    }
}

private struct PinnedTile: View {
    let title: String
    let urlString: String
    let icon: Image
    let isActive: Bool
    let onActivate: () -> Void
    let onClose: () -> Void
    let onRemovePin: () -> Void
    let onSplitRight: () -> Void
    let onSplitLeft: () -> Void

    var body: some View {
        PinnedTabView(
            tabName: title,
            tabURL: urlString,
            tabIcon: icon,
            isActive: isActive,
            action: onActivate
        )
        .frame(maxWidth: .infinity)
        .contextMenu {
            Button(action: onSplitRight) {
                Label("Open in Split (Right)", systemImage: "rectangle.split.2x1")
            }
            Button(action: onSplitLeft) {
                Label("Open in Split (Left)", systemImage: "rectangle.split.2x1")
            }
            Divider()
            Button(role: .destructive, action: onClose) {
                Label("Close tab", systemImage: "xmark")
            }
            Button(action: onRemovePin) {
                Label("Remove pinned tab", systemImage: "pin.slash")
            }
        }
    }
}

// MARK: - Preference Keys
// no-op
