import SwiftUI
import AppKit
import Combine // Added for Combine

enum TabRowMetrics {
    static let rowHeight: CGFloat = 40
}

/// NSViewRepresentable wrapper for NSTableView with native AppKit drag & drop
struct TabTableView<DataSource: TabListDataSource & ObservableObject>: NSViewRepresentable {
    @ObservedObject var dataSource: DataSource
    @EnvironmentObject var browserManager: BrowserManager
    
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let tableView = NSTableView()
        
        // Configure table view
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        tableView.rowHeight = TabRowMetrics.rowHeight // Match SpaceTab height
        tableView.selectionHighlightStyle = .none
        tableView.backgroundColor = NSColor.clear
        tableView.headerView = nil
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        
        // Configure column
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("TabColumn"))
        column.width = 200
        column.minWidth = 100
        column.maxWidth = .greatestFiniteMagnitude
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        
        // Configure drag & drop
        tableView.registerForDraggedTypes([PasteboardType.tab])
        tableView.setDraggingSourceOperationMask(.move, forLocal: true)
        tableView.setDraggingSourceOperationMask(.move, forLocal: false)
        tableView.draggingDestinationFeedbackStyle = .gap
        
        // Hook coordinator to table view for change notifications
        context.coordinator.tableView = tableView

        // Layout: have the table view fill the scroll view's content area
        tableView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        NSLayoutConstraint.activate([
            tableView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            tableView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            tableView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            tableView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        
        // Debug visuals to confirm sizing/hit-testing
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.12).cgColor
        tableView.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.12)

        return scrollView
    }
    
    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let tableView = scrollView.documentView as? NSTableView else { return }
        
        // Update coordinator with new data source
        context.coordinator.parent = self
        context.coordinator.tableView = tableView
        context.coordinator.resubscribeIfNeeded(to: dataSource)
        
        // Reload table data when tabs change
        tableView.reloadData()

        // Force layout update to avoid stale geometry
        DispatchQueue.main.async {
            tableView.needsLayout = true
            tableView.layoutSubtreeIfNeeded()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var parent: TabTableView<DataSource>
        private var cancellable: AnyCancellable?
        private var dataSourceSubscription: AnyCancellable?
        private var subscribedDataSourceID: ObjectIdentifier?
        weak var tableView: NSTableView?
        
        init(_ parent: TabTableView<DataSource>) {
            self.parent = parent
            super.init()
            
            // Initial subscription to parent data source
            resubscribeIfNeeded(to: parent.dataSource)
        }
        
        // MARK: - NSTableViewDataSource
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            return parent.dataSource.tabs.count
        }
        
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard row < parent.dataSource.tabs.count else { return nil }

            let tab = parent.dataSource.tabs[row]
            let cellView = MouseTransparentTableCellView()

            // Create NSHostingView with existing SpaceTab component
            let capturedTab = tab
            let spaceTab = SpaceTab(
                tab: capturedTab,
                action: { [weak self] in
                    if let idx = self?.parent.dataSource.tabs.firstIndex(where: { $0.id == capturedTab.id }) {
                        self?.parent.dataSource.selectTab(at: idx)
                    }
                },
                onClose: { [weak self] in
                    if let idx = self?.parent.dataSource.tabs.firstIndex(where: { $0.id == capturedTab.id }) {
                        self?.parent.dataSource.closeTab(at: idx)
                    }
                },
                onMute: { [weak self] in
                    if let idx = self?.parent.dataSource.tabs.firstIndex(where: { $0.id == capturedTab.id }) {
                        self?.parent.dataSource.toggleMuteTab(at: idx)
                    }
                }
            )
            .environmentObject(parent.browserManager) // Inject BrowserManager

            let hostingView = NSHostingView(rootView: spaceTab)
            hostingView.translatesAutoresizingMaskIntoConstraints = false

            cellView.addSubview(hostingView)

            // Set up constraints
            NSLayoutConstraint.activate([
                hostingView.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
                hostingView.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
                hostingView.topAnchor.constraint(equalTo: cellView.topAnchor),
                hostingView.bottomAnchor.constraint(equalTo: cellView.bottomAnchor)
            ])

            // Attach context menu provided by data source
            cellView.menu = parent.dataSource.contextMenuForTab(at: row)

            return cellView
        }
        
        // MARK: - Drag & Drop
        
        func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
            guard row < parent.dataSource.tabs.count else { return nil }
            
            let tab = parent.dataSource.tabs[row]
            let pasteboardItem = NSPasteboardItem()
            pasteboardItem.setString(tab.id.uuidString, forType: PasteboardType.tab)
