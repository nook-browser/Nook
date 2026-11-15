// Licensed under GPL-3.0. See LICENSE.
//
//  Extensions.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import AppKit
import SwiftUI
import NookDesign
import NookWeb
import NookSettings

struct ExtensionsSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @ObservedObject var extensionManager: ExtensionManager
    /// The extension sets in use and the one shown, for the picker once there is more than one.
    var sets: [ExtensionSetChoice] = []
    var shownSet: Binding<UUID>?
    @State private var showingInstallDialog = false
    @State private var safariExtensions: [ExtensionManager.SafariExtensionInfo] = []
    @State private var isScanningSafari = false
    @State private var showSafariSection = false

    var body: some View {
        Form {
            if sets.count > 1, let shownSet {
                Section {
                    Picker("Profiles", selection: shownSet) {
                        ForEach(sets, id: \.set) { choice in
                            Text(choice.members.compactMap { id in tabs.profiles.first { $0.id == id }?.name }.joined(separator: ", "))
                                .tag(choice.set)
                        }
                    }
                }
            }

            Section {
                Button("Install Extension...") {
                    extensionManager.showExtensionInstallDialog()
                }
                .buttonStyle(.borderedProminent)
            }

            if extensionManager.installedExtensions.isEmpty && !showSafariSection {
                Section {
                    VStack(spacing: NookDesign.Spacing.lg) {
                        Image(systemName: "puzzlepiece.extension")
                            .font(NookDesign.Font.hero)
                            .foregroundStyle(.secondary)
                        Text("No Extensions Installed")
                            .font(NookDesign.Font.titleLarge)
                        Text("Install browser extensions to enhance your browsing experience")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                Section("Installed Extensions") {
                    ForEach(extensionManager.installedExtensions, id: \.id) { ext in
                        ExtensionRowView(extension: ext, extensionManager: extensionManager)
                            .environmentObject(browserManager)
                    }
                }
            }

            Section {
                if isScanningSafari {
                    HStack(spacing: NookDesign.Spacing.md) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning...")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button("Scan for Safari Extensions") {
                        scanForSafariExtensions()
                    }
                }

                if showSafariSection {
                    if safariExtensions.isEmpty {
                        Text("No Safari Web Extensions found on this Mac.")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(safariExtensions) { ext in
                            SafariExtensionRowView(
                                info: ext,
                                // A copy from before stable IDs can be installed again from here, which moves it to its real id.
                                isAlreadyInstalled: extensionManager.installedExtensions.contains(where: {
                                    $0.id == ext.id || ($0.name == ext.name && UUID(uuidString: $0.id) == nil)
                                }),
                                onInstall: {
                                    installSafariExtension(ext)
                                }
                            )
                        }
                    }
                }
            } header: {
                Text("Safari Extensions")
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if safariExtensions.isEmpty && !isScanningSafari {
                scanForSafariExtensions()
            }
        }
    }

    private func scanForSafariExtensions() {
        isScanningSafari = true
        showSafariSection = true
        Task {
            let found = await extensionManager.discoverSafariExtensions()
            await MainActor.run {
                safariExtensions = found
                isScanningSafari = false
            }
        }
    }

    private func installSafariExtension(_ info: ExtensionManager.SafariExtensionInfo) {
        extensionManager.installSafariExtension(info) { result in
            switch result {
            case .success(let ext):
                // Remove from available list since it's now installed
                safariExtensions.removeAll { $0.id == info.id }
                _ = ext // suppress unused warning
            case .failure(.cancelled):
                break
            case .failure(let error):
                let alert = NSAlert()
                alert.messageText = "Failed to Install Safari Extension"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.addButton(withTitle: "OK")
                alert.runModal()
            }
        }
    }
}

// MARK: - Safari Extension Row

private struct SafariExtensionRowView: View {
    let info: ExtensionManager.SafariExtensionInfo
    let isAlreadyInstalled: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: NookDesign.Spacing.lg) {
            Image(systemName: "safari")
                .font(NookDesign.Font.titleLarge)
                .foregroundStyle(.blue)
                .frame(
                    width: NookDesign.Size.settingsIcon,
                    height: NookDesign.Size.settingsIcon
                )

            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(info.name)
                    .font(NookDesign.Font.label)
                    .lineLimit(1)
                Text(info.appPath.lastPathComponent)
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isAlreadyInstalled {
                Text("Installed")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Install") {
                    onInstall()
                }
                .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Installed Extension Row

private struct ExtensionRowView: View {
    let `extension`: InstalledExtension
    /// The extension set this row's extension is installed in.
    let extensionManager: ExtensionManager
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        HStack(spacing: NookDesign.Spacing.lg) {
            // Extension icon
            Group {
                if let iconPath = `extension`.iconPath,
                    let nsImage = NSImage(contentsOfFile: iconPath)
                {
                    Image(nsImage: nsImage)
                        .resizable()
                } else {
                    Image(systemName: "puzzlepiece.extension")
                        .foregroundStyle(.blue)
                }
            }
            .frame(
                width: NookDesign.Size.settingsIcon,
                height: NookDesign.Size.settingsIcon
            )
            .background(NookDesign.Surface.raised)
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))

            // Extension info
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(`extension`.name)
                    .font(NookDesign.Font.label)
                    .lineLimit(1)

                HStack(spacing: NookDesign.Spacing.md) {
                    Text("v\(`extension`.version)")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)

                    if let description = `extension`.description {
                        Text("•")
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                        Text(description)
                            .font(NookDesign.Font.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Toggle(
                    "Allow in Private Browsing",
                    isOn: Binding(
                        get: { `extension`.allowsPrivateBrowsing },
                        set: { extensionManager.setAllowsPrivateBrowsing(`extension`.id, allowed: $0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(NookDesign.Font.caption)
            }

            Spacer()

            // Controls
            HStack(spacing: NookDesign.Spacing.md) {
                Toggle(
                    "Enabled",
                    isOn: Binding(
                        get: { `extension`.isEnabled },
                        set: { isEnabled in
                            if isEnabled {
                                extensionManager.enableExtension(`extension`.id)
                            } else {
                                extensionManager.disableExtension(`extension`.id)
                            }
                        }
                    )
                )
                .labelsHidden()

                Button("Remove") {
                    extensionManager.uninstallExtension(`extension`.id)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
        }
    }
}

/// Settings > Extensions for one extension set, the active window's until another is picked.
struct ExtensionSetsSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(\.nookSettings) private var settings
    @State private var picked: UUID?

    var body: some View {
        let registry = ExtensionSetRegistry.shared
        let sets = settings.extensionSets.choices(profiles: tabs.profiles.map(\.id), defaultSet: registry.defaultSetID)
        let active = browserManager.windowRegistry?.activeWindow.map(registry.setID(for:))
        // Only a set a profile uses is shown: asking for any other id would create it.
        let set = [picked, active].compactMap { $0 }.first { id in sets.contains { $0.set == id } }
            ?? sets.first?.set ?? registry.defaultSetID
        ExtensionsSettingsView(
            extensionManager: registry.manager(forSet: set),
            sets: sets,
            shownSet: Binding(get: { set }, set: { picked = $0 })
        )
        .id(set)
    }
}
