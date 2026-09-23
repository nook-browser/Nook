// Licensed under GPL-3.0. See LICENSE.
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

struct SidebarMenu: View {
    @Environment(BrowserWindowState.self) private var windowState
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings

    private let tabColumnWidth: CGFloat = 110

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
            VStack(spacing: NookDesign.Spacing.xxl) {
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
                .nookGlassControls(in: Circle())
                Spacer()
            }
            .padding(.leading, NookDesign.Spacing.md)
            .padding(.bottom, NookDesign.Spacing.md)
        }
        .padding(NookDesign.Spacing.md)
        .frame(width: tabColumnWidth)
        .frame(maxHeight: .infinity)
        .background(NookDesign.Surface.fill)
    }
}
