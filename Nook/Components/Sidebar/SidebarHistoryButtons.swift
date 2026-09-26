// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarHistoryButtons.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI
import WebKit
import NookDesign
import NookWeb
import NookUI

/// Compact back, forward and reload controls in the title row. The space name gives way before
/// them, and `Size.sidebarMin` keeps the sidebar wide enough to show them whole.
struct SidebarHistoryButtons: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        HStack(spacing: 0) {
            Button("Go Back", systemImage: "chevron.backward", action: goBack)
                .disabled(!canGoBack)
                .contextMenu {
                    NavigationHistoryContextMenu(historyType: .back, windowState: windowState)
                }
            divider
            Button("Go Forward", systemImage: "chevron.forward", action: goForward)
                .disabled(!canGoForward)
                .contextMenu {
                    NavigationHistoryContextMenu(historyType: .forward, windowState: windowState)
                }
            divider
            Button(action: reloadOrStop) {
                Image(systemName: session?.isLoading == true ? "xmark" : "arrow.clockwise")
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .labelStyle(.iconOnly)
        .imageScale(.large)
        .buttonStyle(NookIconButtonStyle())
        .frame(height: NookDesign.Size.iconButton)
    }

    private var divider: some View {
        Divider().padding(.vertical, NookDesign.Spacing.sm)
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

    private func reloadOrStop() {
        if session?.isLoading == true { session?.stop() } else { session?.refresh() }
    }
}
