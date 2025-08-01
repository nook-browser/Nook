import SwiftUI

struct SidebarView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var draggedTabIndex: Int?

    var body: some View {
        if browserManager.isSidebarVisible {
            VStack(spacing: 8) {
                        HStack(spacing: 2) {
                            NavButtonsView()
                        }
                        .frame(height: 30)
                        .background(
                            Rectangle()
                                .fill(Color.clear)
                                .contentShape(Rectangle())
                                .onTapGesture(count: 2) {
                                    DispatchQueue.main.async {
                                        zoomCurrentWindow()
                                    }
                                }
                        )
                        
                        URLBarView()
                        PinnedGrid()
                        SpaceTittle(
                            spaceName: "Development",
                            spaceIcon: "globe"
                        )
                        if(!browserManager.tabManager.tabs.isEmpty) {
                            SpaceSeparator()
                        }
                        NewTabButton()
                        ForEach(browserManager.tabManager.tabs) { tab in
                            SpaceTab(
                                tabName: tab.name,
                                tabURL: tab.name,
                                tabIcon: tab.favicon,
                                isActive: tab.isCurrentTab,
                                action: {
                                    DispatchQueue.main.async {
                                        tab.activate()
                                    }
                                },
                                onClose: {
                                    DispatchQueue.main.async {
                                        tab.closeTab()
                                    }
                                },
                            )

                        }

                Spacer()
            }
            .frame(width: browserManager.sidebarWidth)
            .padding(.top, 8)
            .overlay(DragWindowView())
        }
    }
}
