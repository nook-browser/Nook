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

/// Back, forward and reload in the title row: one glass group, squircled like the URL bar. A narrow
/// sidebar folds all three into one menu.
struct SidebarHistoryButtons: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    var body: some View {
        // Below this the space name would get under ~40pt beside the capsule.
        if windowState.sidebarWidth < 235 {
            collapsedMenu
        } else {
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
            // Dividers take any height offered; the group is the buttons' height.
            .frame(height: NookDesign.Size.iconButton)
            .labelStyle(.iconOnly)
            .buttonStyle(NookIconButtonStyle())
            .nookControlGlass(in: NookDesign.Radius.shape(NookDesign.Radius.md))
        }
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

    private var collapsedMenu: some View {
        Menu {
            Button(action: goBack) {
                Label("Go Back", systemImage: "arrow.backward")
            }
            .disabled(!canGoBack)

            Button(action: goForward) {
                Label("Go Forward", systemImage: "arrow.forward")
            }
            .disabled(!canGoForward)

            Divider()

            Button { session?.refresh() } label: {
                Label("Reload", systemImage: "arrow.clockwise")
            }
        } label: {
            Label("Navigation", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.button)
        .buttonStyle(NookIconButtonStyle())
    }
}
