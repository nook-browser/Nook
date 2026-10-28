// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarMenu.swift
//  Nook
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import AppKit
import SwiftUI
import NookDesign
import NookTabsCore
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
                case .spaces:
                    SidebarMenuSpacesTab(onOpenSpace: openSpace, onNewSpace: newSpace)
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

    private func close() {
        LibraryMotion.close(windowState)
    }

    private func openSpace(_ id: UUID) {
        close()
        withAnimation(NookDesign.Motion.standard) {
            browserManager.tabs.setSpace(id, in: windowState)
        }
    }

    private func newSpace() {
        close()
        withAnimation(NookDesign.Motion.standard) {
            windowState.spaceDraftTheme = .randomPreset()
        }
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
                    image: "square.on.square",
                    activeImage: "square.fill.on.square.fill",
                    title: "Spaces",
                    isActive: windowState.sidebarMenuSelectedTab == .spaces,
                    action: {
                        windowState.sidebarMenuSelectedTab = .spaces
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
                Button("Back", systemImage: "arrow.backward", action: close)
                .nookIconButtons()
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
