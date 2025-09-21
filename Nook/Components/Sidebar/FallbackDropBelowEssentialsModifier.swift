import SwiftUI

struct FallbackDropBelowEssentialsModifier: ViewModifier {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    @State private var draggedItem: UUID? = nil

    func body(content: Content) -> some View {
        content
            .onDrop(
                of: [.text],
                delegate: SidebarSectionDropDelegateSimple(
                    itemsCount: { currentSpacePinnedCount() },
                    draggedItem: $draggedItem,
                    targetSection: currentSpacePinnedTarget(),
                    tabManager: browserManager.tabManager
                )
            )
            .onReceive(NotificationCenter.default.publisher(for: .tabDragDidEnd)) { _ in
                draggedItem = nil
            }
    }

    private func currentSpacePinnedTarget() -> SidebarTargetSection {
        if let sid = windowState.currentSpaceId {
            return .spacePinned(sid)
        }
        // Fallback: if no current space, treat as essentials (below won't be correct, but avoids crashes)
        return .essentials
    }

    private func currentSpacePinnedCount() -> Int {
        guard let sid = windowState.currentSpaceId else { return 0 }
        return browserManager.tabManager.spacePinnedTabs(for: sid).count
    }
}