#if DEBUG
            print("[DnD] TabTableView pasteboardWriterForRow row=\(row)")
#endif
            return pasteboardItem
        }
        
        func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation dropOperation: NSTableView.DropOperation) -> NSDragOperation {
            // Allow drops between rows when the pasteboard contains a tab id, regardless of source
            guard dropOperation == .above else { return [] }
            let hasTab = info.draggingPasteboard.types?.contains(PasteboardType.tab) ?? false
            return hasTab ? .move : []
        }
        
        func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
            guard let pasteboardItems = info.draggingPasteboard.pasteboardItems,
                  let firstItem = pasteboardItems.first,
                  let tabIdString = firstItem.string(forType: PasteboardType.tab),
                  let tabId = UUID(uuidString: tabIdString) else {
                return false
            }
            
            // Find source index
            if let sourceIndex = parent.dataSource.tabs.firstIndex(where: { $0.id == tabId }) {
                // Local reorder
                var targetIndex = row
                if sourceIndex < row { targetIndex -= 1 }
                parent.dataSource.moveTab(from: sourceIndex, to: targetIndex)
                DispatchQueue.main.async { tableView.reloadData() }
                return true
            }

            // Cross-container move
            guard let bm = parent.browserManager as BrowserManager? else { return false }
            let tm = bm.tabManager

            // Resolve the tab by id by searching essentials and all spaces
            let allSpaces = tm.spaces
            let allSpacePinned = allSpaces.flatMap { tm.spacePinnedTabs(for: $0.id) }
            let allRegular = allSpaces.flatMap { tm.tabs(in: $0) }
            let allEssentials = tm.essentialTabs
            guard let tab = (allEssentials + allSpacePinned + allRegular).first(where: { $0.id == tabId }) else { return false }

            // Determine target container by adapter type
            if let pinnedAdapter = parent.dataSource as? SpacePinnedTabListAdapter {
                let spaceId = pinnedAdapter.spaceId
                tm.pinTabToSpace(tab, spaceId: spaceId)
                tm.reorderSpacePinned(tab, in: spaceId, to: row)
            } else if let regularAdapter = parent.dataSource as? SpaceRegularTabListAdapter {
                let spaceId = regularAdapter.spaceId
                // Move to regular via pin→unpin trick to ensure placement in correct space
                tm.pinTabToSpace(tab, spaceId: spaceId)
                tm.unpinTabFromSpace(tab)
                tm.reorderRegular(tab, in: spaceId, to: row)
            } else {
                // Unknown adapter; fallback to no-op
                return false
            }

            DispatchQueue.main.async { tableView.reloadData() }
            return true
        }
        
        // MARK: - Selection
        
        func tableViewSelectionDidChange(_ notification: Notification) {
            guard let tableView = notification.object as? NSTableView else { return }
            
            let selectedRow = tableView.selectedRow
            if selectedRow >= 0 && selectedRow < parent.dataSource.tabs.count {
                parent.dataSource.selectTab(at: selectedRow)
            }
        }
        
        // MARK: - Subscription management
        func resubscribeIfNeeded(to dataSource: DataSource) {
            let newID = ObjectIdentifier(dataSource)
            guard newID != subscribedDataSourceID else { return }
            subscribedDataSourceID = newID
            dataSourceSubscription?.cancel()
            dataSourceSubscription = dataSource.objectWillChange
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in
                    self?.tableView?.reloadData()
                }
        }
    }
    
    // Mouse-transparent cell so NSTableView receives mouse for drag/selection
    private final class MouseTransparentTableCellView: NSTableCellView {
        override func hitTest(_ point: NSPoint) -> NSView? { return nil }
    }
}
