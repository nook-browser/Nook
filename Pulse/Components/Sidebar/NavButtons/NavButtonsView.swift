//
//  NavButtonsView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

struct NavButtonsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    var sidebarThreshold: CGFloat = 160
    var body: some View {
        HStack(spacing: 2) {
            MacButtonsView()
                .frame(width: 70)
            if browserManager.sidebarWidth > sidebarThreshold {
                NavButton(iconName: "sidebar.left") {
                    browserManager.toggleSidebar()
                }
            }
            
            Spacer()
            
            if browserManager.sidebarWidth < sidebarThreshold {
                Menu {
                    Label("Toggle Sidebar", systemImage: "sidebar.left")
                    Label("Backward", systemImage: "arrow.backward")
                    Label("Forward", systemImage: "arrow.forward")
                } label: {
                    NavButton(iconName: "ellipsis")
                }
                .buttonStyle(PlainButtonStyle())

            } else {
                HStack(alignment: .center, spacing: 8) {
                    NavButton(iconName: "arrow.backward", disabled: browserManager.tabManager.currentTab?.canGoBack ?? true) {
                        browserManager.tabManager.currentTab?.goBack()
                        print("back")
                    }
                    NavButton(iconName: "arrow.forward", disabled: browserManager.tabManager.currentTab?.canGoForward ?? true) {
                        browserManager.tabManager.currentTab?.goForward()
                        print("forward")

                    }
                    NavButton(iconName: "arrow.clockwise") {
                        browserManager.tabManager.currentTab?.refresh()
                    }
                }
            }

        }
    }
}
