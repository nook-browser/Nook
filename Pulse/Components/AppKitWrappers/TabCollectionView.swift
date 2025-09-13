import SwiftUI
import AppKit
import Combine

/// NSViewRepresentable wrapper for NSCollectionView with native AppKit drag & drop
struct TabCollectionView<DataSource: TabListDataSource & ObservableObject>: NSViewRepresentable {
    // MARK: - Layout constants (use shared helper)
    private let minButtonWidth: CGFloat = EssentialsGridLayout.minButtonWidth
    private let itemSpacing: CGFloat = EssentialsGridLayout.itemSpacing
    private let lineSpacing: CGFloat = EssentialsGridLayout.lineSpacing
    private let maxColumns: Int = EssentialsGridLayout.maxColumns

    @ObservedObject var dataSource: DataSource
    var availableWidth: CGFloat
    // Width changes are driven externally by GeometryReader

    @EnvironmentObject var browserManager: BrowserManager

    // MARK: - NSViewRepresentable
    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let collectionView = NSCollectionView()
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        collectionView.backgroundColors = [.clear]
        collectionView.isSelectable = true
        collectionView.allowsEmptySelection = true
        collectionView.delegate = context.coordinator
        collectionView.dataSource = context.coordinator
        // Debug background to visualize bounds
        collectionView.wantsLayer = true
        collectionView.layer?.backgroundColor = NSColor.systemBlue.withAlphaComponent(0.08).cgColor

        // Layout
        let layout = NSCollectionViewFlowLayout()
        layout.scrollDirection = .vertical
        layout.minimumInteritemSpacing = itemSpacing
        layout.minimumLineSpacing = lineSpacing
        layout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        let columns = columnCount(for: availableWidth, itemCount: dataSource.tabs.count)
        layout.itemSize = itemSize(for: availableWidth, columns: columns)
        collectionView.collectionViewLayout = layout

        // Register item
        collectionView.register(TabCollectionViewItem.self,
                                forItemWithIdentifier: TabCollectionViewItem.reuseIdentifier)

        // Drag & Drop
        collectionView.registerForDraggedTypes([PasteboardType.tab])
        collectionView.setDraggingSourceOperationMask(.move, forLocal: true)
        collectionView.setDraggingSourceOperationMask(.move, forLocal: false)

        // Embed in scroll view
        scrollView.documentView = collectionView
        // Debug background to visualize container
        scrollView.wantsLayer = true
        scrollView.layer?.backgroundColor = NSColor.systemRed.withAlphaComponent(0.08).cgColor
        NSLayoutConstraint.activate([
            collectionView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            collectionView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: scrollView.contentView.bottomAnchor),
            collectionView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        // Coordinator hooks
        context.coordinator.parent = self
        context.coordinator.collectionView = collectionView
        // External width changes will cause SwiftUI to call updateNSView
        
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let collectionView = scrollView.documentView as? NSCollectionView,
              let layout = collectionView.collectionViewLayout as? NSCollectionViewFlowLayout else { return }

        // Update coordinator and layout
        context.coordinator.parent = self
        context.coordinator.collectionView = collectionView
        context.coordinator.resubscribeIfNeeded(to: dataSource)

        let itemCount = dataSource.tabs.count
        let columns = columnCount(for: availableWidth, itemCount: max(1, itemCount))
        let size = itemSize(for: availableWidth, columns: columns)
        if layout.itemSize != size || layout.minimumInteritemSpacing != itemSpacing || layout.minimumLineSpacing != lineSpacing {
            layout.itemSize = size
            layout.minimumInteritemSpacing = itemSpacing
            layout.minimumLineSpacing = lineSpacing
            layout.sectionInset = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.18
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                collectionView.reloadData()
            }
        } else {
            collectionView.reloadData()
        }
    }

    func makeCoordinator() -> CollectionCoordinator {
        CollectionCoordinator(self)
    }

    // MARK: - Layout helpers
    private func columnCount(for width: CGFloat, itemCount: Int) -> Int {
        EssentialsGridLayout.columnCount(for: width, itemCount: itemCount)
    }

    private func itemSize(for width: CGFloat, columns: Int) -> NSSize {
        let cols = max(1, min(columns, maxColumns))
        let totalSpacing = CGFloat(max(0, cols - 1)) * itemSpacing
        let available = max(0, width - totalSpacing)
        let w = max(minButtonWidth, floor(available / CGFloat(cols)))
        // Height aligned to Essentials tile minimum
        let h: CGFloat = EssentialsGridLayout.tileHeight
        return NSSize(width: w, height: h)
    }

    // MARK: - Coordinator
    class CollectionCoordinator: NSObject, NSCollectionViewDataSource, NSCollectionViewDelegate {
        var parent: TabCollectionView<DataSource>
        weak var collectionView: NSCollectionView?
        private var cancellable: AnyCancellable?
        // No internal KVO-based width observation

        init(_ parent: TabCollectionView<DataSource>) {
            self.parent = parent
            super.init()

            // Initial subscription
            self.resubscribeIfNeeded(to: parent.dataSource)
        }

        deinit { cancellable?.cancel() }

        // No width observer; SwiftUI passes width via `availableWidth` and triggers updateNSView

        // MARK: - Data Source
        func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }

        func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int {
            parent.dataSource.tabs.count
        }

        func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
            let item = collectionView.makeItem(withIdentifier: TabCollectionViewItem.reuseIdentifier, for: indexPath)
            guard let tabItem = item as? TabCollectionViewItem else { return item }

            if indexPath.item < parent.dataSource.tabs.count {
                let tab = parent.dataSource.tabs[indexPath.item]
                tabItem.configure(with: tab, dataSource: parent.dataSource, browserManager: parent.browserManager)
            }
            return tabItem
        }

        // Prefer pasteboardWriterForItemAt to ensure drag begins even if subviews handle mouse
        func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
            guard indexPath.item < parent.dataSource.tabs.count else { return nil }
            let tab = parent.dataSource.tabs[indexPath.item]
            let item = NSPasteboardItem()
            item.setString(tab.id.uuidString, forType: PasteboardType.tab)
            item.setString(tab.id.uuidString, forType: .string)
