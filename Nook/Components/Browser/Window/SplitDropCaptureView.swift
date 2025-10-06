import AppKit

final class SplitDropCaptureView: NSView {
    weak var browserManager: BrowserManager?
    weak var splitManager: SplitViewManager?
    var windowId: UUID?
    private var isDragActive: Bool = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        // Accept plain text drags (UUID string for a Tab)
        registerForDraggedTypes([.string])
        // Transparent to normal mouse events; only DnD uses these callbacks
        isHidden = false
    }

    // Only intercept events during an active drag; otherwise pass through
    override func hitTest(_ point: NSPoint) -> NSView? { isDragActive ? self : nil }

    // MARK: - Dragging
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragActive = true
        updatePreview(sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragActive = true
        updatePreview(sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragActive = false
        if let windowId { splitManager?.endPreview(cancel: true, for: windowId) }
        // Signal UI to clear any drag-hiding state even on invalid drops
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let bm = browserManager, let sm = splitManager, let windowId else { return false }
        sm.endPreview(cancel: false, for: windowId)
        let pb = sender.draggingPasteboard
        guard let idString = pb.string(forType: .string), let id = UUID(uuidString: idString) else {
            // Invalid payload; clear any lingering drag UI state
            NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
            return false
        }
        let all = bm.tabManager.allTabs()
        guard let tab = all.first(where: { $0.id == id }) else { return false }
        let side = sideForDrag(sender)
        // Redundant replace guard
        if sm.isSplit(for: windowId) {
            let leftId = sm.leftTabId(for: windowId)
            let rightId = sm.rightTabId(for: windowId)
            if (side == .left && leftId == tab.id) || (side == .right && rightId == tab.id) {
                return true
            }
        }
        if let windowState = bm.windowStates[windowId] {
            sm.enterSplit(with: tab, placeOn: side, in: windowState)
        }
        // Cancel any in-progress sidebar/tab drag to prevent unintended reorder/removal
        DispatchQueue.main.async {
            TabDragManager.shared.cancelDrag()
        }
        isDragActive = false
        return true
    }

    // MARK: - Helpers
    private func updatePreview(_ sender: NSDraggingInfo) {
        let side = sideForDrag(sender)
        if let windowId { splitManager?.beginPreview(side: side, for: windowId) }
    }

    private func sideForDrag(_ sender: NSDraggingInfo) -> SplitViewManager.Side {
        let loc = convert(sender.draggingLocation, from: nil)
        let w = max(bounds.width, 1)
        return loc.x < (w / 2) ? .left : .right
    }
}
