//
//  Profiles.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import NookTabsCore
import SwiftUI

struct ProfilesSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @State private var profileToRename: Profile? = nil
    @State private var profileToDelete: Profile? = nil

    var body: some View {
        Form {
            Section("Profiles") {
                Button(action: showCreateDialog) {
                    Label("Create Profile", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                if browserManager.profileManager.profiles.isEmpty {
                    Label(
                        "No profiles yet. Create one to get started.",
                        systemImage: "person.crop.circle"
                    )
                    .foregroundStyle(.secondary)
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
            }

            Section {
                MigrationControls()
            } header: {
                Text("Legacy Data")
            } footer: {
                Text(
                    "Scan for cookies and site data in the shared store and migrate them into \(browserManager.currentProfile?.name ?? "current profile")."
                )
            }

            Section("Space Assignments") {
                HStack(spacing: NookDesign.Spacing.md) {
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

                if tabs.orderedSpaces.isEmpty {
                    Label(
                        "No spaces yet. Create a space to assign profiles.",
                        systemImage: "rectangle.3.group"
                    )
                    .foregroundStyle(.secondary)
                } else {
                    ForEach(tabs.orderedSpaces) { space in
                        SpaceAssignmentRowView(space: space)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    // MARK: - Helpers

    private func spacesCount(for profile: Profile) -> Int {
        tabs.spaces(inProfile: profile.id).count
    }

    private func tabsCount(for profile: Profile) -> Int {
        tabs.items(inProfile: profile.id).count
    }

    private func pinnedCount(for profile: Profile) -> Int {
        tabs.spaces(inProfile: profile.id).reduce(0) { $0 + tabs.tabCount(under: .pinned(spaceID: $1.id)) }
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
                    let createdID = tabs.createProfile(name: trimmed, icon: safeIcon)
                    if let created = browserManager.profileManager.profiles.first(where: { $0.id == createdID }) {
                        Task { await browserManager.switchToProfile(created) }
                    }
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
                    tabs.updateProfile(target.id, name: newName, icon: newIcon)
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
                let heir = browserManager.profileManager.profiles.first { $0.id != profile.id }
                guard let heir else {
                    browserManager.dialogManager.closeDialog()
                    return
                }
                browserManager.dialogManager.closeDialog()
                Task { @MainActor in
                    if browserManager.currentProfile?.id == profile.id {
                        await browserManager.switchToProfile(heir)
                    }
                    await profile.clearAllData()
                    tabs.deleteProfile(profile.id, heir: heir.id)
                }
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
                    VStack(alignment: .leading, spacing: NookDesign.Spacing.lg) {
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

    // MARK: - Space assignment helpers

    private func assignAllSpacesToCurrentProfile() {
        guard let pid = browserManager.currentProfile?.id else { return }
        for space in tabs.orderedSpaces {
            tabs.moveSpaceToEnd(space.id, ofProfile: pid)
        }
    }

    private func resetAllSpaceAssignments() {
        guard let defaultProfileId = browserManager.profileManager.profiles.first?.id else { return }
        for space in tabs.orderedSpaces {
            tabs.moveSpaceToEnd(space.id, ofProfile: defaultProfileId)
        }
    }
}

// MARK: - Space Assignment Row

private struct SpaceAssignmentRowView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    let space: SpaceRecord
    @State private var showDeleteConfirmation = false

    private var canDelete: Bool {
        tabs.orderedSpaces.count > 1
    }

    var body: some View {
        HStack(spacing: NookDesign.Spacing.lg) {
            // Space icon
            Group {
                if space.icon.isEmojiIcon {
                    Text(space.icon)
                        .font(NookDesign.Font.body)
                } else {
                    Image(systemName: space.icon)
                        .font(NookDesign.Font.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(
                width: NookDesign.Size.settingsChip,
                height: NookDesign.Size.settingsChip
            )
            .background(NookDesign.Surface.raised)
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))

            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(space.name)
                HStack(spacing: NookDesign.Spacing.sm) {
                    SpaceProfileBadge(space: space, size: .compact)
                        .environmentObject(browserManager)
                    Text(currentProfileName)
                        .font(NookDesign.Font.caption)
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
                        space.profileID
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
                .foregroundStyle(.red)
                .help("Delete Space")
            }
        }
        .alert("Delete \"\(space.name)\"?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                tabs.deleteSpace(space.id)
            }
        } message: {
            let tabCount = tabs.tabCount(inSpace: space.id)
            Text("This will close \(tabCount) tab\(tabCount == 1 ? "" : "s") in this space.")
        }
    }

    private var currentProfileName: String {
        browserManager.profileManager.profiles.first { $0.id == space.profileID }?.name
            ?? browserManager.profileManager.profiles.first?.name
            ?? "Default"
    }

    private func assign(space: SpaceRecord, to id: UUID) {
        tabs.moveSpaceToEnd(space.id, ofProfile: id)
    }
}

// MARK: - Legacy Data Migration

private struct MigrationControls: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var legacySummary: BrowserManager.LegacyDataSummary? = nil
    @State private var lastDetectionDate: Date? = nil
    @State private var showingCancelConfirm: Bool = false

    var body: some View {
        Group {
            HStack(spacing: NookDesign.Spacing.md) {
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
                LabeledContent {
                    if let dt = lastDetectionDate {
                        Text(
                            DateFormatter.localizedString(
                                from: dt,
                                dateStyle: .none,
                                timeStyle: .short
                            )
                        )
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                    }
                } label: {
                    Label {
                        Text(
                            summary.hasAny
                                ? "Legacy data detected, \(summary.estimatedDescription)"
                                : "No legacy shared data found"
                        )
                    } icon: {
                        Image(
                            systemName: summary.hasAny
                                ? "exclamationmark.circle" : "checkmark.circle"
                        )
                        .foregroundStyle(summary.hasAny ? .orange : .green)
                    }
                }
            }

            if browserManager.isMigrationInProgress,
                let mp = browserManager.migrationProgress
            {
                LabeledContent {
                    Text("\(Int(mp.progress * 100))%")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                } label: {
                    Text(mp.currentStep)
                }

                ProgressView(value: mp.progress)
                    .progressViewStyle(.linear)

                HStack(spacing: NookDesign.Spacing.md) {
                    Button("Cancel") { showingCancelConfirm = true }
                        .buttonStyle(.bordered)
                        .tint(.red)
                    Text("Estimated time: a few seconds")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
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
