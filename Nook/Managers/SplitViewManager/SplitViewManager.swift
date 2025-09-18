import SwiftUI

@MainActor
final class SplitViewManager: ObservableObject {
    enum Side { case left, right }

    // MARK: - State
    @Published var isSplit: Bool = false
    @Published var leftTabId: UUID? = nil
    @Published var rightTabId: UUID? = nil
    @Published private(set) var dividerFraction: CGFloat = 0.5 // 0.0 = all left, 1.0 = all right

    // Preview state during drag-over of the web content
    @Published var isPreviewActive: Bool = false
    @Published var previewSide: Side? = nil

    // Limits for divider movement
    let minFraction: CGFloat = 0.2
    let maxFraction: CGFloat = 0.8

    weak var browserManager: BrowserManager?
    
    // Window-specific split state
    private var windowSplitStates: [UUID: WindowSplitState] = [:]
    
    struct WindowSplitState {
        var isSplit: Bool = false
        var leftTabId: UUID? = nil
        var rightTabId: UUID? = nil
        var dividerFraction: CGFloat = 0.5
        var isPreviewActive: Bool = false
        var previewSide: Side? = nil
    }

    init(browserManager: BrowserManager? = nil) {
        self.browserManager = browserManager
    }
    
    // MARK: - Window-Aware Split Management
    
    /// Get split state for a specific window
    func getSplitState(for windowId: UUID) -> WindowSplitState {
        return windowSplitStates[windowId] ?? WindowSplitState()
    }
    
    /// Set split state for a specific window
    func setSplitState(_ state: WindowSplitState, for windowId: UUID) {
        windowSplitStates[windowId] = state
        syncPublishedStateIfNeeded(for: windowId)
    }
    
    /// Check if split is active for a specific window
    func isSplit(for windowId: UUID) -> Bool {
        return getSplitState(for: windowId).isSplit
    }
    
    /// Get left tab ID for a specific window
    func leftTabId(for windowId: UUID) -> UUID? {
        return getSplitState(for: windowId).leftTabId
    }
    
    /// Get right tab ID for a specific window
    func rightTabId(for windowId: UUID) -> UUID? {
        return getSplitState(for: windowId).rightTabId
    }
    
    /// Get divider fraction for a specific window
    func dividerFraction(for windowId: UUID) -> CGFloat {
        return getSplitState(for: windowId).dividerFraction
    }
    
    /// Set divider fraction for a specific window
    func setDividerFraction(_ value: CGFloat, for windowId: UUID) {
        let clamped = min(max(value, minFraction), maxFraction)
        var state = getSplitState(for: windowId)
        if abs(clamped - state.dividerFraction) > 0.0001 {
            state.dividerFraction = clamped
            setSplitState(state, for: windowId)
        }
    }

    /// Keep legacy published properties aligned with the active window's state
    private func syncPublishedStateIfNeeded(for windowId: UUID) {
        guard let bm = browserManager, bm.activeWindowState?.id == windowId else { return }
        updatePublishedState(from: getSplitState(for: windowId))
    }

    private func updatePublishedState(from state: WindowSplitState) {
        isSplit = state.isSplit
        leftTabId = state.leftTabId
        rightTabId = state.rightTabId
        dividerFraction = state.dividerFraction
        isPreviewActive = state.isPreviewActive
        previewSide = state.previewSide
    }

    func refreshPublishedState(for windowId: UUID) {
        updatePublishedState(from: getSplitState(for: windowId))
    }
    
    /// Enter split mode for a specific window
    func enterSplit(leftTabId: UUID, rightTabId: UUID, for windowId: UUID) {
        var state = getSplitState(for: windowId)
        state.isSplit = true
        state.leftTabId = leftTabId
        state.rightTabId = rightTabId
        state.dividerFraction = 0.5
        setSplitState(state, for: windowId)
        
        // Note: No need to update tab display ownership since windows are independent
        
        if let windowState = browserManager?.windowStates[windowId] {
            browserManager?.refreshCompositor(for: windowState)
        }
        
        print("🪟 [SplitViewManager] Entered split mode for window \(windowId)")
    }
    
