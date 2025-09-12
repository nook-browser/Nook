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

        // If already split, replace the requested side
        if isSplit {
            switch side {
            case .left: leftTabId = tab.id
            case .right: rightTabId = tab.id
            }
            bm.compositorManager.loadTab(tab)
            return
        }

        // Not split yet: use current tab as the opposite side
        guard let current = bm.tabManager.currentTab else { return }
        // Avoid attempting to split the same tab against itself
        if current.id == tab.id { return }
        switch side {
        case .left:
            leftTabId = tab.id
            rightTabId = current.id
        case .right:
            leftTabId = current.id
            rightTabId = tab.id
        }

        isSplit = true
        bm.compositorManager.loadTab(current)
        bm.compositorManager.loadTab(tab)

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
