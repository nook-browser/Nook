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
    @State private var pendingRemoval: InstalledExtension?
    @State private var consent: PendingConsent?

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

            Section("Installed") {
                if extensionManager.installedExtensions.isEmpty {
                    emptyState
                } else {
                    ForEach(installed, id: \.id) { ext in
                        let update = extensionManager.safariUpdate(for: ext)
                        let alternative = extensionManager.safariAlternative(to: ext)
                        ExtensionRowView(
                            extension: ext,
                            appName: ext.source.appName
                                ?? extensionManager.safariExtension(id: ext.id)?.appPath.lastPathComponent,
                            hasOptionsPage: extensionManager.hasOptionsPage(ext.id),
                            onEnabledChange: { isEnabled in
                                if isEnabled {
                                    extensionManager.enableExtension(ext.id)
                                } else {
                                    extensionManager.disableExtension(ext.id)
                                }
                            },
                            onPrivateBrowsingChange: { extensionManager.setAllowsPrivateBrowsing(ext.id, allowed: $0) },
                            onUpdate: update.map { info in { install(info) } },
                            onSwitch: alternative.map { info in { install(info) } },
                            onOpenOptions: { extensionManager.openOptionsPage(ext.id) },
                            onRemove: { pendingRemoval = ext }
                        )
                    }
                }
            }

            Section {
                if extensionManager.safariExtensions == nil {
                    HStack(spacing: NookDesign.Spacing.md) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Scanning…")
                            .foregroundStyle(.secondary)
                    }
                }
                ForEach(extensionManager.uninstalledSafariExtensions) { info in
                    AddExtensionRow(
                        title: info.name,
                        subtitle: "Safari · \(info.appPath.lastPathComponent)",
                        action: "Install",
                        icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: info.appPath.path))
                                .resizable()
                        },
                        onAction: { install(info) }
                    )
                }
                AddExtensionRow(
                    title: "Chrome Web Store",
                    subtitle: "Install from an extension's page in the store",
                    action: "Open",
                    actionSymbol: "arrow.up.right",
                    icon: { SymbolTile(systemName: "storefront") },
                    onAction: openWebStore
                )
                AddExtensionRow(
                    title: "From a File",
                    subtitle: "A folder, or a ZIP, CRX or XPI file",
                    action: "Choose…",
                    icon: { SymbolTile(systemName: "doc.zipper") },
                    onAction: { extensionManager.showExtensionInstallDialog(presenter: presentConsent) }
                )
            } header: {
                Text("Add Extensions")
            } footer: {
                Text("Safari extensions come with Mac apps. Install the app and its extension shows up here.")
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .alert(
            Text("Remove \(pendingRemoval?.name ?? "")?"),
            isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { ext in
            Button("Remove", role: .destructive) {
                extensionManager.uninstallExtension(ext.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its data in Nook, such as sign-ins and settings, is deleted.")
        }
        .sheet(item: $consent) { pending in
            ExtensionPermissionView(
                consent: pending.request,
                onGrant: { answer(pending, granted: true) },
                onDeny: { answer(pending, granted: false) }
            )
            .frame(width: NookDesign.Size.dialogMaxWidth)
        }
        .task { await extensionManager.refreshSafariExtensions() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await extensionManager.refreshSafariExtensions() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: NookDesign.Spacing.lg) {
            Image(systemName: "puzzlepiece.extension")
                .font(NookDesign.Font.hero)
                .foregroundStyle(.secondary)
            Text("No Extensions Installed")
                .font(NookDesign.Font.titleLarge)
            Text("Add extensions from the Chrome Web Store or from apps on this Mac.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Derived State

    private var installed: [InstalledExtension] {
        extensionManager.installedExtensions.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Actions

    private func install(_ info: ExtensionManager.SafariExtensionInfo) {
        extensionManager.installSafariExtension(info, presenter: presentConsent) { result in
            guard case .failure(let error) = result else { return }
            if case .cancelled = error { return }
            extensionManager.showErrorAlert(error)
        }
    }

    private func presentConsent(_ request: InstallConsent) async -> Bool {
        await withCheckedContinuation { continuation in
            consent = PendingConsent(
                request: request,
                decide: ResumeOnce(fallback: false) { continuation.resume(returning: $0) }
            )
        }
    }

    private func answer(_ pending: PendingConsent, granted: Bool) {
        pending.decide(granted)
        consent = nil
    }

    private func openWebStore() {
        guard let window = browserManager.openBrowserWindow() else { return }
        browserManager.tabs.open(url: ExtensionStore.chromeWebStoreURL, in: window, placement: .newTab)
    }
}

private struct PendingConsent: Identifiable {
    let request: InstallConsent
    let decide: ResumeOnce<Bool>

    var id: UUID { request.id }
}

// MARK: - Add Extension Row

private struct AddExtensionRow<Icon: View>: View {
    let title: String
    let subtitle: String
    let action: String
    var actionSymbol: String?
    @ViewBuilder let icon: () -> Icon
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: NookDesign.Spacing.lg) {
            icon()
                .frame(width: NookDesign.Size.settingsIcon, height: NookDesign.Size.settingsIcon)

            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(title)
                    .font(NookDesign.Font.label)
                    .lineLimit(1)
                Text(subtitle)
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onAction) {
                HStack(spacing: NookDesign.Spacing.xs) {
                    Text(action)
                    if let actionSymbol {
                        Image(systemName: actionSymbol)
                    }
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

private struct SymbolTile: View {
    let systemName: String

    var body: some View {
        Image(systemName: systemName)
            .font(NookDesign.Font.title)
            .foregroundStyle(.secondary)
            .extensionIconTile()
    }
}

private extension View {
    func extensionIconTile() -> some View {
        frame(width: NookDesign.Size.settingsIcon, height: NookDesign.Size.settingsIcon)
            .background(NookDesign.Surface.raised)
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
    }
}

// MARK: - Installed Extension Row

private struct ExtensionRowView: View {
    let `extension`: InstalledExtension
    let appName: String?
    let hasOptionsPage: Bool
    let onEnabledChange: (Bool) -> Void
    let onPrivateBrowsingChange: (Bool) -> Void
    let onUpdate: (() -> Void)?
    let onSwitch: (() -> Void)?
    let onOpenOptions: () -> Void
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: NookDesign.Spacing.lg) {
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
            .extensionIconTile()
            .opacity(`extension`.isEnabled ? 1 : NookDesign.Surface.unloadedOpacity)

            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Group {
                    Text(`extension`.name)
                        .font(NookDesign.Font.label)
                        .foregroundStyle(`extension`.isEnabled ? .primary : .secondary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .help(`extension`.description ?? "")

                Toggle(
                    "Allow in Private Browsing",
                    isOn: Binding(get: { `extension`.allowsPrivateBrowsing }, set: onPrivateBrowsingChange)
                )
                .toggleStyle(.checkbox)
                .font(NookDesign.Font.caption)
            }

            Spacer()

            if let onUpdate {
                Button("Update", action: onUpdate)
                    .buttonStyle(.bordered)
            }
            if let onSwitch {
                Button("Switch…", action: onSwitch)
                    .buttonStyle(.bordered)
            }

            Toggle(
                "Enabled",
                isOn: Binding(get: { `extension`.isEnabled }, set: onEnabledChange)
            )
            .labelsHidden()

            Menu {
                if hasOptionsPage {
                    Button("Settings…", systemImage: "gearshape", action: onOpenOptions)
                    Divider()
                }
                Button("Remove…", systemImage: "trash", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private var subtitle: String {
        [
            `extension`.source.name,
            appName,
            `extension`.version,
            onUpdate != nil ? "update available" : nil,
            onSwitch != nil ? "Safari version available" : nil,
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
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
