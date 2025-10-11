import SwiftUI

struct SplitTabRow: View {
    let left: Tab
    let right: Tab
    let spaceId: UUID
    @Binding var draggedItem: UUID?
    
    let onActivate: (Tab) -> Void
    let onClose: (Tab) -> Void
    
    @Environment(BrowserManager.self) private var browserManager
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
        .onReceive(NotificationCenter.default.publisher(for: .tabDragDidEnd)) { _ in
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
    @Environment(BrowserManager.self) private var browserManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    
    var body: some View {
        ZStack {
            Button(action: onActivate) {
                HStack(spacing: 8) {
                    tab.favicon
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    Text(tab.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(isActive ? Color.black : AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 4)
                    if isHovering {
                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(isActive ? Color.black : AppColors.textSecondary)
                                .padding(3)
                                .background(AppColors.controlBackgroundHover)
                                .clipShape(RoundedRectangle(cornerRadius: 5))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .transition(.opacity.combined(with: .scale))
                    }
                }
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            .onHover { hovering in withAnimation(.easeInOut(duration: 0.15)) { isHovering = hovering } }
            .contextMenu {
                Button("Close Tab", action: onClose)
            }
        }
        .onTabDrag(tab.id, draggedItem: $draggedItem)
        .opacity(draggedItem == tab.id ? 0.25 : 1.0)
        .background(background)
        .onDrop(of: [.text], isTargeted: nil, perform: handleDrop)
    }
    
    private var isActive: Bool {
        browserManager.currentTab(for: windowState)?.id == tab.id
    }
    
    private var background: some View {
        Group {
            if isActive { AppColors.activeTab }
            else if isHovering { AppColors.controlBackgroundHover }
            else { Color.clear }
        }
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let s = obj as? String, let id = UUID(uuidString: s) else { return }
            DispatchQueue.main.async {
                let all = browserManager.tabManager.allTabs()
                guard let dropped = all.first(where: { $0.id == id }) else { return }
                let windowId = windowState.id
                if splitManager.isSplit(for: windowId) {
                    if side == .left, splitManager.leftTabId(for: windowId) == dropped.id { return }
                    if side == .right, splitManager.rightTabId(for: windowId) == dropped.id { return }
                }
                splitManager.enterSplit(with: dropped, placeOn: side, in: windowState)
                // Ensure any local drag-hide state is cleared after drop
                self.draggedItem = nil
                NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
            }
        }
        // Also proactively clear drag-hide state in case the drop short-circuits internally
        DispatchQueue.main.async {
            self.draggedItem = nil
            NotificationCenter.default.post(name: .tabDragDidEnd, object: nil)
        }
        return true
    }
}