    /// Exit split mode for a specific window
    func exitSplit(keep: Side, for windowId: UUID) {
        var state = getSplitState(for: windowId)
        guard state.isSplit else { return }
        
        let keepTabId = keep == .left ? state.leftTabId : state.rightTabId
        state.isSplit = false
        state.leftTabId = nil
        state.rightTabId = nil
        state.isPreviewActive = false
        state.previewSide = nil
        setSplitState(state, for: windowId)
        
        // Note: No need to update tab display ownership since windows are independent
        
        if let windowState = browserManager?.windowStates[windowId] {
            browserManager?.refreshCompositor(for: windowState)
        }
        
        print("🪟 [SplitViewManager] Exited split mode for window \(windowId), keeping \(keep)")
    }
    
    /// Close a pane in a specific window
    func closePane(_ side: Side, for windowId: UUID) {
        guard let bm = browserManager else { return }
        let state = getSplitState(for: windowId)
        guard state.isSplit else { return }
        guard let windowState = bm.windowStates[windowId] else { return }
        
        switch side {
        case .left:
            if let rightId = state.rightTabId, let rightTab = bm.tabManager.allTabs().first(where: { $0.id == rightId }) {
                bm.selectTab(rightTab, in: windowState)
            }
        case .right:
            if let leftId = state.leftTabId, let leftTab = bm.tabManager.allTabs().first(where: { $0.id == leftId }) {
                bm.selectTab(leftTab, in: windowState)
            }
        }
        exitSplit(keep: side == .left ? .right : .left, for: windowId)
    }

    func cleanupWindow(_ windowId: UUID) {
        windowSplitStates.removeValue(forKey: windowId)
        if let bm = browserManager, bm.activeWindowState?.id == windowId {
            updatePublishedState(from: WindowSplitState())
        }
        print("🪟 [SplitViewManager] Cleaned up split state for window \(windowId)")
    }

    func setDividerFraction(_ value: CGFloat) {
        if let windowId = browserManager?.activeWindowState?.id {
            setDividerFraction(value, for: windowId)
        } else {
            let clamped = min(max(value, minFraction), maxFraction)
            if abs(clamped - dividerFraction) > 0.0001 {
                dividerFraction = clamped
            }
        }
    }

    // MARK: - Helpers
    func resolveTab(_ id: UUID?) -> Tab? {
        guard let id, let bm = browserManager else { return nil }
        return bm.tabManager.allTabs().first(where: { $0.id == id })
    }

    func tab(for side: Side) -> Tab? {
        switch side {
        case .left: return resolveTab(leftTabId)
        case .right: return resolveTab(rightTabId)
        }
    }

    func side(for tabId: UUID) -> Side? {
        if leftTabId == tabId { return .left }
        if rightTabId == tabId { return .right }
        return nil
    }

    // MARK: - Entry points
    func enterSplit(with tab: Tab, placeOn side: Side = .right, animate: Bool = true) {
        guard let windowState = browserManager?.activeWindowState else { return }
        enterSplit(with: tab, placeOn: side, in: windowState, animate: animate)
    }

