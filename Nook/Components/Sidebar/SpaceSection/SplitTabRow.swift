// Licensed under GPL-3.0. See LICENSE.
import SwiftUI
import NookDesign
import NookTabsCore
import NookUI
import NookWeb

/// The window's split pair shown as one sidebar row (from `BrowserWindowState.split`).
/// The halves' visuals are `SplitHalfLabel` in NookUI; this file is the drag source around them.
struct SplitTabRow: View {
    let left: Item
    let right: Item
    /// The drop zone the halves drag from.
    let zoneID: DropZoneID

    @Environment(BrowserWindowState.self) private var windowState

    /// The whole row is the selection while the window shows the pair.
    private var isActive: Bool {
        windowState.selectedItemID == left.id || windowState.selectedItemID == right.id
    }

    var body: some View {
        HStack(spacing: 0) {
            SplitHalfTab(item: left, zoneID: zoneID)
            Rectangle()
                .fill(NookDesign.Surface.hairline)
                .frame(width: NookDesign.Size.hairlineWidth)
                .padding(.vertical, NookDesign.Spacing.sm)
            SplitHalfTab(item: right, zoneID: zoneID)
        }
        .frame(height: NookDesign.Size.row)
        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .nookRowSelection(isActive)
        .nookElevation(isActive ? .raised : .flat)
    }
}

private struct SplitHalfTab: View {
    let item: Item
    let zoneID: DropZoneID

    @Environment(TabsController.self) private var tabs
    @ObservedObject private var dragSession = NookDragSessionManager.shared

    var body: some View {
        let session = tabs.session(for: item.id)
        NookDragSourceView(
            item: NookDragItem(tabId: item.id, title: tabs.title(for: item), urlString: tabs.currentURL(for: item)?.absoluteString ?? ""),
            icon: session?.favicon,
            zoneID: zoneID,
            manager: dragSession
        ) {
            SplitHalfLabel(item: item)
        }
        .opacity(dragSession.draggedItem?.tabId == item.id
                 ? (dragSession.isSettlingDrop ? 0 : NookDesign.Surface.unloadedOpacity)
                 : 1)
    }
}
