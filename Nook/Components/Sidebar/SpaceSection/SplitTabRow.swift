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
        HStack(spacing: 1) {
            SplitHalfTab(
                tab: left,
                side: .left,
                onActivate: { onActivate(left) },
                onClose: { onClose(left) }
            )
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.6))
                .frame(width: 1, height: 24)
                .padding(.vertical, 4)
            SplitHalfTab(
                tab: right,
                side: .right,
                onActivate: { onActivate(right) },
                onClose: { onClose(right) }
            )
        }
        .frame(height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct SplitHalfTab: View {
    @ObservedObject var tab: Tab
    let side: SplitViewManager.Side
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var isHovering: Bool = false
    @State private var isCloseHovering: Bool = false
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.colorScheme) var colorScheme
    @ObservedObject private var dragSession = NookDragSessionManager.shared

    var body: some View {
        NookDragSourceView(
            item: NookDragItem(tabId: tab.id, title: tab.name, urlString: tab.url.absoluteString),
            tab: tab,
            zoneID: .spaceRegular(tab.spaceId ?? UUID()),
            index: tab.index,
            manager: dragSession
        ) {
            ZStack {
                Button(action: onActivate) {
                    HStack(spacing: 8) {
                        tab.favicon
                            .resizable()
                            .scaledToFit()
                            .frame(width: 18, height: 18)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        Text(tab.name)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(textTab)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        if isHovering {
                            Button(action: onClose) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(textTab)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        isCloseHovering
                                            ? (isActive
                                                ? AppColors
                                                    .controlBackgroundHoverLight
                                                : AppColors.controlBackgroundActive)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(PlainButtonStyle())
                            .onHover { state in
                                isCloseHovering = state
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHovering = hovering
                    }
                }
                .contextMenu {
                    Button("Close Tab", action: onClose)
                }
            }
        }
        .opacity(dragSession.draggedItem?.tabId == tab.id ? 0.25 : 1.0)
        .background(backgroundColor)
    }

    private var isActive: Bool {
        browserManager.currentTab(for: windowState)?.id == tab.id
    }

    private var backgroundColor: Color {
        if isActive {
            return colorScheme == .dark
                ? AppColors.spaceTabActiveLight : AppColors.spaceTabActiveDark
        } else if isHovering {
            return colorScheme == .dark
                ? AppColors.spaceTabHoverLight : AppColors.spaceTabHoverDark
        } else {
            return Color.clear
        }
    }
    private var textTab: Color {
        return colorScheme == .dark
            ? AppColors.spaceTabTextLight : AppColors.spaceTabTextDark
    }

}