    func enterSplit(with tab: Tab, placeOn side: Side = .right, in windowState: BrowserWindowState, animate: Bool = true) {
        guard let bm = browserManager else { return }
        let tm = bm.tabManager
        let windowId = windowState.id
        var state = getSplitState(for: windowId)

        func maybeDuplicateIfPinned(_ candidate: Tab, anchor: Tab?) -> Tab {
            if tm.isGlobalPinned(candidate) || tm.isSpacePinned(candidate) {
                return tm.duplicateAsRegularForSplit(from: candidate, anchor: anchor, placeAfterAnchor: true)
            }
            return candidate
        }

        if state.isSplit {
            let oppositeId = (side == .left) ? state.rightTabId : state.leftTabId
            let opposite = oppositeId.flatMap { id in tm.allTabs().first(where: { $0.id == id }) }
            let resolved = maybeDuplicateIfPinned(tab, anchor: opposite)
            switch side {
            case .left: state.leftTabId = resolved.id
            case .right: state.rightTabId = resolved.id
            }
            setSplitState(state, for: windowId)
            bm.compositorManager.loadTab(resolved)
            if let ws = bm.windowStates[windowId] {
                bm.refreshCompositor(for: ws)
            }
            return
        }

        let current = bm.currentTab(for: windowState) ?? tm.currentTab
        guard let current, current.id != tab.id else { return }

        var leftCandidate: Tab
        var rightCandidate: Tab
        switch side {
        case .left:
            leftCandidate = tab
            rightCandidate = current
        case .right:
            leftCandidate = current
            rightCandidate = tab
        }

        let leftResolved = maybeDuplicateIfPinned(leftCandidate, anchor: rightCandidate)
        let rightResolved = maybeDuplicateIfPinned(rightCandidate, anchor: leftResolved)

        state.isSplit = true
        state.leftTabId = leftResolved.id
        state.rightTabId = rightResolved.id
        setSplitState(state, for: windowId)

        bm.compositorManager.loadTab(leftResolved)
        bm.compositorManager.loadTab(rightResolved)

        if animate {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                setDividerFraction(0.5, for: windowId)
            }
        } else {
            setDividerFraction(0.5, for: windowId)
        }

        bm.refreshCompositor(for: windowState)
    }

    func exitSplit(keep side: Side = .left) {
        guard let bm = browserManager, let activeWindow = bm.activeWindowState else { return }
        exitSplit(keep: side, for: activeWindow.id)
    }

    func closePane(_ side: Side) {
        guard let bm = browserManager, let activeWindow = bm.activeWindowState else { return }
        closePane(side, for: activeWindow.id)
    }

    func swapSides() {
        guard let bm = browserManager, let activeWindow = bm.activeWindowState else { return }
        swapSides(for: activeWindow.id)
    }
    
    /// Swap sides for a specific window
    func swapSides(for windowId: UUID) {
        var state = getSplitState(for: windowId)
        guard state.isSplit else { return }
        let l = state.leftTabId
        state.leftTabId = state.rightTabId
        state.rightTabId = l
        setSplitState(state, for: windowId)
        if let windowState = browserManager?.windowStates[windowId] {
            browserManager?.refreshCompositor(for: windowState)
        }
        
        print("🪟 [SplitViewManager] Swapped sides for window \(windowId)")
    }

    func exitSplitCompletely() {
        isSplit = false
        leftTabId = nil
        rightTabId = nil
        isPreviewActive = false
        previewSide = nil
    }

    // MARK: - Preview during drag-over
    func beginPreview(side: Side) {
        guard let bm = browserManager, let windowState = bm.activeWindowState else { return }
        beginPreview(side: side, for: windowState.id)
    }

    func endPreview(cancel: Bool) {
        guard let bm = browserManager, let windowState = bm.activeWindowState else { return }
        endPreview(cancel: cancel, for: windowState.id)
    }

    func beginPreview(side: Side, for windowId: UUID) {
        var state = getSplitState(for: windowId)
        state.previewSide = side
        if !state.isSplit, let bm = browserManager, let windowState = bm.windowStates[windowId], let current = bm.currentTab(for: windowState) {
            if side == .right {
                state.leftTabId = current.id
            } else {
                state.rightTabId = current.id
            }
            state.isSplit = true
        }
        state.isPreviewActive = true
        setSplitState(state, for: windowId)
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            setDividerFraction(0.5, for: windowId)
        }
        if let windowState = browserManager?.windowStates[windowId] {
            browserManager?.refreshCompositor(for: windowState)
        }
    }

    func endPreview(cancel: Bool, for windowId: UUID) {
        var state = getSplitState(for: windowId)
        state.isPreviewActive = false
        state.previewSide = nil
        if cancel {
            if state.leftTabId == nil || state.rightTabId == nil {
                state.isSplit = false
            }
        }
        setSplitState(state, for: windowId)
        if let windowState = browserManager?.windowStates[windowId] {
            browserManager?.refreshCompositor(for: windowState)
        }
    }
}
