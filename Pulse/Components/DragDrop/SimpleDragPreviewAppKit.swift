//
//  SimpleDragPreviewAppKit.swift
//  Pulse
//
//  AppKit-backed preview of the sidebar drag & drop
//  Essentials grid + Space Pinned + Regular with buttery animations.
//  This is a preview/sandbox file; not wired to real models yet.
//

import SwiftUI

import AppKit

struct SimpleDragPreviewAppKit: View {
    @State private var sidebarWidth: CGFloat = 260

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("🧪 AppKit Drag Preview")
                    .font(.headline)
                Spacer()
                Text("Width: \(Int(sidebarWidth))px")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Slider(value: $sidebarWidth, in: 180...360, step: 1)
                    .frame(width: 160)
            }
            .padding(.horizontal, 8)

            AppKitSidebarPreviewRepresentable(sidebarWidth: sidebarWidth)
                .frame(width: sidebarWidth, height: 700)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                )
        }
        .padding()
    }
}

// MARK: - NSViewRepresentable host
struct AppKitSidebarPreviewRepresentable: NSViewRepresentable {
    let sidebarWidth: CGFloat

    func makeNSView(context: Context) -> SidebarPreviewHostView {
        let v = SidebarPreviewHostView()
        v.configure()
        return v
    }

    func updateNSView(_ nsView: SidebarPreviewHostView, context: Context) {
        nsView.update(sidebarWidth: sidebarWidth)
    }
}

// MARK: - Host View holding three sections
final class SidebarPreviewHostView: NSView {
    // Data (sandbox)
    private var essentials: [String] = ["GitHub", "Gmail", "Calendar"]
    private var spacePinned: [String] = ["Stack Overflow", "Docs"]
    private var regular: [String] = ["Claude", "OpenAI", "Anthropic", "YouTube", "Netflix"]

    // Subviews
    private let container = NSStackView()
    private let essentialsLabel = NSTextField(labelWithString: "Essential Tabs")
    private let essentialsCollection = EssentialsCollectionView()
    private let spaceHeader = NSTextField(labelWithString: "Development Space")
    private let spacePinnedLabel = NSTextField(labelWithString: "Pinned in Space")
    private let spacePinnedTable = DnDTableView()
    private let regularLabel = NSTextField(labelWithString: "Regular Tabs")
    private let regularTable = DnDTableView()

    // Drag state
    private var isDragging = false
    private var dragSource: Section?
    private var dragItem: String?

    // Highlight layer (shared)
    private let highlightLayer = CAShapeLayer()

    enum Section { case essentials, spacePinned, regular }

    func configure() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        highlightLayer.fillColor = NSColor.systemGreen.cgColor
        highlightLayer.opacity = 1
        layer?.addSublayer(highlightLayer)

        // Container
        container.orientation = .vertical
        container.spacing = 8
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)
        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            container.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)
        ])

        // Essentials (grid)
        essentialsLabel.textColor = .secondaryLabelColor
        container.addArrangedSubview(essentialsLabel)
        essentialsCollection.configure()
        essentialsCollection.dragDelegate = self
        essentialsCollection.registerForDraggedTypes([.string])
        container.addArrangedSubview(essentialsCollection.enclosingScrollView ?? NSScrollView())

        container.addArrangedSubview(makeDivider())

        // Space header
        spaceHeader.font = .boldSystemFont(ofSize: 13)
        container.addArrangedSubview(spaceHeader)

        // Space pinned table
        let spHeaderStack = NSStackView(views: [spacePinnedLabel])
        spacePinnedLabel.textColor = .secondaryLabelColor
        container.addArrangedSubview(spHeaderStack)

        spacePinnedTable.configure()
        spacePinnedTable.dragDelegate = self
        spacePinnedTable.registerForDraggedTypes([.string])
        container.addArrangedSubview(spacePinnedTable.enclosingScrollView ?? NSScrollView())

        container.addArrangedSubview(makeDivider())

        // Regular table
        let regHeaderStack = NSStackView(views: [regularLabel])
        regularLabel.textColor = .secondaryLabelColor
        container.addArrangedSubview(regHeaderStack)

        regularTable.configure()
        regularTable.dragDelegate = self
        regularTable.registerForDraggedTypes([.string])
        container.addArrangedSubview(regularTable.enclosingScrollView ?? NSScrollView())

        reloadAll()
    }

    func update(sidebarWidth: CGFloat) {
        essentialsCollection.updateWidth(sidebarWidth)
        // tables auto-fit; nothing else needed here.
    }

    private func reloadAll() {
        essentialsCollection.items = essentials
        essentialsCollection.reloadData()
        spacePinnedTable.items = spacePinned
        spacePinnedTable.reloadData()
        regularTable.items = regular
        regularTable.reloadData()
    }

    private func makeDivider() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        return v
    }
}

