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

struct ExtensionsSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @ObservedObject var extensionManager: ExtensionManager
    @State private var safariExtensions: [ExtensionManager.SafariExtensionInfo] = []
    @State private var isScanningSafari = false
    @State private var showSafariSection = false
    @State private var searchText = ""
    @State private var selectedExtension: InstalledExtension?

    private var filteredExtensions: [InstalledExtension] {
        guard !searchText.isEmpty else { return extensionManager.installedExtensions }
        return extensionManager.installedExtensions.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxxl) {
                installedExtensionsSection
                safariExtensionsSection
            }
            .padding(NookDesign.Spacing.xxxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .sheet(isPresented: Binding(
            get: { selectedExtension != nil },
            set: { if !$0 { selectedExtension = nil } }
        )) {
            if let selectedExtension {
                ExtensionDetailsView(extension: selectedExtension)
            }
        }
        .onAppear {
            if safariExtensions.isEmpty && !isScanningSafari {
                scanForSafariExtensions()
            }
        }
    }

    private var installedExtensionsSection: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.xl) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                    Text("Installed Extensions")
                        .font(NookDesign.Font.heading)
                    Text("\(extensionManager.installedExtensions.count) installed")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Install Extension…") {
                    browserManager.showExtensionInstallDialog()
                }
                .buttonStyle(.borderedProminent)
            }

            if !extensionManager.installedExtensions.isEmpty {
                TextField("Search extensions", text: $searchText, prompt: Text("Search extensions"))
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search installed extensions")
            }

            if extensionManager.installedExtensions.isEmpty {
                ContentUnavailableView(
                    "No Extensions Installed",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Install browser extensions to enhance your browsing experience.")
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, NookDesign.Spacing.xxxl)
            } else if filteredExtensions.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, NookDesign.Spacing.xxxl)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: NookDesign.Spacing.lg)],
                    alignment: .leading,
                    spacing: NookDesign.Spacing.lg
                ) {
                    ForEach(filteredExtensions, id: \.id) { ext in
                        ExtensionCardView(
                            extension: ext,
                            onDetails: { selectedExtension = ext },
                            onRemove: { browserManager.uninstallExtension(ext.id) },
                            onToggle: { isEnabled in
                                if isEnabled {
                                    browserManager.enableExtension(ext.id)
                                } else {
                                    browserManager.disableExtension(ext.id)
                                }
                            }
                        )
                    }
                }
            }
        }
    }

    private var safariExtensionsSection: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.lg) {
            HStack {
                VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                    Text("Safari Extensions")
                        .font(NookDesign.Font.heading)
                    Text("Install extensions already available on this Mac.")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isScanningSafari {
                    ProgressView("Scanning…")
                        .controlSize(.small)
                } else {
                    Button("Scan Again") {
                        scanForSafariExtensions()
                    }
                    .buttonStyle(.bordered)
                }
            }

            if showSafariSection {
                if safariExtensions.isEmpty && !isScanningSafari {
                    Text("No Safari Web Extensions found on this Mac.")
                        .font(NookDesign.Font.bodyRegular)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(NookDesign.Spacing.xl)
                        .background(NookDesign.Surface.fill)
                        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                } else if !safariExtensions.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(safariExtensions) { ext in
                            SafariExtensionRowView(
                                info: ext,
                                isAlreadyInstalled: extensionManager.installedExtensions.contains(where: {
                                    $0.name == ext.name
                                }),
                                onInstall: { installSafariExtension(ext) }
                            )
                            .padding(.horizontal, NookDesign.Spacing.xl)
                            .padding(.vertical, NookDesign.Spacing.lg)

                            if ext.id != safariExtensions.last?.id {
                                Divider()
                                    .padding(.leading, NookDesign.Spacing.xl)
                            }
                        }
                    }
                    .background(NookDesign.Surface.fill)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                }
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
            case .success:
                safariExtensions.removeAll { $0.id == info.id }
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
                .frame(width: NookDesign.Size.settingsIcon, height: NookDesign.Size.settingsIcon)

            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(info.name)
                    .font(NookDesign.Font.label)
                    .lineLimit(1)
                Text(info.appPath.lastPathComponent)
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: NookDesign.Spacing.md)

            if isAlreadyInstalled {
                Text("Installed")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            } else {
                Button("Install", action: onInstall)
                    .buttonStyle(.bordered)
            }
        }
    }
}

// MARK: - Installed Extension Card

private struct ExtensionCardView: View {
    let `extension`: InstalledExtension
    let onDetails: () -> Void
    let onRemove: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: NookDesign.Spacing.xl) {
            HStack(alignment: .top, spacing: NookDesign.Spacing.lg) {
                extensionIcon
                    .frame(width: 40, height: 40)
                    .background(NookDesign.Surface.raised)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))

                VStack(alignment: .leading, spacing: NookDesign.Spacing.xs) {
                    Text(`extension`.name)
                        .font(NookDesign.Font.label)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(`extension`.description ?? "Version \(`extension`.version)")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)

            HStack(spacing: NookDesign.Spacing.sm) {
                Button("Details", action: onDetails)
                    .buttonStyle(.bordered)

                Button("Remove", role: .destructive, action: onRemove)
                    .buttonStyle(.bordered)

                Spacer(minLength: 0)

                Toggle("Enabled", isOn: Binding(
                    get: { `extension`.isEnabled },
                    set: onToggle
                ))
                .labelsHidden()
                .accessibilityLabel("Enable \(`extension`.name)")
            }
        }
        .padding(NookDesign.Spacing.xl)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NookDesign.Surface.fill)
        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .overlay {
            NookDesign.Radius.shape(NookDesign.Radius.md)
                .strokeBorder(NookDesign.Surface.hairline, lineWidth: 1)
        }
    }

    @ViewBuilder
    private var extensionIcon: some View {
        if let iconPath = `extension`.iconPath,
            let nsImage = NSImage(contentsOfFile: iconPath)
        {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFit()
                .padding(NookDesign.Spacing.xs)
        } else {
            Image(systemName: "puzzlepiece.extension")
                .font(NookDesign.Font.title)
                .foregroundStyle(.blue)
        }
    }
}

// MARK: - Extension Details

private struct ExtensionDetailsView: View {
    let `extension`: InstalledExtension
    @Environment(\.dismiss) private var dismiss

    private var permissions: [String] {
        (`extension`.manifest["permissions"] as? [String] ?? []).sorted()
    }

    private var hostPermissions: [String] {
        (`extension`.manifest["host_permissions"] as? [String] ?? []).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Extension") {
                    LabeledContent("Name", value: `extension`.name)
                    LabeledContent("Version", value: `extension`.version)
                    LabeledContent("Extension ID", value: `extension`.id)
                    LabeledContent("Manifest version", value: String(`extension`.manifestVersion))
                }

                Section("Permissions") {
                    if permissions.isEmpty && hostPermissions.isEmpty {
                        Text("No special permissions declared.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(permissions, id: \.self) { permission in
                            Label(permission, systemImage: "key.horizontal")
                        }
                        ForEach(hostPermissions, id: \.self) { host in
                            Label(host, systemImage: "globe")
                                .textSelection(.enabled)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Extension Details")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 400)
    }
}
