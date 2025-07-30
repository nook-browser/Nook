import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var isResizing = false
    @State private var isHovering = false
    @State private var startingWidth: CGFloat = 0

    var body: some View {
        HStack(spacing: 0) {
            VStack {
                HStack(spacing: 2) {
                    NavButtonsView()
                }
                .frame(height: 30)
                URLBarView(urlName: "about:blank")
                Spacer()
            }
            .frame(width: browserManager.sidebarWidth)

            Rectangle()
                .fill(isHovering ? Color.blue.opacity(0.3) : Color.clear)
                .frame(width: 4)
                .onHover { hovering in
                    isHovering = hovering
                    if hovering {
                        NSCursor.resizeLeftRight.set()
                    } else {
                        NSCursor.arrow.set()
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isResizing {
                                startingWidth = browserManager.sidebarWidth
                                isResizing = true
                            }
                            let newWidth =
                                startingWidth + value.translation.width
                            browserManager.updateSidebarWidth(
                                max(100, min(300, newWidth))
                            )
                        }
                        .onEnded { _ in
                            isResizing = false
                        }
                )
        }
    }
}
