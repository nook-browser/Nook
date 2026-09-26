// Licensed under GPL-3.0. See LICENSE.
//
//  SettingsWindow.swift
//  Nook
//
//  Created by Claude on 26/03/2026.
//

import AppKit
import SwiftUI
import NookDesign
import NookUI

struct SettingsWindow: View {
    static let presentationKey = "settings"

    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @Environment(\.isEnabled) private var isEnabled

    @Bindable var navigation: SettingsNavigation
    // Back/forward walk every place visited, sidebar picks and sub-pane pushes alike.
    @State private var paths: [SettingsTabs: [SettingsSubPane]] = [:]
    @State private var back: [SettingsLocation] = []
    @State private var forward: [SettingsLocation] = []
    @State private var restoring = false

    private var location: SettingsLocation {
        let tab = navigation.currentSettingsTab
        return SettingsLocation(tab: tab, path: paths[tab] ?? [])
    }

    private var selection: Binding<SettingsTabs> {
        Binding(
            get: { navigation.currentSettingsTab },
            set: { paths[$0] = []; navigation.currentSettingsTab = $0 }
        )
    }

    var body: some View {
        let tab = navigation.currentSettingsTab
        GeometryReader { geometry in
            let panelWidth = min(850, max(0, geometry.size.width - 40))
            let panelHeight = min(600, max(0, geometry.size.height - 40))
            let compact = panelWidth < 680

            NookPanel(maxWidth: 850, padding: 0) {
                HStack(spacing: 0) {
                    if !compact {
                        SettingsSidebar(selection: selection)
                            .frame(width: 220)
                        Divider()
                    }

                    detailPane(for: tab, compact: compact)
                }
                .frame(width: panelWidth, height: panelHeight)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: location) { old, _ in
            if restoring { restoring = false; return }
            // A fresh move abandons the forward history, like a browser.
            back.append(old)
            forward.removeAll()
        }
        .toggleStyle(SettingsSwitch())
        .onExitCommand {
            if isEnabled {
                browserManager.dialogManager.closeDialog()
            }
        }
    }

    private func go(from stack: inout [SettingsLocation], to other: inout [SettingsLocation]) {
        guard let target = stack.popLast() else { return }
        other.append(location)
        restoring = true
        paths[target.tab] = target.path
        navigation.currentSettingsTab = target.tab
    }

    private var availableTabs: [SettingsTabs] {
        SettingsTabs.sidebarGroups.flatMap { $0.tabs }.filter {
            $0 != .extensions || browserManager.extensionManager != nil
        }
    }

    private func detailPane(for tab: SettingsTabs, compact: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                if compact && paths[tab]?.last == nil {
                    Picker("Section", selection: selection) {
                        ForEach(availableTabs, id: \.self) { tab in
                            Text(tab.name).tag(tab)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(maxWidth: 180)
                }

                if !back.isEmpty || !forward.isEmpty {
                    Button {
                        go(from: &back, to: &forward)
                    } label: {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(back.isEmpty)
                    .accessibilityLabel("Back")

                    Button {
                        go(from: &forward, to: &back)
                    } label: {
                        Image(systemName: "chevron.forward")
                    }
                    .disabled(forward.isEmpty)
                    .accessibilityLabel("Forward")
                }

                if !compact || paths[tab]?.last != nil {
                    Text(paths[tab]?.last?.title ?? tab.name)
                        .font(NookDesign.Font.label)
                }
                Spacer()

                Button {
                    browserManager.dialogManager.closeDialog()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 28, height: 28)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Close Settings")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .frame(height: 52)

            Divider()

            SettingsDetailPane(
                tab: tab,
                path: Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 })
            )
            .environmentObject(browserManager)
            .environmentObject(gradientColorManager)
            .id(tab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// System Settings' switches measure 44x20, which is `.small`; a grouped Form's default
/// renders them at the mini size. Scoped to switches so buttons and pickers stay regular.
private struct SettingsSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Toggle(configuration)
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

/// One place the window can show: a sidebar tab and whatever is pushed on top of it.
private struct SettingsLocation: Hashable {
    let tab: SettingsTabs
    let path: [SettingsSubPane]
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var selection: SettingsTabs
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 40, height: 40)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Nook")
                        .font(.headline)
                    if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
                        Text("Version \(version)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            List(selection: $selection) {
                ForEach(Array(SettingsTabs.sidebarGroups.enumerated()), id: \.offset) { _, group in
                    let tabs = group.tabs.filter {
                        $0 != .extensions || browserManager.extensionManager != nil
                    }
                    if !tabs.isEmpty {
                        Section {
                            ForEach(tabs, id: \.self) { tab in
                                sidebarRow(tab)
                            }
                        } header: {
                            if let title = group.title {
                                Text(title)
                            }
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
        }
    }

    private func sidebarRow(_ tab: SettingsTabs) -> some View {
        Label {
            Text(tab.name)
        } icon: {
            Image(systemName: tab.icon)
                .imageScale(.small)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.primary)
                .frame(
                    width: NookDesign.Size.settingsChip,
                    height: NookDesign.Size.settingsChip
                )
                .background {
                    NookDesign.Radius.shape(NookDesign.Radius.sm)
                        .fill(.primary.opacity(0.12))
                }
                .overlay {
                    NookDesign.Radius.shape(NookDesign.Radius.sm)
                        .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                }
        }
        .tag(tab)
    }
}

// MARK: - Sub-Panes

/// Pushed destinations. Typed so back/forward can replay them.
enum SettingsSubPane: Hashable {
    case cookies
    case cache

    var title: String {
        switch self {
        case .cookies: "Cookie Management"
        case .cache: "Cache Management"
        }
    }

    @MainActor @ViewBuilder
    var view: some View {
        switch self {
        case .cookies: CookieManagementView()
        case .cache: CacheManagementView()
        }
    }
}

// MARK: - Detail Pane

private struct SettingsDetailPane: View {
    let tab: SettingsTabs
    @Binding var path: [SettingsSubPane]
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        NavigationStack(path: $path) {
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
            .navigationTitle(tab.name)
            .navigationDestination(for: SettingsSubPane.self) { pane in
                pane.view
                    .navigationBarBackButtonHidden(true)
            }
        }
    }
}
