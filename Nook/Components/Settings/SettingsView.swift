//
//  SettingsView.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import AppKit
import SwiftUI

// MARK: - Settings Root (Native macOS Settings)
struct SettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var gradientColorManager: GradientColorManager

    var body: some View {
        TabView(selection: $browserManager.settingsManager.currentSettingsTab) {
            SettingsPane {
                GeneralSettingsView()
            }
                .tag(SettingsTabs.general)

            SettingsPane {
                PrivacySettingsView()
            }
                .tag(SettingsTabs.privacy)

            SettingsPane {
                ProfilesSettingsView()
            }
                .tag(SettingsTabs.profiles)

            

            SettingsPane {
                ShortcutsSettingsView()
            }
                .tag(SettingsTabs.shortcuts)

            SettingsPane {
                ExtensionsSettingsView()
            }
                .tag(SettingsTabs.extensions)

            SettingsPane {
                AdvancedSettingsView()
            }
                .tag(SettingsTabs.advanced)
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Picker("Settings Tabs", selection: $browserManager.settingsManager.currentSettingsTab) {
                    ForEach(SettingsTabs.ordered, id: \.self) { tab in
                        Image(systemName: tab.icon)
                            .help(tab.name)
                            .tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }
}

// MARK: - Reusable pane wrapper: fixed height + scrolling
private struct SettingsPane<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    private let fixedHeight: CGFloat = 620
    private let minWidth: CGFloat = 760

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(20)
        }
        .scrollIndicators(.automatic)
        .frame(minWidth: minWidth)
        .frame(minHeight: fixedHeight, idealHeight: fixedHeight, maxHeight: fixedHeight)
    }
}

// MARK: - Horizontal Tab Bar
// Legacy custom tab strip retained for reference but no longer used.
struct SettingsTabStrip: View {
    @Binding var selection: SettingsTabs
    var body: some View { EmptyView() }
}

struct SettingsTabItem: View {
    let tab: SettingsTabs
    let isSelected: Bool
    var body: some View { EmptyView() }
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

struct ProfilesSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var creatingName: String = ""
    @State private var creatingIcon: String = "person.crop.circle"
    @State private var renamingName: String = ""
    @State private var renamingIcon: String = "person.crop.circle"
    @State private var profileToRename: Profile? = nil
    @State private var profileToDelete: Profile? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Profiles list and actions
            SettingsSectionCard(title: "Profiles", subtitle: "Create, switch, and manage browsing personas") {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        NookButton(text: "Create Profile", iconName: "plus", variant: .primary) {
                            showCreateDialog()
                        }
                        .accessibilityLabel("Create Profile")
                        .accessibilityHint("Open dialog to create a new profile")

                        Spacer()
                    }

                    Divider().opacity(0.4)

