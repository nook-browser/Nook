//
//  NavButtonsView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

// Wrapper to properly observe Tab object and use active window's WebView
@MainActor
class ObservableTabWrapper: ObservableObject {
    @Published var tab: Tab?
    weak var browserManager: BrowserManager?
    weak var windowState: BrowserWindowState?

    var canGoBack: Bool {
        // Use active window's WebView for navigation state to ensure consistency
        if let tab = tab,
           let browserManager = browserManager,
           let windowState = windowState,
           let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
            return webView.canGoBack
        }
        return tab?.canGoBack ?? false // Fallback to tab's default WebView
    }

    var canGoForward: Bool {
        // Use active window's WebView for navigation state to ensure consistency
        if let tab = tab,
           let browserManager = browserManager,
           let windowState = windowState,
           let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
            return webView.canGoForward
        }
        return tab?.canGoForward ?? false // Fallback to tab's default WebView
    }

    func updateTab(_ newTab: Tab?) {
        tab = newTab
        objectWillChange.send()
    }

    func setContext(browserManager: BrowserManager, windowState: BrowserWindowState) {
        self.browserManager = browserManager
        self.windowState = windowState
    }
}

struct NavButtonsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    var sidebarThreshold: CGFloat = 150
    @StateObject private var tabWrapper = ObservableTabWrapper()

    var body: some View {
        HStack(spacing: 2) {
            MacButtonsView()
                .frame(width: 70)
            NavButton(iconName: "sidebar.left", disabled: false, action: {
                browserManager.toggleSidebar(for: windowState)
            })

            Spacer()

            if windowState.sidebarWidth < sidebarThreshold {
                Menu {
                    Label("Reload", systemImage: "arrow.clockwise")
                    Label("Go Back", systemImage: "arrow.backward")
                    Label("Go Forward", systemImage: "arrow.forward")
                } label: {
                    NavButton(iconName: "ellipsis", disabled: false, action: {})
                }
                .buttonStyle(PlainButtonStyle())

            } else {
                HStack(alignment: .center, spacing: 8) {
                    NavButton(
                        iconName: "arrow.backward",
                        disabled: !tabWrapper.canGoBack,
                        action: {
                            // Use the active window's WebView to ensure navigation history consistency
                            if let tab = tabWrapper.tab,
                               let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
                                webView.goBack()
                            } else {
                                tabWrapper.tab?.goBack() // Fallback to original method
                            }
                        }
                    )
                    .contextMenu {
                        NavigationHistoryContextMenu(
                            historyType: .back,
                            windowState: windowState
                        )
                    }
                    NavButton(
                        iconName: "arrow.forward",
                        disabled: !tabWrapper.canGoForward,
                        action: {
                            // Use the active window's WebView to ensure navigation history consistency
                            if let tab = tabWrapper.tab,
                               let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
                                webView.goForward()
                            } else {
                                tabWrapper.tab?.goForward() // Fallback to original method
                            }
                        }
                    )
                    .contextMenu {
                        NavigationHistoryContextMenu(
                            historyType: .forward,
                            windowState: windowState
                        )
                    }
                    RefreshButton(action: {
                        tabWrapper.tab?.refresh()
                    })
                }
            }
        }
        .onAppear {
            tabWrapper.setContext(browserManager: browserManager, windowState: windowState)
            updateCurrentTab()
        }
        .onChange(of: browserManager.currentTab(for: windowState)?.id) { _, _ in
            updateCurrentTab()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            updateCurrentTab()
        }
    }

    private func updateCurrentTab() {
        tabWrapper.updateTab(browserManager.currentTab(for: windowState))
    }
}