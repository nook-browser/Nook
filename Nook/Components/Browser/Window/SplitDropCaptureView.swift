import AppKit
import WebKit

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
        registerForDraggedTypes([.nookTabItem, .string])
        // Transparent to normal mouse events; only DnD uses these callbacks
        isHidden = false
    }

    // Only intercept events during an active drag; otherwise pass through
    override func hitTest(_ point: NSPoint) -> NSView? { 
        // Return nil to pass through all mouse events when not dragging
        // This allows right-clicks to reach the webview below for context menus
        return isDragActive ? self : nil 
    }
    
    // Override acceptsFirstResponder to prevent this view from intercepting events
    override var acceptsFirstResponder: Bool { false }

    // MARK: - Dragging
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragActive = true
        updatePreview(sender)
        updateDragLocation(sender)
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        isDragActive = true
        updateDragLocation(sender)
        updatePreview(sender)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        isDragActive = false
        if let windowId {
            splitManager?.updateDragLocation(nil, for: windowId)
            splitManager?.endPreview(cancel: true, for: windowId)
        }
        // Signal UI to clear any drag-hiding state even on invalid drops
        NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let bm = browserManager, let sm = splitManager, let windowId else { return false }
        let pb = sender.draggingPasteboard
        // Try to read NookDragItem first, fall back to plain string UUID
        let tabId: UUID? = {
            if let item = NookDragItem.fromPasteboard(pb) { return item.tabId }
            if let idString = pb.string(forType: .string) { return UUID(uuidString: idString) }
            return nil
        }()
        guard let id = tabId else {
            // Invalid payload; clear any lingering drag UI state
            sm.updateDragLocation(nil, for: windowId)
            sm.endPreview(cancel: false, for: windowId)
            NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
            return false
        }
        let all = bm.tabManager.allTabs()
        guard let tab = all.first(where: { $0.id == id }) else {
            sm.updateDragLocation(nil, for: windowId)
            sm.endPreview(cancel: false, for: windowId)
            return false
        }
        
        let side = sideForDragInCard(sender)
        guard let dropSide = side else {
            sm.updateDragLocation(nil, for: windowId)
            sm.endPreview(cancel: false, for: windowId)
            return false
        }
        
        sm.updateDragLocation(nil, for: windowId)
        sm.endPreview(cancel: false, for: windowId)
        
        // Redundant replace guard
        if sm.isSplit(for: windowId) {
            let leftId = sm.leftTabId(for: windowId)
            let rightId = sm.rightTabId(for: windowId)
            if (dropSide == .left && leftId == tab.id) || (dropSide == .right && rightId == tab.id) {
                return true
            }
        }
        if let windowState = bm.windowRegistry?.windows[windowId] {
            sm.enterSplit(with: tab, placeOn: dropSide, in: windowState)
        }
        // Cancel any in-progress sidebar/tab drag to prevent unintended reorder/removal
        DispatchQueue.main.async {
            NookDragSessionManager.shared.cancelDrag()
        }
        isDragActive = false
        return true
    }

    // MARK: - Helpers
    private func updatePreview(_ sender: NSDraggingInfo) {
        let side = sideForDragInCard(sender)
        guard let windowId, let sm = splitManager else { return }
        
        let currentState = sm.getSplitState(for: windowId)
        if currentState.isPreviewActive {
            sm.updatePreviewSide(side, for: windowId)
        } else {
            sm.beginPreview(side: side, for: windowId)
        }
    }
    
    private func updateDragLocation(_ sender: NSDraggingInfo) {
        let loc = convert(sender.draggingLocation, from: nil)
        if let windowId {
            splitManager?.updateDragLocation(loc, for: windowId)
        }
    }

    private func sideForDrag(_ sender: NSDraggingInfo) -> SplitViewManager.Side {
        let loc = convert(sender.draggingLocation, from: nil)
        let w = max(bounds.width, 1)
        return loc.x < (w / 2) ? .left : .right
    }
    
    /// Check if drag location is within card bounds and return which side
    /// Card dimensions: 237x394, positioned with 20pt padding from edges
    private func sideForDragInCard(_ sender: NSDraggingInfo) -> SplitViewManager.Side? {
        let loc = convert(sender.draggingLocation, from: nil)
        let cardWidth: CGFloat = 237
        let cardHeight: CGFloat = 394
        let cardPadding: CGFloat = 20
        
        // Calculate card positions (centered vertically)
        let viewHeight = bounds.height
        let cardTop = (viewHeight - cardHeight) / 2
        let cardBottom = cardTop + cardHeight
        
        // Left card bounds
        let leftCardLeft = cardPadding
        let leftCardRight = leftCardLeft + cardWidth
        
        // Right card bounds
        let rightCardRight = bounds.width - cardPadding
        let rightCardLeft = rightCardRight - cardWidth
        
        // Check if location is within left card
        if loc.x >= leftCardLeft && loc.x <= leftCardRight &&
           loc.y >= cardTop && loc.y <= cardBottom {
            return .left
        }
        
        // Check if location is within right card
        if loc.x >= rightCardLeft && loc.x <= rightCardRight &&
           loc.y >= cardTop && loc.y <= cardBottom {
            return .right
        }
        
        return nil // Not within any card
    }
}
