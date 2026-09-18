// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  SidebarMenu.swift
//  Nook
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import SwiftUI
import NookDesign
import NookWeb
import NookUI

typealias Tabs = SidebarMenuTab

struct SidebarMenu: View {
    @Environment(BrowserWindowState.self) private var windowState
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if nookSettings.sidebarPosition == .left{
                tabs
            }
            VStack {
                switch windowState.sidebarMenuSelectedTab {
                case .history:
                    SidebarMenuHistoryTab()
                case .downloads:
                    SidebarMenuDownloadsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if nookSettings.sidebarPosition == .right{
                tabs
            }
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea()
    }

    var tabs: some View{
        VStack {

            Spacer()
            VStack(spacing: 20) {
                SidebarMenuTab(
                    image: "clock",
                    activeImage: "clock.fill",
                    title: "History",
                    isActive: windowState.sidebarMenuSelectedTab == .history,
                    action: {
                        windowState.sidebarMenuSelectedTab = .history
                    }
                )
                SidebarMenuTab(
                    image: "arrow.down.circle",
                    activeImage: "arrow.down.circle.fill",
                    title: "Downloads",
                    isActive: windowState.sidebarMenuSelectedTab == .downloads,
                    action: {
                        windowState.sidebarMenuSelectedTab = .downloads
                    }
                )
            }
            
            Spacer()
            HStack {
                Button("Back", systemImage: "arrow.backward") {
                    withAnimation(NookDesign.Motion.standard) {
                        windowState.isSidebarMenuVisible = false
                        let restoredWidth = windowState.savedSidebarWidth
                        windowState.sidebarWidth = restoredWidth
                        windowState.sidebarContentWidth = max(restoredWidth - 16, 0)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(NookIconButtonStyle())
                .foregroundStyle(Color.primary)
                Spacer()
            }
            .padding(.leading, 8)
            .padding(.bottom, 8)
        }
        .padding(8)
        .frame(width: 110)
        .frame(maxHeight: .infinity)
        .background(.black.opacity(0.2))
    }
}
