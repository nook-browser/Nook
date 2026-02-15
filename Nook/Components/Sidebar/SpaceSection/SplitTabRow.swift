import SwiftUI

struct SplitTabRow: View {
    let left: Tab
    let right: Tab
    let spaceId: UUID
    @Binding var draggedItem: UUID?

    let onActivate: (Tab) -> Void
    let onClose: (Tab) -> Void

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        HStack(spacing: 1) {
            SplitHalfTab(
                tab: left,
                side: .left,
                draggedItem: $draggedItem,
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
                draggedItem: $draggedItem,
                onActivate: { onActivate(right) },
                onClose: { onClose(right) }
            )
        }
        .frame(height: 34)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .onReceive(NotificationCenter.default.publisher(for: .tabDragDidEnd)) {
            _ in
            draggedItem = nil
        }
    }
}

private struct SplitHalfTab: View {
    @ObservedObject var tab: Tab
    let side: SplitViewManager.Side
    @Binding var draggedItem: UUID?
    let onActivate: () -> Void
    let onClose: () -> Void

    @State private var isHovering: Bool = false
    @State private var isCloseHovering: Bool = false
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
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
        .onTabDrag(tab.id, draggedItem: $draggedItem)
        .opacity(draggedItem == tab.id ? 0.25 : 1.0)
        .background(backgroundColor)
        .onDrop(of: [.text], isTargeted: nil, perform: handleDrop)
    }

    private var isActive: Bool {
        browserManager.currentTab(for: windowState)?.id == tab.id
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let s = obj as? String, let id = UUID(uuidString: s) else {
                return
            }
            DispatchQueue.main.async {
                let all = browserManager.tabManager.allTabs()
                guard let dropped = all.first(where: { $0.id == id }) else {
                    return
                }
                let windowId = windowState.id
                if splitManager.isSplit(for: windowId) {
                    if side == .left,
                        splitManager.leftTabId(for: windowId) == dropped.id
                    {
                        return
                    }
                    if side == .right,
                        splitManager.rightTabId(for: windowId) == dropped.id
                    {
                        return
                    }
                }
                splitManager.enterSplit(
                    with: dropped,
                    placeOn: side,
                    in: windowState
                )
                // Ensure any local drag-hide state is cleared after drop
                self.draggedItem = nil
                NotificationCenter.default.post(
                    name: .tabDragDidEnd,
                    object: nil
                )
            }
        }
        // Also proactively clear drag-hide state in case the drop short-circuits internally
        DispatchQueue.main.async {
            self.draggedItem = nil
            NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
        }
        return true
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
