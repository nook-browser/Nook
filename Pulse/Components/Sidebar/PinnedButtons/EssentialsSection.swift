import SwiftUI

struct EssentialsSection: View {
    @EnvironmentObject var browserManager: BrowserManager
    @StateObject private var adapter: EssentialTabListAdapter

    init(tabManager: TabManager) {
        _adapter = StateObject(wrappedValue: EssentialTabListAdapter(tabManager: tabManager))
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let count = adapter.tabs.count
            let cols = EssentialsGridLayout.columnCount(for: width, itemCount: count)
            let rows = max(1, Int(ceil(Double(max(1, count)) / Double(cols))))
            let height = CGFloat(rows) * EssentialsGridLayout.tileHeight + CGFloat(max(0, rows - 1)) * EssentialsGridLayout.lineSpacing + 4 // padding to avoid clipping during drag

            ZStack(alignment: .top) {
                TabCollectionView(
                    dataSource: adapter,
                    availableWidth: width
                )
                .environmentObject(browserManager)
                .frame(height: height)
            }
            .frame(height: height)
            .background(Color.blue.opacity(0.08)) // debug: essentials section bounds
        }
        .frame(minHeight: 30)
    }
}
