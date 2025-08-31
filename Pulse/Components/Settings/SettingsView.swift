//
//  SettingsView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import AppKit
import SwiftUI

// MARK: - Settings Root
struct SettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var gradientColorManager: GradientColorManager

    var body: some View {
        ZStack {
            // Ambient background using the current space gradient
            SpaceGradientBackgroundView()
                .environmentObject(browserManager)
                .environmentObject(gradientColorManager)
                .overlay(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                // Top bar with title and horizontal tabs
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text("Pulse")
                            .font(.system(size: 24, weight: .semibold))
                        Text("Settings")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 24, weight: .semibold))
                        Spacer()
                    }
                    SettingsTabStrip(selection: $browserManager.settingsManager.currentSettingsTab)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)

                // Content area
                Group {
                    switch browserManager.settingsManager.currentSettingsTab {
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
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 960, minHeight: 640)
    }
}

// MARK: - Horizontal Tab Bar
struct SettingsTabStrip: View {
    @Binding var selection: SettingsTabs

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(SettingsTabs.ordered, id: \.self) { tab in
                    SettingsTabItem(tab: tab, isSelected: tab == selection)
                        .onTapGesture { selection = tab }
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(.ultraThinMaterial)
                    .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
            )
        }
    }
}

struct SettingsTabItem: View {
    let tab: SettingsTabs
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: tab.icon)
                .font(.system(size: 18, weight: .semibold))
                .symbolVariant(isSelected ? .fill : .none)
            Text(tab.name)
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(isSelected ? .primary : .secondary)
        .frame(width: 88, height: 64)
        .background(
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.primary.opacity(0.08))
                        )
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                }
            }
        )
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .animation(.snappy, value: isSelected)
    }
}

// MARK: - General Settings

struct GeneralSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            // Hero card
            SettingsHeroCard()
                .frame(width: 320, height: 420)

            // Right side stacked cards
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionCard(title: "Appearance", subtitle: "Window materials and visual style") {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Background Material")
                            Spacer()
                            Picker("Background Material", selection: $browserManager.settingsManager.currentMaterialRaw) {
                                ForEach(materials, id: \.value.rawValue) { material in
                                    Text(material.name).tag(material.value.rawValue)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 220)
                        }

                        Divider().opacity(0.4)

                        Toggle(isOn: $browserManager.settingsManager.isLiquidGlassEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Liquid Glass")
                                Text("Enable frosted translucency for UI surfaces")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    SettingsSectionCard(title: "Search", subtitle: "Default provider for address bar") {
                        HStack(alignment: .firstTextBaseline) {
                            Text("Search Engine")
                            Spacer()
                            Picker("Search Engine", selection: $browserManager.settingsManager.searchEngine) {
                                ForEach(SearchProvider.allCases) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 220)
                        }
                    }

                    SettingsSectionCard(title: "Performance", subtitle: "Manage memory by unloading inactive tabs") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text("Tab Unload Timeout")
                                Spacer()
                                Picker("Tab Unload Timeout",
                                       selection: Binding<TimeInterval>(
                                           get: {
                                               nearestTimeoutOption(to: browserManager.settingsManager.tabUnloadTimeout)
                                           },
                                           set: { newValue in
                                               browserManager.settingsManager.tabUnloadTimeout = newValue
                                           }
                                       )
                                ) {
                                    ForEach(unloadTimeoutOptions, id: \.self) { value in
                                        Text(formatTimeout(value)).tag(value)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(width: 220)
                                .onAppear {
                                    browserManager.settingsManager.tabUnloadTimeout =
                                        nearestTimeoutOption(to: browserManager.settingsManager.tabUnloadTimeout)
                                }
                            }

                            Text("Automatically unload inactive tabs to reduce memory usage.")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button("Unload All Inactive Tabs") {
                                    browserManager.tabManager.unloadAllInactiveTabs()
                                }
                                .buttonStyle(.bordered)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.trailing, 4)
            }
        }
        .frame(minHeight: 480)
    }
}

// MARK: - Placeholder Settings Views

struct SpacesSettingsView: View {
    var body: some View {
        SettingsPlaceholderView(title: "Spaces", subtitle: "Customize workspaces and groups", icon: "rectangle.3.group")
    }
}

struct ProfilesSettingsView: View {
    var body: some View {
        SettingsPlaceholderView(title: "Profiles", subtitle: "Switch between browsing personas", icon: "person.crop.circle")
    }
}

struct ShortcutsSettingsView: View {
    var body: some View {
        SettingsPlaceholderView(title: "Shortcuts", subtitle: "Keyboard and quick actions", icon: "keyboard")
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
        SettingsPlaceholderView(title: "Advanced", subtitle: "Power features and diagnostics", icon: "wrench.and.screwdriver")
    }
}

// MARK: - Helper Functions
private let unloadTimeoutOptions: [TimeInterval] = [
    300,    // 5 min
    600,    // 10 min
    900,    // 15 min
    1800,   // 30 min
    2700,   // 45 min
    3600,   // 1 hr
    7200,   // 2 hr
    14400,  // 4 hr
    28800,  // 8 hr
    43200,  // 12 hr
    86400   // 24 hr
]

private func nearestTimeoutOption(to value: TimeInterval) -> TimeInterval {
    guard let nearest = unloadTimeoutOptions.min(by: { abs($0 - value) < abs($1 - value) }) else {
        return value
    }
    return nearest
}

// MARK: - Styled Components
struct SettingsSectionCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var content: Content

    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
                .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
        )
    }
}

struct SettingsHeroCard: View {
    @EnvironmentObject var gradientColorManager: GradientColorManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(.ultraThinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
                BarycentricGradientView(gradient: gradientColorManager.displayGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(12)
            }
            .frame(height: 220)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pulse")
                    .font(.system(size: 24, weight: .bold))
                Text("BROWSER")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 12) {
                Image(systemName: "square.and.arrow.up")
                Image(systemName: "doc.on.doc")
                Image(systemName: "gearshape")
            }
            .foregroundStyle(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.thinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
                .shadow(color: Color.black.opacity(0.1), radius: 14, y: 6)
        )
    }
}

struct SettingsPlaceholderView: View {
    let title: String
    let subtitle: String
    let icon: String

    var body: some View {
        VStack(alignment: .center, spacing: 16) {
            HStack { Spacer() }
            VStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text(title).font(.title2).fontWeight(.semibold)
                Text(subtitle).foregroundStyle(.secondary)
            }
            .padding(32)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(.thinMaterial)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(Color.primary.opacity(0.08))
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 12, y: 6)
            )
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 20)
    }
}

private func formatTimeout(_ seconds: TimeInterval) -> String {
    if seconds < 3600 { // under 1 hour
        let minutes = Int(seconds / 60)
        return minutes == 1 ? "1 min" : "\(minutes) mins"
    } else if seconds < 86400 { // under 24 hours
        let hours = seconds / 3600.0
        let rounded = hours.rounded()
        let isWhole = abs(hours - rounded) < 0.01
        if isWhole {
            let wholeHours = Int(rounded)
            return wholeHours == 1 ? "1 hr" : "\(wholeHours) hrs"
        } else {
            // Show one decimal for non-integer hours
            return String(format: "%.1f hrs", hours)
        }
    } else {
        // 24 hours (cap in UI)
        return "24 hr"
    }
}
