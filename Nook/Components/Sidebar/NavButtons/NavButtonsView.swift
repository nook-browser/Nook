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
                .helpTooltip {
                    HStack(spacing: 5) {
                        Text(windowState.isSidebarVisible ? "Hide Sidebar" : "Lock Sidebar")
                        HStack(spacing: 2) {
                            KeyIcon(iconName: "command", type: .symbol)
                            KeyIcon(iconName: "S", type: .letter)
                        }

                    }
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
                    NavButton(iconName: "arrow.backward", disabled: browserManager.currentTab(for: windowState)?.canGoBack ?? true) {
                        browserManager.currentTab(for: windowState)?.goBack()
                        print("back")
                    }
                    .helpTooltip {
                        HStack(spacing: 5) {
                            Text("Go back")
                            HStack(spacing: 2) {
                                KeyIcon(iconName: "command", type: .symbol)
                                KeyIcon(iconName: "[", type: .letter)
                            }

                        }
                    }
                    NavButton(iconName: "arrow.forward", disabled: browserManager.currentTab(for: windowState)?.canGoForward ?? true) {
                        browserManager.currentTab(for: windowState)?.goForward()
                        print("forward")

                    }
                    .helpTooltip {
                        HStack(spacing: 5) {
                            Text("Go forward")
                            HStack(spacing: 2) {
                                KeyIcon(iconName: "command", type: .symbol)
                                KeyIcon(iconName: "]", type: .letter)
                            }

                        }
                    }
                    RefreshButton() {
                        browserManager.currentTab(for: windowState)?.refresh()
                    }
                    .helpTooltip {
                        HStack(spacing: 5) {
                            Text("Reload this page")
                            HStack(spacing: 2) {
                                KeyIcon(iconName: "command", type: .symbol)
                                KeyIcon(iconName: "R", type: .letter)
                            }

                        }
                    }
                }
            }

        }
    }
