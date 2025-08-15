//
//  NavButtonsView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

struct NavButtonsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    var sidebarThreshold: CGFloat = 210
    var body: some View {
        HStack(spacing: 2) {
            MacButtonsView()
                .frame(width: 70)
                NavButton(iconName: "sidebar.left") {
                    browserManager.toggleSidebar()
                }
            }
            
            Spacer()
            
            if browserManager.sidebarWidth < sidebarThreshold {
                Menu {
                    Label("Reload", systemImage: "arrow.clockwise")
                    Label("Go Back", systemImage: "arrow.backward")
                    Label("Go Forward", systemImage: "arrow.forward")
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
                    RefreshButton() {
                        browserManager.tabManager.currentTab?.refresh()
                    }
                }
            }

        }
    }

