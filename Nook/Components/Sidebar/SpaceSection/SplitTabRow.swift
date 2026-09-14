import SwiftUI

struct SplitTabRow: View {
    let left: Tab
    let right: Tab
    let spaceId: UUID

    let onActivate: (Tab) -> Void
    let onClose: (Tab) -> Void

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @ObservedObject private var dragSession = NookDragSessionManager.shared

    var body: some View {
        HStack(spacing: 0) {
            SplitHalfTab(
                tab: left,
                side: .left,
                spaceId: spaceId,
                onActivate: { onActivate(left) },
                onClose: { onClose(left) }
            )
            Rectangle()
                .fill(NookDesign.Surface.hairline)
                .frame(width: NookDesign.Size.hairlineWidth)
                .padding(.vertical, NookDesign.Spacing.sm)
            SplitHalfTab(
                tab: right,
                side: .right,
                spaceId: spaceId,
                onActivate: { onActivate(right) },
                onClose: { onClose(right) }
            )
        }
        .frame(height: NookDesign.Size.row)
        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
    }
}

private struct SplitHalfTab: View {
    @ObservedObject var tab: Tab
    let side: SplitViewManager.Side
    let spaceId: UUID
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var isHovering: Bool = false
    @State private var isCloseHovering: Bool = false
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @ObservedObject private var dragSession = NookDragSessionManager.shared

    var body: some View {
        NookDragSourceView(
            item: NookDragItem(tabId: tab.id, title: tab.displayName, urlString: tab.url.absoluteString),
            tab: tab,
            zoneID: .spaceRegular(tab.spaceId ?? spaceId),
            index: tab.index,
            manager: dragSession
        ) {
            ZStack {
                Button(action: onActivate) {
                    HStack(spacing: NookDesign.Spacing.md) {
                        tab.favicon
                            .resizable()
                            .scaledToFit()
                            .frame(width: NookDesign.Size.favicon, height: NookDesign.Size.favicon)
                            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
                        Text(tab.displayName)
                            .font(NookDesign.Font.body)
                            .foregroundStyle(textTab)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: NookDesign.Spacing.xs)
                        if isHovering {
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(NookDesign.Font.secondary)
                                    .foregroundColor(textTab)
                                    .frame(width: NookDesign.Size.rowButton, height: NookDesign.Size.rowButton)
                                    .background(
                                        isCloseHovering
                                            ? NookDesign.Surface.fillPressed
                                            : Color.clear
                                    )
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
                    TabContextMenu(tab: tab, context: .split)
                }
            }
        }
        .opacity(dragSession.draggedItem?.tabId == tab.id ? 0 : 1.0)
        .background(backgroundColor)
        .overlay {
            if isActive {
                NookDesign.Radius.shape(NookDesign.Radius.md)
                    .strokeBorder(NookDesign.Surface.hairline, lineWidth: 1)
            }
        }
    }

    private var isActive: Bool {
        browserManager.currentTab(for: windowState)?.id == tab.id
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
    private var textTab: Color {
        .primary
    }

}