// MARK: - Essentials Grid (NSCollectionView)
final class EssentialsCollectionView: NSCollectionView {
    var items: [String] = []
    weak var dragDelegate: SidebarPreviewHostView?
    private let flow = NSCollectionViewFlowLayout()
    private var sidebarWidth: CGFloat = 260

    func configure() {
        collectionViewLayout = flow
        flow.minimumInteritemSpacing = 8
        flow.minimumLineSpacing = 8
        flow.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        flow.itemSize = NSSize(width: 44, height: 44)
        isSelectable = false
        backgroundColors = [.clear]
        dataSource = self
        delegate = self
        // Register tile item class once
        register(TileItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("Tile"))

        let scroll = enclosingScrollView ?? NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        if superview == nil { scroll.documentView = self }

        // Drag source & destination
        setDraggingSourceOperationMask(.move, forLocal: true)
    }

    override func reloadData() {
        super.reloadData()
        invalidateGrid()
    }

    func updateWidth(_ w: CGFloat) {
        sidebarWidth = w
        invalidateGrid()
    }

    private func invalidateGrid() {
        let tile: CGFloat = 44
        let gap: CGFloat = 8
        let pad: CGFloat = 8
        let usable = max(sidebarWidth - pad * 2, tile)
        let cols = max(1, min(4, Int(floor((usable + gap) / (tile + gap)))))
        let totalWidth = CGFloat(cols) * tile + CGFloat(cols - 1) * gap
        let left = max(8, (sidebarWidth - totalWidth) / 2)
        flow.sectionInset = NSEdgeInsets(top: 8, left: left, bottom: 8, right: left)
        flow.invalidateLayout()
    }
}

extension EssentialsCollectionView: NSCollectionViewDataSource, NSCollectionViewDelegate {
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { items.count }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let id = NSUserInterfaceItemIdentifier("Tile")
        // Ensure registered in configure(); just make item here
        let item = collectionView.makeItem(withIdentifier: id, for: indexPath) as! TileItem
        item.configure(title: items[indexPath.item])
        return item
    }

    // Simple drag source
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? {
        let p = NSPasteboardItem()
        p.setString(items[indexPath.item], forType: .string)
        return p
    }
}

final class TileItem: NSCollectionViewItem {
    override func loadView() { self.view = NSView() }
    func configure(title: String) {
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.2).cgColor
        view.layer?.cornerRadius = 8
        let l = NSTextField(labelWithString: String(title.prefix(2)))
        l.font = .systemFont(ofSize: 11, weight: .semibold)
        l.textColor = .labelColor
        l.translatesAutoresizingMaskIntoConstraints = false
        view.subviews.forEach { $0.removeFromSuperview() }
        view.addSubview(l)
        NSLayoutConstraint.activate([
            l.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            l.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}

// MARK: - Tables (NSTableView) for Space Pinned and Regular
final class DnDTableView: NSTableView, NSTableViewDataSource, NSTableViewDelegate {
    var items: [String] = []
    weak var dragDelegate: SidebarPreviewHostView?

    func configure() {
        headerView = nil
        rowHeight = 30
        allowsMultipleSelection = false
        backgroundColor = .clear

        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c0"))
        addTableColumn(col)
        delegate = self
        dataSource = self

        setDraggingSourceOperationMask(.move, forLocal: true)
        enclosingScrollView?.drawsBackground = false
        enclosingScrollView?.hasVerticalScroller = true
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        var v = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView
        if v == nil {
            v = NSTableCellView()
            v?.identifier = id
            let l = NSTextField(labelWithString: "")
            l.translatesAutoresizingMaskIntoConstraints = false
            v?.textField = l
            v?.addSubview(l)
            NSLayoutConstraint.activate([
                l.leadingAnchor.constraint(equalTo: v!.leadingAnchor, constant: 8),
                l.centerYAnchor.constraint(equalTo: v!.centerYAnchor)
            ])
        }
        v?.textField?.stringValue = items[row]
        return v
    }

    // Drag source
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let p = NSPasteboardItem()
        p.setString(items[row], forType: .string)
        return p
    }
}

// MARK: - SidebarPreviewHostView drag/highlight plumbing (scaffold)
extension SidebarPreviewHostView {
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragging = true
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        return .move
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        // TODO: compute nearest boundary across whichever child view the pointer is over
        // and draw a green line there. For now, draw a top line as a placeholder.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let y = bounds.minY + 40
        let p = NSBezierPath(rect: NSRect(x: 8, y: y, width: bounds.width - 16, height: 3))
        highlightLayer.path = p.cgPath
        CATransaction.commit()
        return .move
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        // Keep highlight during cross-view moves — do not clear here.
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // TODO: decode string and reorder between lists/collection accordingly.
        // Play drop haptic
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        return true
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        // Clear highlight after drop
        isDragging = false
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        highlightLayer.path = nil
        CATransaction.commit()
    }
}


#Preview {
    SimpleDragPreviewAppKit()
        .frame(width: 420, height: 780)
}
