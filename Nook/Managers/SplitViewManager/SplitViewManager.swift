// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import SwiftUI
import NookTabsCore
import NookWeb

/// Split view per window. The pair lives on `BrowserWindowState.split` (item ids, saved with the
/// window); the active side is whichever pane the window selects. Only the drag preview state is
/// kept here.
@MainActor
final class SplitViewManager: ObservableObject {
    enum Side { case left, right }

    /// A read-only snapshot of one window's split and preview state.
    struct WindowSplitState {
        var isSplit: Bool = false
        var leftTabId: UUID? = nil
        var rightTabId: UUID? = nil
        var dividerFraction: CGFloat = 0.5
        var isPreviewActive: Bool = false
        var previewSide: Side? = nil
        var activeSide: Side? = nil
        var dragLocation: CGPoint? = nil
    }

    private struct Preview {
        var isActive = false
        var side: Side?
        var dragLocation: CGPoint?
    }

    weak var browserManager: BrowserManager?

    @Published private var previews: [UUID: Preview] = [:]

    init(browserManager: BrowserManager? = nil) {
        self.browserManager = browserManager
    }

    private func window(_ windowId: UUID) -> BrowserWindowState? {
        browserManager?.windowRegistry?.windows[windowId]
    }

    // MARK: - State

    func getSplitState(for windowId: UUID) -> WindowSplitState {
        let preview = previews[windowId] ?? Preview()
        var state = WindowSplitState(
            isPreviewActive: preview.isActive, previewSide: preview.side, dragLocation: preview.dragLocation)
        guard let window = window(windowId), let split = window.split else { return state }
        state.isSplit = true
        state.leftTabId = split.leftItemID
        state.rightTabId = split.rightItemID
        state.dividerFraction = CGFloat(split.fraction)
        state.activeSide = side(for: window.selectedItemID, in: split)
        return state
    }

    func isSplit(for windowId: UUID) -> Bool { window(windowId)?.split != nil }
    func leftTabId(for windowId: UUID) -> UUID? { window(windowId)?.split?.leftItemID }
    func rightTabId(for windowId: UUID) -> UUID? { window(windowId)?.split?.rightItemID }
    func dividerFraction(for windowId: UUID) -> CGFloat { CGFloat(window(windowId)?.split?.fraction ?? 0.5) }
    func activeSide(for windowId: UUID) -> Side? { getSplitState(for: windowId).activeSide }

    func side(for itemID: UUID, in windowId: UUID) -> Side? {
        window(windowId)?.split.flatMap { side(for: itemID, in: $0) }
    }

    private func side(for itemID: UUID?, in split: SplitRecord) -> Side? {
        switch itemID {
        case split.leftItemID: return .left
        case split.rightItemID: return .right
        default: return nil
        }
    }

    // MARK: - Entering and Leaving

    /// Puts `itemID` on `side`. Outside a split it pairs with the window's selection, which stays
    /// selected; inside a split it replaces that pane and becomes the selection.
    func enterSplit(with itemID: UUID, placeOn side: Side = .right, in window: BrowserWindowState) {
        guard let tabs = browserManager?.tabs, tabs.item(itemID) != nil else { return }
        if var split = window.split {
            switch side {
            case .left: split.leftItemID = itemID
            case .right: split.rightItemID = itemID
            }
            guard split.leftItemID != split.rightItemID else { return }
            window.split = split
            loadPanes(of: window)
            tabs.select(itemID, in: window)
            return
        }
        guard let current = window.selectedItemID, current != itemID else { return }
        let (left, right) = side == .left ? (itemID, current) : (current, itemID)
        window.split = SplitRecord(leftItemID: left, rightItemID: right, fraction: 0.5)
        loadPanes(of: window)
        // Selecting again saves the window record with its new split.
        tabs.select(current, in: window)
    }

    private func loadPanes(of window: BrowserWindowState) {
        guard let bm = browserManager, let split = window.split else { return }
        for id in [split.leftItemID, split.rightItemID] {
            if let session = bm.tabs.ensureSession(for: id) { bm.compositorManager.load(session) }
        }
    }

    /// Leaves the split. When the window selects a pane, the kept side becomes the selection.
    func exitSplit(keep side: Side, for windowId: UUID) {
        guard let window = window(windowId), let split = window.split else { return }
        let showsPane = self.side(for: window.selectedItemID, in: split) != nil
        window.split = nil
        let kept = side == .left ? split.leftItemID : split.rightItemID
        if showsPane, let tabs = browserManager?.tabs, tabs.item(kept) != nil {
            tabs.select(kept, in: window)
        } else {
            // No selection change to save the record, so save it here.
            browserManager?.tabs.mirror(window)
            window.refreshCompositor()
        }
    }

    /// Ends the split and keeps both tabs open. The active pane stays selected.
    func separate(in window: BrowserWindowState) {
        exitSplit(keep: activeSide(for: window.id) ?? .left, for: window.id)
    }

    func cleanupWindow(_ windowId: UUID) {
        previews.removeValue(forKey: windowId)
    }

    // MARK: - Preview During Drag-Over

    func beginPreview(side: Side?, for windowId: UUID) {
        previews[windowId, default: Preview()].isActive = true
        previews[windowId]?.side = side
        window(windowId)?.refreshCompositor()
    }

    func updatePreviewSide(_ side: Side?, for windowId: UUID) {
        guard previews[windowId]?.isActive == true else { return }
        previews[windowId]?.side = side
    }

    func updateDragLocation(_ location: CGPoint?, for windowId: UUID) {
        previews[windowId, default: Preview()].dragLocation = location
    }

    func dragLocation(for windowId: UUID) -> CGPoint? {
        previews[windowId]?.dragLocation
    }

    func endPreview(cancel: Bool, for windowId: UUID) {
        previews[windowId] = Preview()
        window(windowId)?.refreshCompositor()
    }
}
