import SwiftUI

struct FallbackDropBelowEssentialsModifier: ViewModifier {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @ObservedObject private var dragSession = NookDragSessionManager.shared

    func body(content: Content) -> some View {
        content
            .onChange(of: dragSession.pendingDrop) { _, drop in
                handleFallbackDrop(drop)
            }
    }

    private func handleFallbackDrop(_ drop: PendingDrop?) {
        guard let drop = drop else { return }
        let target = currentSpacePinnedZone()
        guard drop.targetZone == target else { return }
        let allTabs = browserManager.tabManager.allTabs()
        guard let tab = allTabs.first(where: { $0.id == drop.item.tabId }) else { return }
        let op = dragSession.makeDragOperation(from: drop, tab: tab)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            browserManager.tabManager.handleDragOperation(op)
        }
        dragSession.pendingDrop = nil
    }

    private func currentSpacePinnedZone() -> DropZoneID {
        if let sid = windowState.currentSpaceId {
            return .spacePinned(sid)
        }
        return .essentials
    }
}
