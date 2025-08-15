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
                    ForEach([SettingsTabs.general, .privacy, .spaces, .profiles, .shortcuts, .advanced], id: \.self) { tab in
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
