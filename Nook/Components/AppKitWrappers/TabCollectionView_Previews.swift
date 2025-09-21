import AppKit
import SwiftUI

@MainActor
final class MockEssentialTabListDataSource: TabListDataSource, ObservableObject {
    @Published var tabs: [Tab]

    init(sampleCount: Int = 8) {
        var arr: [Tab] = []
        let urls = [
            "https://www.apple.com",
            "https://www.google.com",
            "https://github.com",
            "https://stackoverflow.com",
            "https://developer.apple.com",
            "https://news.ycombinator.com",
            "http://localhost:3000",
            "file:///Users/me/Documents/readme.html",
        ]
        for i in 0 ..< sampleCount {
            let urlStr = urls[i % urls.count]
            let nameVariants = [
                "Docs",
                "Apple",
                "A very very long tab name to test truncation",
                "HN",
                "Localhost",
                "GitHub",
                "Stack Overflow",
                "Preview",
            ]
            let t = Tab(
                url: URL(string: urlStr)!,
                name: nameVariants[i % nameVariants.count],
                favicon: "globe",
                spaceId: nil,
                index: i
            )
            arr.append(t)
        }
        // Simulate audio state for one tab
        if arr.indices.contains(1) { arr[1].hasAudioContent = true }
        tabs = arr
    }

    func moveTab(from sourceIndex: Int, to targetIndex: Int) {
        guard sourceIndex < tabs.count, targetIndex <= tabs.count else { return }
        objectWillChange.send()
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: targetIndex)
        print("[Preview] Moved tab from \(sourceIndex) to \(targetIndex)")
    }

    func selectTab(at index: Int) {
        guard index < tabs.count else { return }
        print("[Preview] Selected tab: \(tabs[index].name)")
    }

    func closeTab(at index: Int) {
        guard index < tabs.count else { return }
        objectWillChange.send()
        print("[Preview] Close tab: \(tabs[index].name)")
        tabs.remove(at: index)
    }

    func toggleMuteTab(at index: Int) {
        guard index < tabs.count else { return }
        print("[Preview] Toggle mute: \(tabs[index].name)")
    }

    func contextMenuForTab(at index: Int) -> NSMenu? {
        guard index < tabs.count else { return nil }
        let menu = NSMenu()
        let test = NSMenuItem(title: "Test Action", action: nil, keyEquivalent: "")
        menu.addItem(test)
        let remove = NSMenuItem(title: "Remove", action: nil, keyEquivalent: "")
        menu.addItem(remove)
        return menu
    }
}

struct TabCollectionView_Previews: PreviewProvider {
    static var previews: some View {
        TabCollectionViewPreviewContainer()
    }
}

struct TabCollectionViewPreviewContainer: View {
    @StateObject private var ds = MockEssentialTabListDataSource(sampleCount: 8)
    @State private var width: CGFloat = 260
    private let height: CGFloat = 400

    var body: some View {
        let browserManager = BrowserManager()
        return VStack(alignment: .leading, spacing: 12) {
            Text("TabCollectionView Preview").font(.headline)
            ZStack {
                Color(NSColor.windowBackgroundColor).opacity(0.6)
                TabCollectionView(dataSource: ds, availableWidth: width)
                    .environmentObject(browserManager)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))

            HStack {
                Text("Width: \(Int(width))")
                Slider(value: $width, in: 180 ... 320)
            }
        }
        .padding()
        .frame(width: 360, height: 520)
    }
}

#Preview {
    TabCollectionView_Previews.previews
}

// MARK: - Real data preview using EssentialTabListAdapter

struct TabCollectionView_RealDataPreviewContainer: View {
    @StateObject private var adapter: EssentialTabListAdapter
    private let browserManager: BrowserManager
    @State private var width: CGFloat = 260
    private let height: CGFloat = 400

    init() {
        let bm = BrowserManager()
        // Seed a few tabs and pin them to essentials
        let urls = [
            ("Apple", "https://www.apple.com"),
            ("Google", "https://www.google.com"),
            ("GitHub", "https://github.com"),
            ("Stack Overflow", "https://stackoverflow.com"),
            ("Hacker News", "https://news.ycombinator.com"),
            ("Developer", "https://developer.apple.com"),
        ]
        for (name, link) in urls {
            if let url = URL(string: link) {
                let t = Tab(url: url, name: name)
                bm.tabManager.addTab(t)
                bm.tabManager.pinTab(t)
            }
        }
        if let first = bm.tabManager.pinnedTabs.first {
            bm.tabManager.setActiveTab(first)
        }
        browserManager = bm
        _adapter = StateObject(wrappedValue: EssentialTabListAdapter(tabManager: bm.tabManager))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Real Essentials Adapter Preview").font(.headline)
            ZStack {
                Color(NSColor.windowBackgroundColor).opacity(0.6)
                TabCollectionView(dataSource: adapter, availableWidth: width)
                    .environmentObject(browserManager)
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.1), lineWidth: 1))

            HStack {
                Text("Width: \(Int(width))")
                Slider(value: $width, in: 180 ... 320)
            }
        }
        .padding()
        .frame(width: 360, height: 520)
    }
}

#Preview("Real Essentials Data") {
    TabCollectionView_RealDataPreviewContainer()
}