                    if browserManager.profileManager.profiles.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle")
                                .foregroundColor(.secondary)
                            Text("No profiles yet. Create one to get started.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(browserManager.profileManager.profiles, id: \.id) { profile in
                                ProfileRowView(
                                    profile: profile,
                                    isCurrent: browserManager.currentProfile?.id == profile.id,
                                    spacesCount: spacesCount(for: profile),
                                    tabsCount: tabsCount(for: profile),
                                    dataSizeDescription: "Shared store",
                                    pinnedCount: pinnedCount(for: profile),
                                    onMakeCurrent: { Task { await browserManager.switchToProfile(profile) } },
                                    onRename: { startRename(profile) },
                                    onDelete: { startDelete(profile) },
                                    onManageData: { showDataManagement(for: profile) }
                                )
                                .accessibilityLabel("Profile \(profile.name)")
                                .accessibilityHint(browserManager.currentProfile?.id == profile.id ? "Current profile" : "Inactive profile")
                            }
                        }
                    }
                }
                
                Divider().opacity(0.4)
                
                // Migration controls appear under the profile list
                MigrationControls()
                    .environmentObject(browserManager)
                
                Divider().opacity(0.4)
                
                // Export / Import actions (placeholders)
                HStack(spacing: 8) {
                    NookButton(text: "Export Current Profile", iconName: "square.and.arrow.up") {
                        showExportPlaceholder()
                    }
                    .accessibilityLabel("Export current profile")
                    
                    NookButton(text: "Import Profile", iconName: "square.and.arrow.down") {
                        showImportPlaceholder()
                    }
                    .accessibilityLabel("Import profile")
                    
                    Spacer()
                }
            }

            

            // Space assignments management
            SettingsSectionCard(title: "Space Assignments", subtitle: "Assign spaces to specific profiles") {
                VStack(alignment: .leading, spacing: 12) {
                    // Bulk actions
                    HStack(spacing: 8) {
                        NookButton(text: "Assign All to Current Profile", iconName: "checkmark.circle") {
                            assignAllSpacesToCurrentProfile()
                        }
                        .accessibilityLabel("Assign all spaces to current profile")

                        NookButton(text: "Reset to Default Profile", iconName: "arrow.uturn.backward") {
                            resetAllSpaceAssignments()
                        }
                        .accessibilityLabel("Reset space assignments to none")

                        NookButton(text: "Auto-assign by Usage", iconName: "sparkles") {
                            showAutoAssignPlaceholder()
                        }
                        .accessibilityLabel("Auto assign by usage (placeholder)")

                        Spacer()
                    }

                    Divider().opacity(0.4)

                    if browserManager.tabManager.spaces.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "rectangle.3.group")
                                .foregroundStyle(.secondary)
                            Text("No spaces yet. Create a space to assign profiles.")
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(browserManager.tabManager.spaces, id: \.id) { space in
                                SpaceAssignmentRowView(space: space)
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Helpers
    private func spacesCount(for profile: Profile) -> Int {
        browserManager.tabManager.spaces.filter { $0.profileId == profile.id }.count
    }

    private func tabsCount(for profile: Profile) -> Int {
        let spaceIds = Set(browserManager.tabManager.spaces.filter { $0.profileId == profile.id }.map { $0.id })
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
        creatingName = ""
        creatingIcon = "person.crop.circle"
        let dialog = ProfileCreationDialog(
            profileName: $creatingName,
            profileIcon: $creatingIcon,
            isNameAvailable: { proposed in
                let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return false }
                return !browserManager.profileManager.profiles.contains { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
            },
            onSave: {
                let trimmed = creatingName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                let safeIcon = creatingIcon.isEmpty ? "person.crop.circle" : creatingIcon
                let created = browserManager.profileManager.createProfile(name: trimmed, icon: safeIcon)
                Task { await browserManager.switchToProfile(created) }
                browserManager.dialogManager.closeDialog()
            },
            onCancel: { browserManager.dialogManager.closeDialog() }
        )
        browserManager.dialogManager.showDialog(dialog)
    }

    private func startRename(_ profile: Profile) {
        profileToRename = profile
        renamingName = profile.name
        renamingIcon = profile.icon
        let dialog = ProfileRenameDialog(
            originalProfile: profile,
            profileName: $renamingName,
            profileIcon: $renamingIcon,
            isNameAvailable: { proposed in
                let trimmed = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
                return !browserManager.profileManager.profiles.contains { $0.id != profile.id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }
            },
            onSave: {
                guard let p = profileToRename else { return }
                let trimmed = renamingName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                p.name = trimmed
                p.icon = renamingIcon
                browserManager.profileManager.persistProfiles()
                browserManager.dialogManager.closeDialog()
            },
            onCancel: { browserManager.dialogManager.closeDialog() }
        )
        browserManager.dialogManager.showDialog(dialog)
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
        // Placeholder: show info dialog
        let header = AnyView(DialogHeader(icon: "internaldrive", title: "Manage Data", subtitle: "Per‑profile data isolation coming soon"))
        let content = VStack(alignment: .leading, spacing: 12) {
            Text("Currently, profiles share a single website data store.")
            Text("Privacy tools are available under the Privacy tab.")
                .foregroundStyle(.secondary)
        }
        let footer = AnyView(DialogFooter(rightButtons: [
            DialogButton(text: "Close", variant: .primary) { browserManager.dialogManager.closeDialog() }
        ]))
        browserManager.dialogManager.showCustomContentDialog(header: header, content: AnyView(content), footer: footer)
    }

    private func showExportPlaceholder() {
        let header = AnyView(DialogHeader(icon: "square.and.arrow.up", title: "Export Profile", subtitle: "Coming soon"))
        let body = AnyView(Text("Profile export is not yet implemented."))
        let footer = AnyView(DialogFooter(rightButtons: [DialogButton(text: "OK", variant: .primary) { browserManager.dialogManager.closeDialog() }]))
        browserManager.dialogManager.showCustomContentDialog(header: header, content: body, footer: footer)
    }

    private func showImportPlaceholder() {
        let header = AnyView(DialogHeader(icon: "square.and.arrow.down", title: "Import Profile", subtitle: "Coming soon"))
        let body = AnyView(Text("Profile import is not yet implemented."))
        let footer = AnyView(DialogFooter(rightButtons: [DialogButton(text: "OK", variant: .primary) { browserManager.dialogManager.closeDialog() }]))
        browserManager.dialogManager.showCustomContentDialog(header: header, content: body, footer: footer)
    }

    // MARK: - Space assignment helpers and views
    private func assign(space: Space, to id: UUID?) {
        browserManager.tabManager.assign(spaceId: space.id, toProfile: id)
    }

    private func assignAllSpacesToCurrentProfile() {
        guard let pid = browserManager.currentProfile?.id else { return }
        for sp in browserManager.tabManager.spaces {
            browserManager.tabManager.assign(spaceId: sp.id, toProfile: pid)
        }
    }

    private func resetAllSpaceAssignments() {
        for sp in browserManager.tabManager.spaces {
            browserManager.tabManager.assign(spaceId: sp.id, toProfile: nil)
        }
    }

    private func showAutoAssignPlaceholder() {
        let header = AnyView(DialogHeader(icon: "sparkles", title: "Auto-assign by Usage", subtitle: "Coming soon"))
        let body = AnyView(Text("Automatic assignment based on recent tab activity will be available in a future update."))
        let footer = AnyView(DialogFooter(rightButtons: [DialogButton(text: "OK", variant: .primary) { browserManager.dialogManager.closeDialog() }]))
        browserManager.dialogManager.showCustomContentDialog(header: header, content: body, footer: footer)
    }

    private func resolvedProfile(for id: UUID?) -> Profile? {
        guard let id else { return nil }
        return browserManager.profileManager.profiles.first(where: { $0.id == id })
    }

    private struct SpaceAssignmentRowView: View {
        @EnvironmentObject var browserManager: BrowserManager
        let space: Space

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
                        Label("Assign to \(current.name)", systemImage: "checkmark.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                // Profile picker menu
                Menu {
                    // Use compact picker inside menu
                    let binding = Binding<UUID?>(
                        get: { space.profileId },
                        set: { newId in assign(space: space, to: newId) }
                    )
                    Text("Current: \(currentProfileName)")
                        .foregroundStyle(.secondary)
                    Divider()
                    ProfilePickerView(selectedProfileId: binding, onSelect: { _ in }, compact: true, showNoneOption: true)
                        .environmentObject(browserManager)
                } label: {
                    Label("Change", systemImage: "person.crop.circle")
                        .labelStyle(.titleAndIcon)
                }
                .menuStyle(.borderlessButton)
            }
            .padding(10)
            .background(Color(.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }

        private var currentProfileName: String {
            if let pid = space.profileId,
               let p = browserManager.profileManager.profiles.first(where: { $0.id == pid }) {
                return p.name
            }
            return "No Profile"
        }

        private func assign(space: Space, to id: UUID?) {
            browserManager.tabManager.assign(spaceId: space.id, toProfile: id)
        }

        private func isEmoji(_ string: String) -> Bool {
            return string.unicodeScalars.contains { scalar in
                (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) ||
                (scalar.value >= 0x2600 && scalar.value <= 0x26FF) ||
                (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
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
                NookButton(text: "Detect Legacy Data", iconName: "magnifyingglass") {
                    Task { @MainActor in
                        let summary = await browserManager.detectLegacySharedData()
                        legacySummary = summary
                        lastDetectionDate = Date()
                    }
                }
                .accessibilityLabel("Detect Legacy Data")

                NookButton(text: "Migrate to Current Profile", iconName: "arrow.down.to.line") {
                    browserManager.startMigrationToCurrentProfile()
                }
                .disabled(browserManager.isMigrationInProgress == true)
                .accessibilityLabel("Migrate shared data to current profile")

                NookButton(text: "Start Fresh", iconName: "trash") {
                    Task { @MainActor in
                        await browserManager.clearSharedDataAfterMigration()
                        legacySummary = nil
                    }
                }
                .tint(.red)
                .accessibilityLabel("Clear shared website data without migration")

                Spacer()
            }

            if let summary = legacySummary {
                HStack(spacing: 8) {
                    Image(systemName: summary.hasAny ? "exclamationmark.circle" : "checkmark.circle")
                        .foregroundStyle(summary.hasAny ? .orange : .green)
                    Text(summary.hasAny ? "Legacy data detected — \(summary.estimatedDescription)" : "No legacy shared data found")
                        .font(.subheadline)
                    if let dt = lastDetectionDate {
                        Text("• \(DateFormatter.localizedString(from: dt, dateStyle: .none, timeStyle: .short))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Scan for cookies and site data in the shared store and migrate them into \(browserManager.currentProfile?.name ?? "current profile").")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if browserManager.isMigrationInProgress, let mp = browserManager.migrationProgress {
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
                .confirmationDialog("Cancel migration?", isPresented: $showingCancelConfirm) {
                    Button("Cancel Migration", role: .destructive) {
                        browserManager.migrationTask?.cancel()
                        browserManager.isMigrationInProgress = false
                        browserManager.migrationProgress = nil
                    }
                    Button("Continue", role: .cancel) {}
                }
            }

            Divider().opacity(0.4)

            // Export/Import placeholders with profile context
            HStack(spacing: 8) {
                NookButton(text: "Export Current Profile", iconName: "square.and.arrow.up") {
                    // Placeholder; future: export WK data + SwiftData snapshot
                    // Reuse existing placeholders for now
                    // showExportPlaceholder() is defined in parent view; keep UI consistent
                    // For now, present a minimal dialog here
                    let header = AnyView(DialogHeader(icon: "square.and.arrow.up", title: "Export Profile", subtitle: browserManager.currentProfile?.name ?? ""))
                    let body = AnyView(Text("Export is not implemented yet.").font(.body))
                    let footer = AnyView(DialogFooter(rightButtons: [DialogButton(text: "OK", variant: .primary) { browserManager.dialogManager.closeDialog() }]))
                    browserManager.dialogManager.showCustomContentDialog(header: header, content: body, footer: footer)
                }
                NookButton(text: "Import Into Current", iconName: "square.and.arrow.down") {
                    let header = AnyView(DialogHeader(icon: "square.and.arrow.down", title: "Import Profile", subtitle: browserManager.currentProfile?.name ?? ""))
                    let body = AnyView(Text("Import is not implemented yet.").font(.body))
                    let footer = AnyView(DialogFooter(rightButtons: [DialogButton(text: "OK", variant: .primary) { browserManager.dialogManager.closeDialog() }]))
                    browserManager.dialogManager.showCustomContentDialog(header: header, content: body, footer: footer)
                }
                Spacer()
            }
        }
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
                Text("Nook")
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
