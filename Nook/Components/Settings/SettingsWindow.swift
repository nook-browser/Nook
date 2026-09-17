//
//  SettingsWindow.swift
//  Nook
//
//  Created by Claude on 26/03/2026.
//

import SwiftUI
import NookDesign

struct SettingsWindow: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @Environment(\.nookSettings) var nookSettings

    private let windowSize = CGSize(width: 780, height: 540)

    var body: some View {
        @Bindable var navigation = SettingsNavigation.shared
        // Like System Settings: the sidebar always shows, and the selected page names the window.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebar(selection: $navigation.currentSettingsTab)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            SettingsDetailPane(tab: navigation.currentSettingsTab)
                .environmentObject(browserManager)
                .environmentObject(gradientColorManager)
                .navigationTitle(navigation.currentSettingsTab.name)
        }
        .frame(width: windowSize.width, height: windowSize.height)
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var selection: SettingsTabs
    @EnvironmentObject var browserManager: BrowserManager

    private let sidebarWidth: CGFloat = 220

    var body: some View {
        List(selection: $selection) {
            ForEach(Array(SettingsTabs.sidebarGroups.enumerated()), id: \.offset) { _, group in
                Section {
                    ForEach(group.tabs, id: \.self) { tab in
                        if tab == .extensions {
                            if browserManager.extensionManager != nil {
                                sidebarRow(tab)
                            }
                        } else {
                            sidebarRow(tab)
                        }
                    }
                } header: {
                    if let title = group.title {
                        Text(title)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(sidebarWidth)
    }

    private func sidebarRow(_ tab: SettingsTabs) -> some View {
        Label {
            Text(tab.name)
                .font(NookDesign.Font.body)
        } icon: {
            Image(systemName: tab.icon)
                .font(NookDesign.Font.caption)
                .foregroundStyle(.white)
                .frame(
                    width: NookDesign.Size.settingsChip,
                    height: NookDesign.Size.settingsChip
                )
                .background(
                    NookDesign.Radius.shape(NookDesign.Radius.sm)
                        .fill(tab.iconColor.gradient)
                )
        }
        .frame(height: NookDesign.Size.navRow)
        .tag(tab)
    }
}

// MARK: - Detail Pane

private struct SettingsDetailPane: View {
    let tab: SettingsTabs
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        Group {
            switch tab {
            case .general:
                SettingsGeneralTab()
            case .appearance:
                SettingsAppearanceTab()
            case .ai:
                SettingsAITab()
            case .privacy:
                PrivacySettingsView()
            case .adBlocker:
                SettingsAdBlockerTab()
            case .youTube:
                SettingsYouTubeTab()
            case .socialMedia:
                SettingsSocialMediaTab()
            case .airTrafficControl:
                AirTrafficControlSettingsView()
            case .spaces:
                SpacesSettingsView()
            case .shortcuts:
                ShortcutsSettingsView()
            case .extensions:
                if let extensionManager = browserManager.extensionManager {
                    ExtensionsSettingsView(extensionManager: extensionManager)
                }
            case .advanced:
                AdvancedSettingsView()
            }
        }
    }
}
