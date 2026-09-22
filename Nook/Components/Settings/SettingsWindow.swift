// Licensed under GPL-3.0. See LICENSE.
//
//  SettingsWindow.swift
//  Nook
//
//  Created by Claude on 26/03/2026.
//

import SwiftUI
import NookDesign
import NookUI

struct SettingsWindow: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @Environment(\.nookSettings) var nookSettings

    private let windowSize = CGSize(width: 780, height: 540)
    @State private var query = ""

    // Back/forward walk every place visited, sidebar picks and sub-pane pushes alike.
    @State private var paths: [SettingsTabs: [SettingsSubPane]] = [:]
    @State private var back: [SettingsLocation] = []
    @State private var forward: [SettingsLocation] = []
    @State private var restoring = false

    private var location: SettingsLocation {
        let tab = SettingsNavigation.shared.currentSettingsTab
        return SettingsLocation(tab: tab, path: paths[tab] ?? [])
    }

    var body: some View {
        let navigation = SettingsNavigation.shared
        let tab = navigation.currentSettingsTab
        // A sidebar pick lands on the tab's root, like System Settings.
        let selection = Binding(
            get: { navigation.currentSettingsTab },
            set: { paths[$0] = []; navigation.currentSettingsTab = $0 }
        )
        // Like System Settings: the sidebar always shows, and the selected page names the window.
        NavigationSplitView(columnVisibility: .constant(.all)) {
            SettingsSidebar(selection: selection, query: $query)
                .toolbar(removing: .sidebarToggle)
                .searchable(text: $query, placement: .sidebar, prompt: "Search")
        } detail: {
            SettingsDetailPane(
                tab: tab,
                path: Binding(get: { paths[tab] ?? [] }, set: { paths[tab] = $0 }),
                history: HistoryToolbar(
                    canGoBack: !back.isEmpty,
                    canGoForward: !forward.isEmpty,
                    goBack: { go(from: &back, to: &forward) },
                    goForward: { go(from: &forward, to: &back) }
                )
            )
            .environmentObject(browserManager)
            .environmentObject(gradientColorManager)
            // Rebuilds the pane per tab so each opens scrolled to the top.
            .id(tab)
        }
        .onChange(of: location) { old, _ in
            if restoring { restoring = false; return }
            // A fresh move abandons the forward history, like a browser.
            back.append(old)
            forward.removeAll()
        }
        // System Settings is resizable and remembers its size; a fixed frame is not.
        .frame(minWidth: windowSize.width, minHeight: windowSize.height)
        .navigationSplitViewStyle(.balanced)
        .toggleStyle(SettingsSwitch())
        .background(UnifiedToolbarWindow())
    }

    private func go(from stack: inout [SettingsLocation], to other: inout [SettingsLocation]) {
        guard let target = stack.popLast() else { return }
        other.append(location)
        restoring = true
        paths[target.tab] = target.path
        SettingsNavigation.shared.currentSettingsTab = target.tab
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

/// System Settings keeps both buttons showing, disabled when there is nowhere to go.
/// Applied to the root pane and to every pushed pane, since a push replaces the toolbar.
/// The `.navigation` group style is what draws System Settings' one capsule with the divider;
/// a plain ControlGroup collapses into the overflow menu.
private struct HistoryToolbar: ViewModifier {
    let canGoBack: Bool
    let canGoForward: Bool
    let goBack: () -> Void
    let goForward: () -> Void

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .navigation) {
                ControlGroup {
                    Button(action: goBack) {
                        Image(systemName: "chevron.backward")
                    }
                    .disabled(!canGoBack)

                    Button(action: goForward) {
                        Image(systemName: "chevron.forward")
                    }
                    .disabled(!canGoForward)
                }
                .controlGroupStyle(.navigation)
                .controlSize(.large)
            }
        }
    }
}

/// The Settings scene ignores `.windowToolbarStyle` and lays its toolbar out in the old two-row
/// preference style. System Settings' single row (back button, then the title inline, traffic
/// lights 26pt in from the corner) needs the style set on the window itself.
private struct UnifiedToolbarWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class Probe: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // SwiftUI installs the toolbar after the view lands, so wait one turn.
            guard let window else { return }
            DispatchQueue.main.async { window.toolbarStyle = .unified }
        }
    }
}

// MARK: - Sidebar

private struct SettingsSidebar: View {
    @Binding var selection: SettingsTabs
    @Binding var query: String
    @EnvironmentObject var browserManager: BrowserManager

    private let sidebarWidth: CGFloat = 230

    var body: some View {
        List(selection: $selection) {
            ForEach(Array(SettingsTabs.sidebarGroups.enumerated()), id: \.offset) { _, group in
                let tabs = group.tabs.filter { tab in
                    guard tab.matches(query) else { return false }
                    return tab != .extensions || browserManager.extensionManager != nil
                }
                if !tabs.isEmpty {
                    Section {
                        ForEach(tabs, id: \.self) { tab in
                            sidebarRow(tab)
                        }
                    } header: {
                        // A group header reads as a filter label while searching, so it goes.
                        if let title = group.title, query.isEmpty {
                            Text(title)
                        }
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
        } icon: {
            Image(systemName: tab.icon)
                .imageScale(.small)
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
        .tag(tab)
    }
}

// MARK: - Sub-Panes

/// Pushed destinations. Typed so back/forward can replay them.
enum SettingsSubPane: Hashable {
    case cookies
    case cache

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
    let history: HistoryToolbar
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
            .modifier(history)
            .navigationDestination(for: SettingsSubPane.self) { pane in
                pane.view
                    .navigationBarBackButtonHidden(true)
                    .modifier(history)
            }
        }
    }
}
