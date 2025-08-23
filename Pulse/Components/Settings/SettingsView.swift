//
//  SettingsView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var selectedTab: SettingsTabs = .general

    var body: some View {
        HSplitView {
            // Sidebar
            VStack(spacing: 0) {
                // Tab bar header
                HStack {
                    Text("Settings")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                
                Divider()
                
                // Tab list
                List(selection: $selectedTab) {
                    ForEach([SettingsTabs.general, .privacy, .spaces, .profiles, .shortcuts, .extensions, .advanced], id: \.self) { tab in
                        Label(tab.name, systemImage: tab.icon)
                            .tag(tab)
                    }
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 200, maxWidth: 250)
            
            // Content
            VStack(spacing: 0) {
                // Tab content header
                HStack {
                    Image(systemName: selectedTab.icon)
                        .foregroundColor(.blue)
                    Text(selectedTab.name)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding()
                
                Divider()
                
                // Tab content
                Group {
                    switch selectedTab {
                    case .general:
                        GeneralSettingsView()
                    case .privacy:
                        PrivacySettingsView()
                    case .spaces:
                        SpacesSettingsView()
                    case .profiles:
                        ProfilesSettingsView()
                    case .shortcuts:
                        ShortcutsSettingsView()
                    case .extensions:
                        ExtensionsSettingsView()
                    case .advanced:
                        AdvancedSettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 600)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker(
                "Background Material",
                selection: $browserManager.settingsManager.currentMaterialRaw
            ) {
                ForEach(materials, id: \.value.rawValue) { material in
                    Text(material.name).tag(material.value.rawValue)
                }
            }
            .pickerStyle(.menu)
            
            Divider()
            
            Picker(
                "Search Engine",
                selection: $browserManager.settingsManager.searchEngine
            ) {
                ForEach(SearchProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.menu)
            
            Toggle(isOn: $browserManager.settingsManager.isLiquidGlassEnabled) {
                Text("Liquid Glass")
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Tab Unload Timeout")
                    .font(.headline)
                
                Text("Automatically unload inactive tabs to save memory")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                HStack {
                    Slider(
                        value: $browserManager.settingsManager.tabUnloadTimeout,
                        in: 60...1800, // 1 minute to 30 minutes
                        step: 60
                    ) {
                        Text("Tab Unload Timeout")
                    }
                    
                    Text(formatTimeout(browserManager.settingsManager.tabUnloadTimeout))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                
                HStack {
                    Button("Unload All Inactive Tabs") {
                        browserManager.tabManager.unloadAllInactiveTabs()
                    }
                    .buttonStyle(.bordered)
                    
                    Spacer()
                }
            }
            
            Spacer()
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
    }
}

// MARK: - Placeholder Settings Views

struct SpacesSettingsView: View {
    var body: some View {
        VStack {
            Text("Spaces Settings")
                .font(.title)
            Text("Coming soon...")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
}

struct ProfilesSettingsView: View {
    var body: some View {
        VStack {
            Text("Profiles Settings")
                .font(.title)
            Text("Coming soon...")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
}

struct ShortcutsSettingsView: View {
    var body: some View {
        VStack {
            Text("Shortcuts Settings")
                .font(.title)
            Text("Coming soon...")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
}

struct ExtensionsSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var showingInstallDialog = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if #available(macOS 15.5, *) {
                if let extensionManager = browserManager.extensionManager {
                    // Extension management UI
                    HStack {
                        Text("Installed Extensions")
                            .font(.headline)
                        Spacer()
                        Button("Install Extension...") {
                            browserManager.showExtensionInstallDialog()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    
                    Divider()
                    
                    if extensionManager.installedExtensions.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "puzzlepiece.extension")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text("No Extensions Installed")
                                .font(.title2)
                                .fontWeight(.medium)
                            Text("Install browser extensions to enhance your browsing experience")
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(extensionManager.installedExtensions, id: \.id) { ext in
                                    ExtensionRowView(extension: ext)
                                        .environmentObject(browserManager)
                                }
                            }
                            .padding(.vertical)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundColor(.orange)
                        Text("Extension Manager Unavailable")
                            .font(.title2)
                            .fontWeight(.medium)
                        Text("Extension support is not properly initialized")
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                // Unsupported OS version
                VStack(spacing: 12) {
                    Image(systemName: "puzzlepiece.extension")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Extensions Not Supported")
                        .font(.title2)
                        .fontWeight(.medium)
                    Text("Extensions require macOS 15.5 or later")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .frame(minWidth: 520, minHeight: 360)
    }
}

struct ExtensionRowView: View {
    let `extension`: InstalledExtension
    @EnvironmentObject var browserManager: BrowserManager
    
    var body: some View {
        HStack(spacing: 12) {
            // Extension icon
            Group {
                if let iconPath = `extension`.iconPath,
                   let nsImage = NSImage(contentsOfFile: iconPath) {
                    Image(nsImage: nsImage)
                        .resizable()
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundColor(.blue)
                }
            }
            .frame(width: 32, height: 32)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            
            // Extension info
            VStack(alignment: .leading, spacing: 2) {
                Text(`extension`.name)
                    .font(.headline)
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Text("v\(`extension`.version)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let description = `extension`.description {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            
            Spacer()
            
            // Controls
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { `extension`.isEnabled },
                    set: { isEnabled in
                        if isEnabled {
                            browserManager.enableExtension(`extension`.id)
                        } else {
                            browserManager.disableExtension(`extension`.id)
                        }
                    }
                ))
                .toggleStyle(.switch)
                
                Button("Remove") {
                    browserManager.uninstallExtension(`extension`.id)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct AdvancedSettingsView: View {
    var body: some View {
        VStack {
            Text("Advanced Settings")
                .font(.title)
            Text("Coming soon...")
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
    }
}

// MARK: - Helper Functions
private func formatTimeout(_ seconds: TimeInterval) -> String {
    let minutes = Int(seconds / 60)
    if minutes == 1 {
        return "1 min"
    } else {
        return "\(minutes) mins"
    }
}
