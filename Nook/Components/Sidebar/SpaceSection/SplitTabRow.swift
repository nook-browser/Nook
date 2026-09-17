import NookTabsCore
import SwiftUI
import NookDesign

/// The window's split pair shown as one sidebar row (from `BrowserWindowState.split`).
struct SplitTabRow: View {
    let left: Item
    let right: Item
    /// The drop zone the halves drag from.
    let zoneID: DropZoneID

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
    }
}

private struct SplitHalfTab: View {
    let item: Item
    let zoneID: DropZoneID

    @State private var isHovering: Bool = false
    @State private var isCloseHovering: Bool = false
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @ObservedObject private var dragSession = NookDragSessionManager.shared

    private var tabs: TabsController { browserManager.tabs }

    var body: some View {
        let title = tabs.title(for: item)
        let session = tabs.session(for: item.id)
        NookDragSourceView(
            item: NookDragItem(tabId: item.id, title: title, urlString: tabs.currentURL(for: item)?.absoluteString ?? ""),
            icon: session?.favicon,
            zoneID: zoneID,
            manager: dragSession
        ) {
            Button(action: { tabs.select(item.id, in: windowState) }) {
                HStack(spacing: NookDesign.Spacing.md) {
                    ItemFavicon(item: item, session: session)
                        .frame(width: NookDesign.Size.favicon, height: NookDesign.Size.favicon)
                        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
                    Text(title)
                        .font(NookDesign.Font.body)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: NookDesign.Spacing.xs)
                    if isHovering {
                        Button(action: { tabs.close(item.id) }) {
                            Image(systemName: "xmark")
                                .font(NookDesign.Font.secondary)
                                .foregroundColor(.primary)
                                .frame(width: NookDesign.Size.rowButton, height: NookDesign.Size.rowButton)
                                .background(isCloseHovering ? NookDesign.Surface.fillPressed : Color.clear)
                                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .onHoverTracking { state in
                            isCloseHovering = state
                        }
                    }
                }
                .padding(.horizontal, NookDesign.Spacing.rowPadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .onHoverTracking { hovering in
                withAnimation(NookDesign.Motion.quick) {
                    isHovering = hovering
                }
            }
            .contextMenu {
                TabContextMenu(itemID: item.id, context: .split)
                    .environmentObject(browserManager)
                    .environment(windowState)
            }
        }
        .opacity(dragSession.draggedItem?.tabId == item.id ? NookDesign.Surface.unloadedOpacity : 1)
        .background(backgroundColor)
        .overlay {
            if isActive {
                NookDesign.Radius.shape(NookDesign.Radius.md)
                    .strokeBorder(NookDesign.Surface.hairline, lineWidth: NookDesign.Size.hairlineWidth)
            }
        }
    }

    private var isActive: Bool {
        tabs.selectedItemID(in: windowState) == item.id
    }

    private var backgroundColor: Color {
        if isActive {
            return NookDesign.Surface.raised
        } else if isHovering {
            return NookDesign.Surface.fill
        } else {
            return Color.clear
        }
    }
}
