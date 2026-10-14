// Licensed under GPL-3.0. See LICENSE.
//
//  DevPanelColumn.swift
//  Nook
//
//  The right column. The AI chat alone while Developer Mode is off; with it on, tabs for the chat,
//  the Console and the Network log of the window's selected page.
//

import SwiftUI
import NookDesign
import NookWeb
import NookUI

struct DevPanelColumn: View {
    @Environment(BrowserWindowState.self) private var windowState
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings

    private var tabs: [DevPanelTab] {
        nookSettings.showAIAssistant ? DevPanelTab.allCases : DevPanelTab.allCases.filter { $0 != .agent }
    }

    private var selectedTab: DevPanelTab {
        tabs.contains(windowState.devPanelTab) ? windowState.devPanelTab : tabs[0]
    }

    var body: some View {
        if !nookSettings.developerModeEnabled {
            SidebarAIChat()
        } else {
            VStack(spacing: 0) {
                // The chat's scroll view runs up under the title band and would take the tab bar's clicks.
                tabBar.zIndex(1)
                switch selectedTab {
                case .agent:
                    SidebarAIChat()
                case .console:
                    DevConsoleView(capture: session?.devCapture, session: session)
                case .network:
                    DevNetworkView(capture: session?.devCapture, session: session)
                case .blocker:
                    DevBlockerView(capture: session?.devCapture, session: session)
                case .perf:
                    DevPerfView(capture: session?.devCapture, session: session)
                }
            }
        }
    }

    private var session: PageSession? {
        browserManager.tabs.selectedSession(in: windowState)
    }

    private var tabBar: some View {
        HStack(spacing: NookDesign.Spacing.xxs) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    windowState.devPanelTab = tab
                } label: {
                    Text(tab.title)
                        .font(NookDesign.Font.body)
                        .foregroundStyle(tab == selectedTab ? .primary : .secondary)
                        .padding(.horizontal, NookDesign.Spacing.md)
                        .frame(height: NookDesign.Size.iconButton)
                        .nookRowSelection(tab == selectedTab)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            Spacer()
            if selectedTab != .agent {
                Button("Close", systemImage: "xmark") {
                    withAnimation(NookDesign.Motion.standard) {
                        windowState.isSidebarAIChatVisible = false
                    }
                }
                .nookIconButtons()
            }
        }
        .padding(.horizontal, NookDesign.Spacing.md)
        .padding(.top, NookDesign.Spacing.md)
    }
}

private extension DevPanelTab {
    var title: String {
        switch self {
        case .agent: return "Agent"
        case .console: return "Console"
        case .network: return "Network"
        case .blocker: return "Blocker"
        case .perf: return "Perf"
        }
    }
}

/// Shown in place of a tab's content when the page has no capture yet.
struct DevPanelEmpty: View {
    var body: some View {
        Text("Reload the page to capture it.")
            .font(NookDesign.Font.bodyRegular)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
