import AppKit
import SwiftUI

final class TabCollectionViewItem: NSCollectionViewItem {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("TabCollectionViewItem")

    private(set) var tab: Tab?
    private var dataSource: (any TabListDataSource)?
    private weak var browserManager: BrowserManager?

    private var hostingView: NSHostingView<AnyView>?

    override func loadView() {
        self.view = NSView()
        self.view.translatesAutoresizingMaskIntoConstraints = false
        self.view.wantsLayer = true
        self.view.layer?.backgroundColor = NSColor.clear.cgColor
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        if let hv = hostingView { hv.removeFromSuperview() }
        hostingView = nil
        tab = nil
        dataSource = nil
        browserManager = nil
        self.view.menu = nil
    }

    func configure(with tab: Tab, dataSource: TabListDataSource, browserManager: BrowserManager) {
        self.tab = tab
        self.dataSource = dataSource
        self.browserManager = browserManager

        // Action callback resolves current index by id to be robust to reorders
        let action: () -> Void = { [weak self] in
            guard let self = self,
                  let ds = self.dataSource,
                  let t = self.tab,
                  let idx = ds.tabs.firstIndex(where: { $0.id == t.id }) else { return }
            ds.selectTab(at: idx)
        }

        // Host view computes isActive reactively from BrowserManager
        let content = PinnedTileHost(tab: tab, action: action)
            .environmentObject(browserManager)
            .allowsHitTesting(false) // Let NSCollectionView handle mouse for selection/drag
            .eraseToAnyView()

        let hv = NSHostingView(rootView: content)
        hv.translatesAutoresizingMaskIntoConstraints = false
        if let prev = hostingView { prev.removeFromSuperview() }
        hostingView = hv
        view.addSubview(hv)

        NSLayoutConstraint.activate([
            hv.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hv.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hv.topAnchor.constraint(equalTo: view.topAnchor),
            hv.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        // Attach context menu from data source
        if let idx = dataSource.tabs.firstIndex(where: { $0.id == tab.id }) {
            self.view.menu = dataSource.contextMenuForTab(at: idx)
        } else {
            self.view.menu = nil
        }
    }

    private func safeTitle(_ tab: Tab) -> String {
        let t = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (tab.url.host ?? "New Tab") : t
    }
}

// Small helper to type‑erase SwiftUI views for NSHostingView<AnyView>
private extension View {
    func eraseToAnyView() -> AnyView { AnyView(self) }
}

// MARK: - SwiftUI host for pinned tile with reactive active state
private struct PinnedTileHost: View {
    @EnvironmentObject var browserManager: BrowserManager
    let tab: Tab
    let action: () -> Void

    var body: some View {
        let isActive = browserManager.tabManager.currentTab?.id == tab.id
        PinnedTabView(
            tabName: safeTitle(tab),
            tabURL: tab.url.absoluteString,
            tabIcon: tab.favicon,
            isActive: isActive,
            action: action
        )
    }

    private func safeTitle(_ tab: Tab) -> String {
        let t = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? (tab.url.host ?? "New Tab") : t
    }
}

// (No special container; NSCollectionView handles mouse. SwiftUI content is non-interactive.)
