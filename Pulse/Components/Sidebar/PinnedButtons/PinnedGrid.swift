//    
//      PinnedGrid.swift
//      Pulse
//    
//      Created by Maciek Bagiński on 30/07/2025.
//    
import SwiftUI
import UniformTypeIdentifiers

struct PinnedGrid: View {
    let minButtonWidth: CGFloat = 50
    let itemSpacing: CGFloat = 8
    let rowSpacing: CGFloat = 6
    let maxColumns: Int = 3

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.tabDragManager) private var dragManager
    @State private var availableWidth: CGFloat = 0
    @State private var cellFrames: [Int: CGRect] = [:] // local frames in grid space
    @State private var cachedBoundaries: [SidebarGridBoundary] = []

    var body: some View {
        let items: [Tab] = browserManager.tabManager.pinnedTabs
        let colsCount: Int = columnCount(for: availableWidth, itemCount: items.count)
        let columns: [GridItem] = makeColumns(count: colsCount)
        let boundaries = computeBoundaries(colsCount: colsCount)

        VStack(spacing: 6) {
            ZStack(alignment: .top) {
                LazyVGrid(columns: columns, alignment: .center, spacing: rowSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, tab in
                        let isActive: Bool = (browserManager.tabManager.currentTab?.id == tab.id)
                        let title: String = safeTitle(tab)

                        PinnedTile(
                            title: title,
                            urlString: tab.url.absoluteString,
                            icon: tab.favicon,
                            isActive: isActive,
                            onActivate: { browserManager.tabManager.setActiveTab(tab) },
                            onClose: { browserManager.tabManager.removeTab(tab.id) },
                            onRemovePin: { browserManager.tabManager.unpinTab(tab) }
                        )
                        .draggableTab(
                            tab: tab,
                            container: .essentials,
                            index: index,
                            dragManager: dragManager ?? TabDragManager.shared
                        )
                        .background(GeometryReader { proxy in
                            // Record each tile's frame in local grid coordinate space
                            let local = proxy.frame(in: .named("PinnedGridSpace"))
                            Color.clear.preference(key: PinnedGridCellFramesKey.self, value: [index: local])
                        })
                    }
                }
                // Ensure a reasonable drop surface when grid is empty
                if items.isEmpty {
                    Color.clear.frame(height: 44)
                }
            }
            .coordinateSpace(name: "PinnedGridSpace")
            .onPreferenceChange(PinnedGridCellFramesKey.self) { frames in
                cellFrames = frames
                cachedBoundaries = computeBoundaries(colsCount: colsCount)
            }
            .contentShape(Rectangle())
            .overlay(SidebarGridInsertionOverlay(
                isActive: (dragManager ?? TabDragManager.shared).isDragging && (dragManager ?? TabDragManager.shared).dropTarget == .essentials,
                index: max((dragManager ?? TabDragManager.shared).insertionIndex, 0),
                boundaries: boundaries
            ))
            .onDrop(of: [.text], delegate: SidebarGridDropDelegate(
                dragManager: (dragManager ?? TabDragManager.shared),
                boundariesProvider: { boundaries },
                onPerform: { op in browserManager.tabManager.handleDragOperation(op) }
            ))
            .fixedSize(horizontal: false, vertical: true)
        }
        .background(widthReader)
        .animation(.easeInOut(duration: 0.18), value: colsCount)
        .animation(.easeInOut(duration: 0.18), value: items.count)
    }

    private var widthReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { availableWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, newWidth in
                    availableWidth = newWidth
                }
        }
    }

    private func safeTitle(_ tab: Tab) -> String {
        let t = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (tab.url.host ?? "New Tab") : t
    }

    private func columnCount(for width: CGFloat, itemCount: Int) -> Int {
        guard width > 0, itemCount > 0 else { return 1 }
        var cols = min(maxColumns, itemCount)
        while cols > 1 {
            let needed = CGFloat(cols) * minButtonWidth + CGFloat(cols - 1) * itemSpacing
            if needed <= width { break }
            cols -= 1
        }
        return max(1, cols)
    }

    private func makeColumns(count: Int) -> [GridItem] {
        Array(
            repeating: GridItem(
                .flexible(minimum: minButtonWidth),
                spacing: itemSpacing,
                alignment: .center
            ),
            count: count
        )
    }
    
    private func computeBoundaries(colsCount: Int) -> [SidebarGridBoundary] {
        let cw = SidebarDropMath.estimatedGridWidth(from: cellFrames)
        var boundaries = SidebarDropMath.computeGridBoundaries(
            frames: cellFrames,
            columns: colsCount,
            containerWidth: cw > 0 ? cw : max(availableWidth, minButtonWidth),
            gridGap: itemSpacing
        )
        if boundaries.isEmpty {
            let fh: CGFloat = 44
            let f = CGRect(x: 0, y: fh/2 - 1.5, width: max(availableWidth, minButtonWidth), height: 3)
            boundaries = [SidebarGridBoundary(index: 0, orientation: .horizontal, frame: f)]
        }
        return boundaries
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
private struct PinnedGridCellFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGRect] = [:]
    static func reduce(value: inout [Int: CGRect], nextValue: () -> [Int: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}


