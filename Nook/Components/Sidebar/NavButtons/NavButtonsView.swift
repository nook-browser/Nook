//
//  NavButtonsView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

struct NavButtonsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    var sidebarThreshold: CGFloat = 210
    var body: some View {
        HStack(spacing: 2) {
            MacButtonsView()
                .frame(width: 70)
                NavButton(iconName: "sidebar.left") {
                    browserManager.toggleSidebar(for: windowState)
                }
            }
            
            Spacer()
            
            if windowState.sidebarWidth < sidebarThreshold {
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
                    NavButton(iconName: "arrow.backward", disabled: !(browserManager.currentTab(for: windowState)?.canGoBack ?? false)) {
                        browserManager.currentTab(for: windowState)?.goBack()
                        print("back")
                    }
                    NavButton(iconName: "arrow.forward", disabled: !(browserManager.currentTab(for: windowState)?.canGoForward ?? false)) {
                        browserManager.currentTab(for: windowState)?.goForward()
                        print("forward")

                    }
                    RefreshButton() {
                        browserManager.currentTab(for: windowState)?.refresh()
                    }
                }
            }

        }
    }
