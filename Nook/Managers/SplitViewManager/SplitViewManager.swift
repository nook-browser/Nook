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

    init(browserManager: BrowserManager? = nil) {
        self.browserManager = browserManager
    }

    func setDividerFraction(_ value: CGFloat) {
        let clamped = min(max(value, minFraction), maxFraction)
        if abs(clamped - dividerFraction) > 0.0001 {
            dividerFraction = clamped
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
        guard let bm = browserManager else { return }

        let tm = bm.tabManager

        // Helper to duplicate pinned/space-pinned into a regular tab near an anchor
        func maybeDuplicateIfPinned(_ candidate: Tab, anchor: Tab?) -> Tab {
            if tm.isGlobalPinned(candidate) || tm.isSpacePinned(candidate) {
                // Insert after anchor so combined split row renders at anchor's position
                return tm.duplicateAsRegularForSplit(from: candidate, anchor: anchor, placeAfterAnchor: true)
            }
            return candidate
        }

        // If already split, replace the requested side (ensure pinned tabs are duplicated)
        if isSplit {
            // Determine the opposite side to use as an anchor for placement
            let oppositeId = (side == .left) ? rightTabId : leftTabId
            let opposite = tm.allTabs().first(where: { $0.id == oppositeId })
            let resolved = maybeDuplicateIfPinned(tab, anchor: opposite)

            switch side {
            case .left: leftTabId = resolved.id
            case .right: rightTabId = resolved.id
            }
            bm.compositorManager.loadTab(resolved)
            return
        }

        // Not split yet: use current tab as the opposite side
        guard let current = tm.currentTab else { return }
        // Avoid attempting to split the same tab against itself
        if current.id == tab.id { return }

        // Decide sides per request first
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

        // Duplicate pinned/space-pinned tabs into regular tabs near the regular anchor (if any)
        // Prefer the opposite side as an anchor so the row appears near the regular tab.
        let leftResolved: Tab = maybeDuplicateIfPinned(leftCandidate, anchor: rightCandidate)
        let rightResolved: Tab = maybeDuplicateIfPinned(rightCandidate, anchor: leftResolved)

        leftTabId = leftResolved.id
        rightTabId = rightResolved.id
        isSplit = true
        bm.compositorManager.loadTab(leftResolved)
        bm.compositorManager.loadTab(rightResolved)

        if animate {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                setDividerFraction(0.5)
            }
        }
    }

    func exitSplit(keep side: Side = .left) {
        guard isSplit, let bm = browserManager else { return }
        // Focus the kept tab
        if let keepTab = tab(for: side) {
            bm.tabManager.setActiveTab(keepTab)
        }
        // Reset
        leftTabId = nil
        rightTabId = nil
        isSplit = false
        isPreviewActive = false
        previewSide = nil
    }

    func closePane(_ side: Side) {
        guard isSplit, let bm = browserManager else { return }
        switch side {
        case .left:
            if let right = tab(for: .right) {
                bm.tabManager.setActiveTab(right)
            }
        case .right:
            if let left = tab(for: .left) {
                bm.tabManager.setActiveTab(left)
            }
        }
        exitSplit(keep: side == .left ? .right : .left)
    }

    func swapSides() {
        guard isSplit else { return }
        let l = leftTabId
        leftTabId = rightTabId
        rightTabId = l
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
        previewSide = side
        if !isSplit, let bm = browserManager, let current = bm.tabManager.currentTab {
            // Show current tab in its eventual half to preview the split
            if side == .right {
                leftTabId = current.id
            } else {
                rightTabId = current.id
            }
            isSplit = true
        }
        isPreviewActive = true
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            setDividerFraction(0.5)
        }
    }

    func endPreview(cancel: Bool) {
        isPreviewActive = false
        previewSide = nil
        if cancel {
            // Revert split if it was only created for preview
            if leftTabId == nil || rightTabId == nil {
                isSplit = false
            }
        }
    }
}
