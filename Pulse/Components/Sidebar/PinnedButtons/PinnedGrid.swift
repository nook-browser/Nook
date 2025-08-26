//    
//      PinnedGrid.swift
//      Pulse
//    
//      Created by Maciek Bagiński on 30/07/2025.
//    
import SwiftUI

struct PinnedGrid: View {
    let minButtonWidth: CGFloat = 50
    let itemSpacing: CGFloat = 8
    let rowSpacing: CGFloat = 6
    let maxColumns: Int = 3

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.tabDragManager) private var dragManager
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        let items: [Tab] = browserManager.tabManager.pinnedTabs
        let colsCount: Int = columnCount(for: availableWidth, itemCount: items.count)
        let columns: [GridItem] = makeColumns(count: colsCount)

        VStack(spacing: 6) {
            if !items.isEmpty {
                LazyVGrid(columns: columns, alignment: .center, spacing: rowSpacing) {
                    ForEach(items.indices, id: \.self) { index in
                        let tab = items[index]
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
                            dragManager: dragManager ?? TabDragManager()
                        )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
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
