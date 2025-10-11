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

public enum SidebarPosition: String, CaseIterable, Identifiable {
    case left
    case right
    public var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .left: return "Left"
        case .right: return "Right"
        }
    }
    
    var icon: String {
        switch self {
        case .left: return "sidebar.left"
        case .right: return "sidebar.right"
        }
    }
}

struct SidebarMenu: View {
    @State private var selectedTab: Tabs = .history
    @EnvironmentObject var windowState: BrowserWindowState
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            if browserManager.settingsManager.sidebarPosition == .left{
                tabs
            }
            VStack {
                switch selectedTab {
                case .history:
                    SidebarMenuHistoryTab()
                case .downloads:
                    SidebarMenuDownloadsTab()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if browserManager.settingsManager.sidebarPosition == .right{
                tabs
            }
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea()
    }
    
    var tabs: some View{
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
                Button("Back", systemImage: "arrow.backward") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        windowState.isSidebarMenuVisible = false
                        let restoredWidth = windowState.savedSidebarWidth
                        windowState.sidebarWidth = restoredWidth
                        windowState.sidebarContentWidth = max(restoredWidth - 16, 0)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(NavButtonStyle())
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
