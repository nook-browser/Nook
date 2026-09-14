//
//  Extensions.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import AppKit
import SwiftUI

struct ExtensionsSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @ObservedObject var extensionManager: ExtensionManager
    @State private var showingInstallDialog = false
    @State private var safariExtensions: [ExtensionManager.SafariExtensionInfo] = []
    @State private var isScanningSafari = false
    @State private var showSafariSection = false

    var body: some View {
        Form {
            Section {
                Button("Install Extension...") {
                    browserManager.showExtensionInstallDialog()
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
                        ExtensionRowView(extension: ext)
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
                                isAlreadyInstalled: extensionManager.installedExtensions.contains(where: {
                                    $0.name == ext.name
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
                                browserManager.enableExtension(`extension`.id)
                            } else {
                                browserManager.disableExtension(`extension`.id)
                            }
                        }
                    )
                )
                .labelsHidden()

                Button("Remove") {
                    browserManager.uninstallExtension(`extension`.id)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
            }
        }
    }
}
