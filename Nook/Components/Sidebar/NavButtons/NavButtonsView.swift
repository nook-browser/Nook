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
        if let tab = tab,
           let browserManager = browserManager,
           let windowState = windowState,
           let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
            return webView.canGoBack
        }
        return tab?.canGoBack ?? false
    }

    var canGoForward: Bool {
        if let tab = tab,
           let browserManager = browserManager,
           let windowState = windowState,
           let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
            return webView.canGoForward
        }
        return tab?.canGoForward ?? false
    }

    func updateTab(_ newTab: Tab?) {
        tab = newTab
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
    var effectiveSidebarWidth: CGFloat?
    @StateObject private var tabWrapper = ObservableTabWrapper()

    var body: some View {
        let sidebarOnLeft = browserManager.settingsManager.sidebarPosition == .left
        let sidebarWidthForLayout = effectiveSidebarWidth ?? windowState.sidebarWidth

        HStack(spacing: 2) {
            if sidebarOnLeft {
                MacButtonsView()
                    .frame(width: 70)
            }

            NavButton(iconName: sidebarOnLeft ? "sidebar.left" : "sidebar.right", disabled: false, action: {
                browserManager.toggleSidebar(for: windowState)
            })

            Spacer()

            HStack(alignment: .center, spacing: 8) {
                if sidebarWidthForLayout < sidebarThreshold {
                    Menu {
                        Button(action: refreshCurrentTab) {
                            Label("Reload", systemImage: "arrow.clockwise")
                        }
                        Button(action: goBack) {
                            Label("Go Back", systemImage: "arrow.backward")
                        }
                        .disabled(!tabWrapper.canGoBack)
                        Button(action: goForward) {
                            Label("Go Forward", systemImage: "arrow.forward")
                        }
                        .disabled(!tabWrapper.canGoForward)
                    } label: {
                        NavButton(iconName: "ellipsis", disabled: false, action: {})
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    HStack(alignment: .center, spacing: 8) {
                        NavButton(
                            iconName: "arrow.backward",
                            disabled: !tabWrapper.canGoBack,
                            action: goBack
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
                            action: goForward
                        )
                        .contextMenu {
                            NavigationHistoryContextMenu(
                                historyType: .forward,
                                windowState: windowState
                            )
                        }
                        RefreshButton(action: refreshCurrentTab)
                    }
                }

                if !sidebarOnLeft {
                    MacButtonsView()
                        .frame(width: 70)
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

    private func goBack() {
        if let tab = tabWrapper.tab,
           let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
            webView.goBack()
        } else {
            tabWrapper.tab?.goBack()
        }
    }

    private func goForward() {
        if let tab = tabWrapper.tab,
           let webView = browserManager.getWebView(for: tab.id, in: windowState.id) {
            webView.goForward()
        } else {
            tabWrapper.tab?.goForward()
        }
    }

    private func refreshCurrentTab() {
        tabWrapper.tab?.refresh()
    }
}
