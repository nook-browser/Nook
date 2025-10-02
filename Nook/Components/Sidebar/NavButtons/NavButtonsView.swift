//
//  NavButtonsView.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//
import SwiftUI

// Wrapper to properly observe Tab object
@MainActor
class ObservableTabWrapper: ObservableObject {
    @Published var tab: Tab?

    var canGoBack: Bool {
        tab?.canGoBack ?? false
    }

    var canGoForward: Bool {
        tab?.canGoForward ?? false
    }

    func updateTab(_ newTab: Tab?) {
        tab = newTab
        objectWillChange.send()
    }
}

struct NavButtonsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var windowState: BrowserWindowState
    var sidebarThreshold: CGFloat = 150
    @State private var showBackHistory = false
    @State private var showForwardHistory = false
    @StateObject private var tabWrapper = ObservableTabWrapper()

    var body: some View {
        HStack(spacing: 2) {
            MacButtonsView()
                .frame(width: 70)
            NavButton(iconName: "sidebar.left", disabled: false, action: {
                browserManager.toggleSidebar(for: windowState)
            }, onLongPress: nil)

            Spacer()

            if windowState.sidebarWidth < sidebarThreshold {
                Menu {
                    Label("Reload", systemImage: "arrow.clockwise")
                    Label("Go Back", systemImage: "arrow.backward")
                    Label("Go Forward", systemImage: "arrow.forward")
                } label: {
                    NavButton(iconName: "ellipsis", disabled: false, action: {}, onLongPress: nil)
                }
                .buttonStyle(PlainButtonStyle())

            } else {
                HStack(alignment: .center, spacing: 8) {
                    NavButton(
                        iconName: "arrow.backward",
                        disabled: !tabWrapper.canGoBack,
                        action: {
                            tabWrapper.tab?.goBack()
                        },
                        onLongPress: {
                            showBackHistory = true
                        }
                    )
                    NavButton(
                        iconName: "arrow.forward",
                        disabled: !tabWrapper.canGoForward,
                        action: {
                            tabWrapper.tab?.goForward()
                        },
                        onLongPress: {
                            showForwardHistory = true
                        }
                    )
                    RefreshButton() {
                        tabWrapper.tab?.refresh()
                    }
                }
            }
        }
        .onAppear {
            updateCurrentTab()
        }
        .onChange(of: browserManager.currentTab(for: windowState)?.id) { _, _ in
            updateCurrentTab()
        }
        .onReceive(Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()) { _ in
            updateCurrentTab()
        }
        .overlay(
            // Back history overlay
            NavigationHistoryOverlay(
                windowState: windowState,
                isPresented: $showBackHistory,
                menuType: .back
            )
            .environmentObject(browserManager)
        )
        .overlay(
            // Forward history overlay
            NavigationHistoryOverlay(
                windowState: windowState,
                isPresented: $showForwardHistory,
                menuType: .forward
            )
            .environmentObject(browserManager)
        )
    }

    private func updateCurrentTab() {
        tabWrapper.updateTab(browserManager.currentTab(for: windowState))
    }
}