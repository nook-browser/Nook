//
//  SettingsView.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import AppKit
import SwiftUI

// MARK: - Profiles Settings

struct ProfilesSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var profileToRename: Profile? = nil
    @State private var profileToDelete: Profile? = nil

    var body: some View {
        Form {
            Section("Profiles") {
                HStack {
                    Button(action: showCreateDialog) {
                        Label("Create Profile", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                }

                if browserManager.profileManager.profiles.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "person.crop.circle")
                            .foregroundColor(.secondary)
                        Text("No profiles yet. Create one to get started.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(
                        browserManager.profileManager.profiles,
                        id: \.id
                    ) { profile in
                        ProfileRowView(
                            profile: profile,
                            isCurrent: browserManager.currentProfile?.id == profile.id,
                            spacesCount: spacesCount(for: profile),
                            tabsCount: tabsCount(for: profile),
                            dataSizeDescription: "Shared store",
                            pinnedCount: pinnedCount(for: profile),
                            onMakeCurrent: {
                                Task {
                                    await browserManager.switchToProfile(profile)
                                }
                            },
                            onRename: { startRename(profile) },
                            onDelete: { startDelete(profile) },
                            onManageData: {
                                showDataManagement(for: profile)
                            }
                        )
                    }
                }

                MigrationControls()
                    .environmentObject(browserManager)
            }

            Section("Space Assignments") {
                HStack(spacing: 8) {
                    Button(action: assignAllSpacesToCurrentProfile) {
                        Label("Assign All to Current Profile", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)

                    Button(action: resetAllSpaceAssignments) {
                        Label("Reset to Default Profile", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.bordered)

                    Spacer()
                }

                if browserManager.tabManager.spaces.isEmpty {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.3.group")
                            .foregroundStyle(.secondary)
                        Text("No spaces yet. Create a space to assign profiles.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(browserManager.tabManager.spaces, id: \.id) { space in
                        SpaceAssignmentRowView(space: space)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers
    private func spacesCount(for profile: Profile) -> Int {
        browserManager.tabManager.spaces.filter { $0.profileId == profile.id }
            .count
    }

    private func tabsCount(for profile: Profile) -> Int {
        let spaceIds = Set(
            browserManager.tabManager.spaces.filter {
                $0.profileId == profile.id
            }.map { $0.id }
        )
        return browserManager.tabManager.allTabs().filter { tab in
            if let sid = tab.spaceId { return spaceIds.contains(sid) }
            return false
        }.count
    }

    private func pinnedCount(for profile: Profile) -> Int {
        // Count space‑pinned tabs in spaces assigned to this profile
        let spaceIds = browserManager.tabManager.spaces
            .filter { $0.profileId == profile.id }
            .map { $0.id }
        var total = 0
        for sid in spaceIds {
            total += browserManager.tabManager.spacePinnedTabs(for: sid).count
        }
        return total
    }

    // MARK: - Actions
    private func showCreateDialog() {
        browserManager.dialogManager.showDialog(
            ProfileCreationDialog(
                isNameAvailable: { proposed in
                    let trimmed = proposed.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    guard !trimmed.isEmpty else { return false }
                    return !browserManager.profileManager.profiles.contains {
                        $0.name.caseInsensitiveCompare(trimmed) == .orderedSame
                    }
                },
                onCreate: { name, icon in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let safeIcon = icon.isEmpty ? "person.crop.circle" : icon
                    let created = browserManager.profileManager.createProfile(
                        name: trimmed,
                        icon: safeIcon
                    )
                    Task { await browserManager.switchToProfile(created) }
                    browserManager.dialogManager.closeDialog()
                },
                onCancel: {
                    browserManager.dialogManager.closeDialog()
                }
            )
        )
    }

    private func startRename(_ profile: Profile) {
        profileToRename = profile
        browserManager.dialogManager.showDialog(
            ProfileRenameDialog(
                originalProfile: profile,
                isNameAvailable: { proposed in
                    let trimmed = proposed.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    return !browserManager.profileManager.profiles.contains {
                        $0.id != profile.id
                            && $0.name.caseInsensitiveCompare(trimmed)
                                == .orderedSame
                    }
                },
                onSave: { newName, newIcon in
                    guard let target = profileToRename else {
                        browserManager.dialogManager.closeDialog()
                        return
                    }
                    target.name = newName
                    target.icon = newIcon
                    browserManager.profileManager.persistProfiles()
                    browserManager.dialogManager.closeDialog()
                },
                onCancel: {
                    browserManager.dialogManager.closeDialog()
                }
            )
        )
    }

    private func startDelete(_ profile: Profile) {
        let isLast = browserManager.profileManager.profiles.count <= 1
        let stats = (
            spaces: spacesCount(for: profile),
            tabs: tabsCount(for: profile)
        )
        let dialog = ProfileDeleteConfirmationDialog(
            profileName: profile.name,
            profileIcon: profile.icon,
            spacesCount: stats.spaces,
            tabsCount: stats.tabs,
            isLastProfile: isLast,
            onDelete: {
                guard browserManager.profileManager.profiles.count > 1 else {
                    browserManager.dialogManager.closeDialog()
                    return
                }
                browserManager.deleteProfile(profile)
            },
            onCancel: { browserManager.dialogManager.closeDialog() }
        )
        browserManager.dialogManager.showDialog(dialog)
    }

    private func showDataManagement(for profile: Profile) {
        browserManager.dialogManager.showDialog {
            StandardDialog(
                header: {
                    DialogHeader(
                        icon: "internaldrive",
                        title: "Manage Data",
                        subtitle: "Profile data management"
                    )
                },
                content: {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Each profile maintains its own isolated website data store.")
                        Text("Privacy tools are available under the Privacy tab.")
                            .foregroundStyle(.secondary)
                    }
                },
                footer: {
                    DialogFooter(rightButtons: [
                        DialogButton(text: "Close", variant: .primary) {
                            browserManager.dialogManager.closeDialog()
                        }
                    ])
                }
            )
        }
    }

    private func showExportPlaceholder() {
        browserManager.dialogManager.showDialog {
            StandardDialog(
                header: {
                    DialogHeader(
                        icon: "square.and.arrow.up",
                        title: "Export Profile",
                        subtitle: "Coming soon"
                    )
                },
                content: {
                    Text("Profile export is not yet implemented.")
                },
                footer: {
                    DialogFooter(rightButtons: [
                        DialogButton(text: "OK", variant: .primary) {
                            browserManager.dialogManager.closeDialog()
                        }
                    ])
                }
            )
        }
    }

    private func showImportPlaceholder() {
        browserManager.dialogManager.showDialog {
            StandardDialog(
                header: {
                    DialogHeader(
                        icon: "square.and.arrow.down",
                        title: "Import Profile",
                        subtitle: "Coming soon"
                    )
                },
                content: {
                    Text("Profile import is not yet implemented.")
                },
                footer: {
                    DialogFooter(rightButtons: [
                        DialogButton(text: "OK", variant: .primary) {
                            browserManager.dialogManager.closeDialog()
                        }
                    ])
                }
            )
        }
    }

    // MARK: - Space assignment helpers and views
    private func assign(space: Space, to id: UUID) {
        browserManager.tabManager.assign(spaceId: space.id, toProfile: id)
    }

    private func assignAllSpacesToCurrentProfile() {
        guard let pid = browserManager.currentProfile?.id else { return }
        for sp in browserManager.tabManager.spaces {
            browserManager.tabManager.assign(spaceId: sp.id, toProfile: pid)
        }
    }

    private func resetAllSpaceAssignments() {
        guard
            let defaultProfileId = browserManager.profileManager.profiles.first?
                .id
        else { return }
        for sp in browserManager.tabManager.spaces {
            browserManager.tabManager.assign(
                spaceId: sp.id,
                toProfile: defaultProfileId
            )
        }
    }

    private func resolvedProfile(for id: UUID?) -> Profile? {
        guard let id else { return nil }
        return browserManager.profileManager.profiles.first(where: {
            $0.id == id
        })
    }

    private struct SpaceAssignmentRowView: View {
        @EnvironmentObject var browserManager: BrowserManager
        let space: Space
        @State private var showDeleteConfirmation = false

        private var canDelete: Bool {
            browserManager.tabManager.spaces.count > 1
        }

        var body: some View {
            HStack(spacing: 12) {
                // Space icon
                Group {
                    if isEmoji(space.icon) {
                        Text(space.icon)
                            .font(.system(size: 14))
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: space.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(width: 24, height: 24)
                    }
                }
                .background(Color(.controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(space.name)
                        .font(.subheadline)
                    HStack(spacing: 6) {
                        SpaceProfileBadge(space: space, size: .compact)
                            .environmentObject(browserManager)
                        Text(currentProfileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Quick action to set to current profile
                if let current = browserManager.currentProfile {
                    Button {
                        assign(space: space, to: current.id)
                    } label: {
                        Label(
                            "Assign to \(current.name)",
                            systemImage: "checkmark.circle"
                        )
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Profile picker menu
                Menu {
                    // Use compact picker inside menu
                    let binding = Binding<UUID>(
                        get: {
                            space.profileId ?? browserManager.profileManager
                                .profiles.first?.id ?? UUID()
                        },
                        set: { newId in assign(space: space, to: newId) }
                    )
                    Text("Current: \(currentProfileName)")
                        .foregroundStyle(.secondary)
                    Divider()
                    ProfilePickerView(
                        selectedProfileId: binding,
                        onSelect: { _ in },
                        compact: true
                    )
                    .environmentObject(browserManager)
                } label: {
                    Label("Change", systemImage: "person.crop.circle")
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.borderlessButton)

                // Delete space
                if canDelete {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.red.opacity(0.7))
                    .help("Delete Space")
                }
            }
            .padding(10)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .alert("Delete \"\(space.name)\"?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    browserManager.tabManager.removeSpace(space.id)
                }
            } message: {
                let tabCount = (browserManager.tabManager.tabsBySpace[space.id]?.count ?? 0)
                Text("This will close \(tabCount) tab\(tabCount == 1 ? "" : "s") in this space.")
            }
        }

        private var currentProfileName: String {
            if let pid = space.profileId,
                let p = browserManager.profileManager.profiles.first(where: {
                    $0.id == pid
                })
            {
                return p.name
            }
            // If no profile assigned, show the default profile name
            return browserManager.profileManager.profiles.first?.name
                ?? "Default"
        }

        private func assign(space: Space, to id: UUID) {
            browserManager.tabManager.assign(spaceId: space.id, toProfile: id)
        }

        private func isEmoji(_ string: String) -> Bool {
            return string.unicodeScalars.contains { scalar in
                (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF)
                    || (scalar.value >= 0x2600 && scalar.value <= 0x26FF)
                    || (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
            }
        }
    }
}

// MARK: - Migration Controls
private struct MigrationControls: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var legacySummary: BrowserManager.LegacyDataSummary? = nil
    @State private var lastDetectionDate: Date? = nil
    @State private var showingCancelConfirm: Bool = false

    private var hasLegacyData: Bool {
        (legacySummary?.hasAny) ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button(action: {
                    Task { @MainActor in
                        let summary =
                            await browserManager.detectLegacySharedData()
                        legacySummary = summary
                        lastDetectionDate = Date()
                    }
                }) {
                    Label("Detect Legacy Data", systemImage: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Detect Legacy Data")

                Button(action: {
                    browserManager.startMigrationToCurrentProfile()
                }) {
                    Label(
                        "Migrate to Current Profile",
                        systemImage: "arrow.down.to.line"
                    )
                }
                .buttonStyle(.bordered)
                .disabled(browserManager.isMigrationInProgress == true)
                .accessibilityLabel("Migrate shared data to current profile")

                Button(action: {
                    Task { @MainActor in
                        await browserManager.clearSharedDataAfterMigration()
                        legacySummary = nil
                    }
                }) {
                    Label("Start Fresh", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .accessibilityLabel(
                    "Clear shared website data without migration"
                )

                Spacer()
            }

            if let summary = legacySummary {
                HStack(spacing: 8) {
                    Image(
                        systemName: summary.hasAny
                            ? "exclamationmark.circle" : "checkmark.circle"
                    )
                    .foregroundStyle(summary.hasAny ? .orange : .green)
                    Text(
                        summary.hasAny
                            ? "Legacy data detected — \(summary.estimatedDescription)"
                            : "No legacy shared data found"
                    )
                    .font(.subheadline)
                    if let dt = lastDetectionDate {
                        Text(
                            "• \(DateFormatter.localizedString(from: dt, dateStyle: .none, timeStyle: .short))"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text(
                        "Scan for cookies and site data in the shared store and migrate them into \(browserManager.currentProfile?.name ?? "current profile")."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            if browserManager.isMigrationInProgress,
                let mp = browserManager.migrationProgress
            {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(mp.currentStep)
                        Spacer()
                        Text("\(Int(mp.progress * 100))%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: mp.progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 420)
                    HStack(spacing: 8) {
                        Button("Cancel") { showingCancelConfirm = true }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        Text("Estimated time: a few seconds")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .confirmationDialog(
                    "Cancel migration?",
                    isPresented: $showingCancelConfirm
                ) {
                    Button("Cancel Migration", role: .destructive) {
                        browserManager.migrationTask?.cancel()
                        browserManager.isMigrationInProgress = false
                        browserManager.migrationProgress = nil
                    }
                    Button("Continue", role: .cancel) {}
                }
            }
        }
    }
}

// MARK: - Shortcuts Settings

struct ShortcutsSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings
    @State private var searchText = ""
    @State private var selectedCategory: ShortcutCategory? = nil
    @Environment(KeyboardShortcutManager.self) var keyboardShortcutManager

    private var filteredShortcuts: [KeyboardShortcut] {
        var filtered = keyboardShortcutManager.shortcuts

        // Filter by category
        if let category = selectedCategory {
            filtered = filtered.filter { $0.action.category == category }
        }

        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { shortcut in
                shortcut.action.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort by category and display name
        return filtered.sorted {
            if $0.action.category != $1.action.category {
                return $0.action.category.rawValue < $1.action.category.rawValue
            }
            return $0.action.displayName < $1.action.displayName
        }
    }

    private var shortcutsByCategory: [ShortcutCategory: [KeyboardShortcut]] {
        Dictionary(grouping: filteredShortcuts, by: { $0.action.category })
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Detect Website Shortcuts")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Text("When a website uses the same shortcut, press once for website, twice for Nook")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { WebsiteShortcutProfile.isFeatureEnabled },
                        set: { WebsiteShortcutProfile.isFeatureEnabled = $0 }
                    ))
                    .labelsHidden()
                }
            }

            Section {
                HStack(spacing: 12) {
                    TextField("Search shortcuts...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 240)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            CategoryFilterChip(
                                title: "All",
                                icon: nil,
                                isSelected: selectedCategory == nil,
                                onTap: { selectedCategory = nil }
                            )
                            ForEach(ShortcutCategory.allCases, id: \.self) { category in
                                CategoryFilterChip(
                                    title: category.displayName,
                                    icon: category.icon,
                                    isSelected: selectedCategory == category,
                                    onTap: { selectedCategory = category }
                                )
                            }
                        }
                    }

                    Spacer()

                    Button("Reset to Defaults") {
                        keyboardShortcutManager.resetToDefaults()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            ForEach(ShortcutCategory.allCases, id: \.self) { category in
                if let categoryShortcuts = shortcutsByCategory[category], !categoryShortcuts.isEmpty {
                    Section(category.displayName) {
                        ForEach(categoryShortcuts, id: \.id) { shortcut in
                            ShortcutRowView(shortcut: shortcut)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// MARK: - Shortcut Row
private struct ShortcutRowView: View {
    let shortcut: KeyboardShortcut
    @Environment(KeyboardShortcutManager.self) var keyboardShortcutManager
    @State private var localKeyCombination: KeyCombination

    init(shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
        self._localKeyCombination = State(initialValue: shortcut.keyCombination)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Action description
            VStack(alignment: .leading, spacing: 2) {
                Text(shortcut.action.displayName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(shortcut.action.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Shortcut recorder
            if shortcut.isCustomizable {
                ShortcutRecorderView(
                    keyCombination: $localKeyCombination,
                    action: shortcut.action,
                    shortcutManager: keyboardShortcutManager,
                    onRecordingComplete: {
                        updateShortcut()
                    }
                )
            } else {
                Text(shortcut.keyCombination.displayString)
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Enable toggle
            if shortcut.isCustomizable {
                Toggle("", isOn: Binding(
                    get: { shortcut.isEnabled },
                    set: { newValue in
                        keyboardShortcutManager.toggleShortcut(action: shortcut.action, isEnabled: newValue)
                    }
                ))
                .labelsHidden()
            }
        }
        .padding(12)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onChange(of: shortcut) { _, newShortcut in
            localKeyCombination = newShortcut.keyCombination
        }
    }

    private func updateShortcut() {
        keyboardShortcutManager.updateShortcut(action: shortcut.action, keyCombination: localKeyCombination)
    }
}

// MARK: - Category Filter Chip
private struct CategoryFilterChip: View {
    let title: String
    let icon: String?
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 4) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.caption)
                }
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.accentColor : Color(.controlBackgroundColor))
            )
            .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Extensions Settings

struct ExtensionsSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @ObservedObject var extensionManager: ExtensionManager
    @State private var showingInstallDialog = false
    @State private var safariExtensions: [ExtensionManager.SafariExtensionInfo] = []
    @State private var isScanningSafari = false
    @State private var showSafariSection = false

    var body: some View {
        Form {
            if #available(macOS 15.5, *) {
                Section {
                    HStack {
                        Spacer()
                        Button("Install Extension...") {
                            browserManager.showExtensionInstallDialog()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if extensionManager.installedExtensions.isEmpty && !showSafariSection {
                    Section {
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

                Section("Safari Extensions") {
                    HStack {
                        if isScanningSafari {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning...")
                                .foregroundStyle(.secondary)
                        } else {
                            Button("Scan for Safari Extensions") {
                                scanForSafariExtensions()
                            }
                        }
                        Spacer()
                    }

                    if showSafariSection {
                        if safariExtensions.isEmpty {
                            Text("No Safari Web Extensions found on this Mac.")
                                .font(.caption)
                                .foregroundColor(.secondary)
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
                }
            } else {
                Section {
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
                    .frame(maxWidth: .infinity)
                }
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

@available(macOS 15.5, *)
struct SafariExtensionRowView: View {
    let info: ExtensionManager.SafariExtensionInfo
    let isAlreadyInstalled: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "safari")
                .font(.system(size: 20))
                .foregroundColor(.blue)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(info.name)
                    .font(.headline)
                    .lineLimit(1)
                Text(info.appPath.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if isAlreadyInstalled {
                Text("Installed")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Button("Install") {
                    onInstall()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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
                    let nsImage = NSImage(contentsOfFile: iconPath)
                {
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
                Toggle(
                    "",
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

// MARK: - Advanced Settings

struct AdvancedSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings

    var body: some View {
        @Bindable var settings = nookSettings
        Form {
            #if DEBUG
            Section("Debug Options") {
                Toggle(isOn: $settings.debugToggleUpdateNotification) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show Update Notification")
                        Text(
                            "Force display the sidebar update notification for appearance debugging"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            #endif
        }
        .formStyle(.grouped)
    }
}

// MARK: - Site Search Entry Editor

struct SiteSearchEntryEditor: View {
    let entry: SiteSearchEntry?
    let onSave: (SiteSearchEntry) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var domain: String = ""
    @State private var searchURLTemplate: String = ""
    @State private var colorHex: String = "#666666"

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(entry == nil ? "Add Site Search" : "Edit Site Search")
                .font(.headline)

            Form {
                TextField("Name", text: $name)
                TextField("Domain (e.g. youtube.com)", text: $domain)
                TextField("Search URL (use {query})", text: $searchURLTemplate)
                TextField("Color Hex (e.g. #E62617)", text: $colorHex)
            }
            .formStyle(.grouped)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.bordered)
                Button("Save") {
                    let saved = SiteSearchEntry(
                        id: entry?.id ?? UUID(),
                        name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                        domain: domain.trimmingCharacters(in: .whitespacesAndNewlines),
                        searchURLTemplate: searchURLTemplate.trimmingCharacters(in: .whitespacesAndNewlines),
                        colorHex: colorHex.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    onSave(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || domain.isEmpty || searchURLTemplate.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 450)
        .onAppear {
            if let entry {
                name = entry.name
                domain = entry.domain
                searchURLTemplate = entry.searchURLTemplate
                colorHex = entry.colorHex
            }
        }
    }
}
