//
//  SidebarMenu.swift
//  Nook
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import SwiftUI

enum Tabs {
    case history
    case downloads
}

struct SidebarMenu: View {
    @State private var selectedTab: Tabs = .history
    @EnvironmentObject var windowState: BrowserWindowState

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            VStack {
                HStack {
                    MacButtonsView()
                        .frame(width: 70, height: 20)
                        .padding(8)
                    Spacer()
                }

                Spacer()
                VStack(spacing: 20) {
                    SidebarMenuTab(
                        image: "clock",
                        activeImage: "clock.fill",
                        title: "History",
                        isActive: selectedTab == .history,
                        action: {
                            selectedTab = .history
                        }
                    )
                    SidebarMenuTab(
                        image: "arrow.down.circle",
                        activeImage: "arrow.down.circle.fill",
                        title: "Downloads",
                        isActive: selectedTab == .downloads,
                        action: {
                            selectedTab = .downloads
                        }
                    )
                }

                Spacer()
                HStack {
                    NavButton(iconName: "arrow.backward", disabled: false, action: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            windowState.isSidebarMenuVisible = false
                            let restoredWidth = windowState.savedSidebarWidth
                            windowState.sidebarWidth = restoredWidth
                            windowState.sidebarContentWidth = max(restoredWidth - 16, 0)
                        }
                    })
                    Spacer()
                }
                .padding(.leading, 8)
                .padding(.bottom, 8)
            }
            .padding(8)
            .frame(width: 110)
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.2))
            VStack {
                switch selectedTab {
                case .history:
                    SidebarMenuHistoryTab()
                case .downloads:
                    SidebarMenuDownloadsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea()
    }
}