#if DEBUG
            print("[DnD] Collection pasteboardWriterForItemAt item=\(indexPath.item)")
#endif
            return item
        }

        private var hiddenDuringDrag: Set<IndexPath> = []

        func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) {
#if DEBUG
            print("[DnD] Collection draggingSession willBeginAt items=\(indexPaths.map{ $0.item })")
#endif
            hiddenDuringDrag = indexPaths
            for ip in indexPaths {
                if let item = collectionView.item(at: ip) {
                    item.view.isHidden = true
                }
            }
        }

        func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation: NSDragOperation) {
#if DEBUG
            print("[DnD] Collection draggingSession ended op=\(dragOperation.rawValue)")
#endif
            for ip in hiddenDuringDrag {
                if let item = collectionView.item(at: ip) {
                    item.view.isHidden = false
                }
            }
            hiddenDuringDrag.removeAll()
        }

        // MARK: - Drag & Drop
        func collectionView(_ collectionView: NSCollectionView, canDragItemsAt indexPaths: Set<IndexPath>, with event: NSEvent) -> Bool { true }

        // Prefer pasteboardWriterForItemAt for initiating drags

        func collectionView(_ collectionView: NSCollectionView, validateDrop draggingInfo: NSDraggingInfo, proposedIndexPath: AutoreleasingUnsafeMutablePointer<IndexPath>, dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
            // Allow cross-container when pasteboard has tab id
            let pasteboardTypes = draggingInfo.draggingPasteboard.types ?? []
            let hasTab = pasteboardTypes.contains(PasteboardType.tab)
#if DEBUG
            print("[DnD] Collection validateDrop - pasteboard types: \(pasteboardTypes), hasTab: \(hasTab)")
#endif
            guard hasTab else { 
#if DEBUG
                print("[DnD] Collection validateDrop - NO TAB TYPE FOUND, returning []")
#endif
                return [] 
            }
            dropOperation.pointee = .before
            let maxIndex = max(0, parent.dataSource.tabs.count)
            if proposedIndexPath.pointee.item > maxIndex {
                proposedIndexPath.pointee = IndexPath(item: maxIndex, section: 0)
            }
#if DEBUG
            print("[DnD] Collection validateDrop -> op=move index=\(proposedIndexPath.pointee.item) count=\(parent.dataSource.tabs.count)")
#endif
            return .move
        }

        func collectionView(_ collectionView: NSCollectionView, acceptDrop draggingInfo: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
#if DEBUG
            print("[DnD] Collection acceptDrop called at index=\(indexPath.item)")
#endif
            guard let items = draggingInfo.draggingPasteboard.pasteboardItems,
                  let first = items.first,
                  let idString = first.string(forType: PasteboardType.tab),
                  let id = UUID(uuidString: idString) else { 
#if DEBUG
                print("[DnD] Collection acceptDrop - failed to extract tab ID")
#endif
                return false 
            }

            if let sourceIndex = parent.dataSource.tabs.firstIndex(where: { $0.id == id }) {
                // Local reorder
                var targetIndex = indexPath.item
                if sourceIndex < targetIndex { targetIndex -= 1 }
                let maxIndex = max(0, parent.dataSource.tabs.count - 1)
                targetIndex = max(0, min(targetIndex, maxIndex))
                let fromPath = IndexPath(item: sourceIndex, section: 0)
                let toPath = IndexPath(item: targetIndex, section: 0)
#if DEBUG
                print("[DnD] Collection acceptDrop local from=\(sourceIndex) to=\(targetIndex)")
#endif
                collectionView.performBatchUpdates({ [weak self] in
                    guard let self = self else { return }
                    self.parent.dataSource.moveTab(from: sourceIndex, to: targetIndex)
                    collectionView.moveItem(at: fromPath, to: toPath)
                }, completionHandler: nil)
                return true
            }

            // Cross-container: insert into essentials at target index
            let bm = parent.browserManager
            let tm = bm.tabManager
            // Resolve tab by id
            let spaces = tm.spaces
            let allSpacePinned = spaces.flatMap { tm.spacePinnedTabs(for: $0.id) }
            let allRegular = spaces.flatMap { tm.tabs(in: $0) }
            let allEssentials = tm.essentialTabs
            guard let tab = (allEssentials + allSpacePinned + allRegular).first(where: { $0.id == id }) else { return false }

#if DEBUG
            print("[DnD] Collection acceptDrop cross to=\(indexPath.item) from external")
#endif
            tm.addToEssentials(tab)
            tm.reorderEssential(tab, to: indexPath.item)
            DispatchQueue.main.async { collectionView.reloadData() }
            return true
        }
        private var subscribedDataSourceId: ObjectIdentifier?

        func resubscribeIfNeeded(to dataSource: DataSource) {
            let newId = ObjectIdentifier(dataSource)
            if subscribedDataSourceId != newId {
                subscribedDataSourceId = newId
                cancellable?.cancel()
                // Subscribe only to track identity; rely on SwiftUI updateNSView for reloads
                cancellable = dataSource.objectWillChange
                    .receive(on: DispatchQueue.main)
                    .sink { _ in }
            }
        }

        // MARK: - Selection
        func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
            guard let idx = indexPaths.first?.item, idx < parent.dataSource.tabs.count else { return }
            parent.dataSource.selectTab(at: idx)
        }
    }
}
