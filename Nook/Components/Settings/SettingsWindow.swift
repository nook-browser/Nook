//
//  SettingsWindow.swift
//  Nook
//
//  Created by Claude on 26/03/2026.
//

import SwiftUI

struct SettingsWindow: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        @Bindable var settings = nookSettings
        NavigationSplitView {
            SettingsSidebar(selection: $settings.currentSettingsTab)
        } detail: {
            SettingsDetailPane(tab: nookSettings.currentSettingsTab)
                .environmentObject(browserManager)
                .environmentObject(gradientColorManager)
        }
        .frame(
            width: NookDesign.Size.settingsWindowWidth,
            height: NookDesign.Size.settingsWindowHeight
        )
        .navigationSplitViewStyle(.balanced)
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var selection: SettingsTabs
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        List(selection: $selection) {
            ForEach(Array(SettingsTabs.sidebarGroups.enumerated()), id: \.offset) { index, group in
                Section {
                    ForEach(group, id: \.self) { tab in
                        if tab == .extensions {
                            if browserManager.extensionManager != nil {
                                sidebarRow(tab)
                            }
                        } else {
                            sidebarRow(tab)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(NookDesign.Size.settingsSidebar)
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
            case .sponsorBlock:
                SettingsSponsorBlockTab()
            case .airTrafficControl:
                AirTrafficControlSettingsView()
            case .profiles:
                ProfilesSettingsView()
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
