// Licensed under GPL-3.0. See LICENSE.
//
//  NavButtonsView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI
import WebKit
import NookDesign
import NookWeb
import NookUI

struct NavButtonsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) var nookSettings
    var effectiveSidebarWidth: CGFloat?
    @State private var isMenuHovered = false

    var body: some View {
        let sidebarOnLeft = nookSettings.sidebarPosition == .left
        let sidebarWidthForLayout = effectiveSidebarWidth ?? windowState.sidebarWidth

        // Collapse thresholds: at 250pt default width all buttons fit comfortably
        // (5 buttons × 32pt + spacing ≈ 186pt, leaving ~48pt spacer in 234pt usable)
        let navigationCollapseThreshold: CGFloat = nookSettings.showAIAssistant ? 215 : 180
        let refreshCollapseThreshold: CGFloat = nookSettings.showAIAssistant ? 200 : 165
        let aiChatCollapseThreshold: CGFloat = 195

        let shouldCollapseNavigation = sidebarWidthForLayout < navigationCollapseThreshold
        let shouldCollapseRefresh = sidebarWidthForLayout < refreshCollapseThreshold
        let shouldCollapseAIChat = sidebarWidthForLayout < aiChatCollapseThreshold
        
        HStack(spacing: NookDesign.Spacing.xxs) {
            Button("Toggle Sidebar", systemImage: sidebarOnLeft ? "sidebar.left" : "sidebar.right") {
                browserManager.toggleSidebar(for: windowState)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NookIconButtonStyle())
            .foregroundStyle(Color.primary)
            
            if nookSettings.showAIAssistant && !shouldCollapseAIChat {
                Button("Toggle AI Assistant", systemImage: "sparkle") {
                    browserManager.toggleAISidebar(for: windowState)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(NookIconButtonStyle())
                .foregroundStyle(Color.primary)
            }
            
            Spacer()
            
            HStack(alignment: .center, spacing: NookDesign.Spacing.xxs) {
                if shouldCollapseNavigation {
                    collapsedMenu(
                        includeNavigation: true,
                        includeRefresh: shouldCollapseRefresh,
                        includeAIChat: shouldCollapseAIChat && nookSettings.showAIAssistant
                    )
                } else {
                    HStack(alignment: .center, spacing: NookDesign.Spacing.xxs) {
                        Button("Go Back", systemImage: "arrow.backward", action: goBack)
                            .labelStyle(.iconOnly)
                            .buttonStyle(NookIconButtonStyle())
                            .foregroundStyle(Color.primary)
                            .disabled(!canGoBack)
                            .contextMenu {
                                NavigationHistoryContextMenu(
                                    historyType: .back,
                                    windowState: windowState
                                )
                            }
                        
                        Button("Go Forward", systemImage: "arrow.forward", action: goForward)
                            .labelStyle(.iconOnly)
                            .buttonStyle(NookIconButtonStyle())
                            .foregroundStyle(Color.primary)
                            .disabled(!canGoForward)
                            .contextMenu {
                                NavigationHistoryContextMenu(
                                    historyType: .forward,
                                    windowState: windowState
                                )
                            }
                    }
                    
                    if shouldCollapseRefresh || shouldCollapseAIChat {
                        collapsedMenu(
                            includeNavigation: false,
                            includeRefresh: shouldCollapseRefresh,
                            includeAIChat: shouldCollapseAIChat && nookSettings.showAIAssistant
                        )
                    }
                }
                
                if !shouldCollapseRefresh {
                    Button {
                        if session?.isLoading == true {
                            session?.stop()
                        } else {
                            refreshCurrentTab()
                        }
                    } label: {
                        Image(systemName: session?.isLoading == true ? "xmark" : "arrow.clockwise")
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(NookIconButtonStyle())
                    .foregroundStyle(Color.primary)
                }
                
            }
        }
        .frame(maxWidth: .infinity)
        .background(
            DoubleClickView {
                if let window = NSApp.keyWindow {
                    window.performZoom(nil)
                }
            }
        )
    }

    /// Nil while another window holds the page: its controls stay inert until Move Here.
    private var session: PageSession? {
        browserManager.tabs.controllableSession(in: windowState)
    }

    private var canGoBack: Bool { session?.canGoBack ?? false }
    private var canGoForward: Bool { session?.canGoForward ?? false }

    /// This window's own view of the page, so a clone navigates in its window.
    private var windowWebView: WKWebView? {
        session.flatMap { browserManager.webViewCoordinator?.getWebView(for: $0.itemID, in: windowState.id) }
    }

    private func goBack() {
        if let webView = windowWebView { webView.goBack() } else { session?.goBack() }
    }

    private func goForward() {
        if let webView = windowWebView { webView.goForward() } else { session?.goForward() }
    }

    private func refreshCurrentTab() {
        session?.refresh()
    }
    
    @ViewBuilder
    private func collapsedMenu(includeNavigation: Bool, includeRefresh: Bool, includeAIChat: Bool = false) -> some View {
        if includeNavigation || includeRefresh || includeAIChat {
            Menu {
                if includeNavigation {
                    Button(action: goBack) {
                        Label("Go Back", systemImage: "arrow.backward")
                    }
                    .disabled(!canGoBack)

                    Button(action: goForward) {
                        Label("Go Forward", systemImage: "arrow.forward")
                    }
                    .disabled(!canGoForward)
                }

                if includeAIChat {
                    if includeNavigation {
                        Divider()
                    }
                    Button(action: { browserManager.toggleAISidebar(for: windowState) }) {
                        Label("Toggle AI Assistant", systemImage: "sparkle")
                    }
                }

                if includeRefresh {
                    if includeNavigation || includeAIChat {
                        Divider()
                    }
                    Button(action: refreshCurrentTab) {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                }
            } label: {
                Label("Navigation", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
            }
            .menuStyle(.button)
            .buttonStyle(NookIconButtonStyle())
        }
    }
}
