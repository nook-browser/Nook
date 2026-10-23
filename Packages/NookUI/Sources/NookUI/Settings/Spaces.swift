// Licensed under GPL-3.0. See LICENSE.
//
//  Spaces.swift
//  Nook
//
//  Spaces and profiles. A profile is the spaces sharing one login context (cookies, site data,
//  history), so its data is inspected and cleared here too.
//

import NookTabsCore
import SwiftUI
import NookDesign
import NookWeb

public struct SpacesSettingsView: View {
    @Environment(TabsController.self) private var tabs
    @Environment(\.tabActions) private var actions

    /// Data size per profile, filled in as each store answers.
    @State private var stats: [UUID: String] = [:]
    @State private var showAccentPickerFor: UUID?
    /// A move that would leave its profile empty, waiting on confirmation.
    @State private var pendingMove: (space: UUID, to: UUID?, profile: String)?

    public init() {}

    private var spaces: [SpaceRecord] { tabs.orderedSpaces.filter { !$0.isAgent } }

    public var body: some View {
        Form {
            Section {
                ForEach(tabs.profiles) { profile in
                    profileRow(profile)
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("A profile keeps its own logins, cookies and history. Spaces in the same profile share them. Extensions and settings are shared by all profiles.")
            }

            Section {
                // The Agent space keeps its look and borrows another space's data, so it has no row.
                ForEach(spaces) { space in
                    row(space)
                }
            } header: {
                Text("Spaces")
            } footer: {
                Text("Each space belongs to a profile. Moving a space to another profile signs it in as that profile.")
            }

            Section {
                Button("New Space…", systemImage: "plus", action: showCreateDialog)
            }
        }
        .formStyle(.grouped)
        .task(id: tabs.profiles.map(\.id)) { await refreshStats() }
        .alert(
            "Delete the \u{201C}\(pendingMove?.profile ?? "")\u{201D} profile?",
            isPresented: Binding(get: { pendingMove != nil }, set: { if !$0 { pendingMove = nil } })
        ) {
            Button("Move and Delete Profile", role: .destructive) {
                if let move = pendingMove { tabs.setProfile(move.space, to: move.to) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("No other space uses it. Its logins, cookies and history will be deleted.")
        }
    }

    @ViewBuilder
    private func profileRow(_ profile: ProfileSummary) -> some View {
        HStack(spacing: NookDesign.Spacing.md) {
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                TextField("Profile name", text: Binding(
                    get: { profile.name },
                    set: { tabs.renameProfile(profile.id, to: $0) }
                ))
                .textFieldStyle(.plain)
                Text(([profile.spaceIDs.compactMap { tabs.space($0)?.name }.joined(separator: ", ")]
                      + [stats[profile.id] ?? "Checking…"]).joined(separator: " · "))
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Clear Website Data", systemImage: "trash") {
                    Task { await clearData(profile) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func profilePicker(_ space: SpaceRecord) -> some View {
        let current = tabs.profiles.first { $0.spaceIDs.contains(space.id) }
        // A nil selection is "New Profile"; every space is always in some profile.
        return Picker("Profile", selection: Binding<UUID?>(
            get: { current?.id },
            set: { move(space.id, to: $0, from: current) }
        )) {
            ForEach(tabs.profiles) { profile in
                Text(profile.name).tag(UUID?.some(profile.id))
            }
            Divider()
            Text("New Profile").tag(UUID?.none)
        }
        .fixedSize()
    }

    private func move(_ spaceID: UUID, to storeID: UUID?, from current: ProfileSummary?) {
        guard storeID != current?.id else { return }
        if let current, current.spaceIDs == [spaceID] {
            pendingMove = (spaceID, storeID, current.name)
        } else {
            tabs.setProfile(spaceID, to: storeID)
        }
    }

    @ViewBuilder
    private func row(_ space: SpaceRecord) -> some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Button {
                showAccentPickerFor = space.id
            } label: {
                Circle()
                    .fill(space.accentColor)
                    .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { showAccentPickerFor == space.id },
                set: { if !$0 { showAccentPickerFor = nil } }
            )) {
                SpaceAccentPicker(selectedHex: Binding(
                    get: { space.accentHex },
                    set: { tabs.updateSpace(space.id, name: nil, icon: nil, accentHex: $0) }
                ))
                .padding(NookDesign.Spacing.lg)
            }

            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                TextField("Space name", text: Binding(
                    get: { space.name },
                    set: { tabs.updateSpace(space.id, name: $0, icon: nil, accentHex: nil) }
                ))
                .textFieldStyle(.plain)
            }
            Spacer()
            profilePicker(space)
            if spaces.count > 1 {
                Menu {
                    Button("Delete Space…", systemImage: "trash", role: .destructive) {
                        showDeleteDialog(space)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
    }

    // MARK: - Data

    private func refreshStats() async {
        for summary in tabs.profiles {
            guard let space = summary.spaceIDs.first, let profile = tabs.profile(forSpace: space) else { continue }
            await profile.refreshDataStoreStats()
            stats[summary.id] = profile.estimatedDataSize
        }
    }

    private func clearData(_ summary: ProfileSummary) async {
        guard let space = summary.spaceIDs.first, let profile = tabs.profile(forSpace: space) else { return }
        await profile.clearAllData()
        stats[summary.id] = profile.estimatedDataSize
    }

    // MARK: - Dialogs

    private func showCreateDialog() {
        actions?.presentSpaceCreation { name, accentHex in
            tabs.createSpace(
                name: name.isEmpty ? "New Space" : name,
                icon: "square.grid.2x2",
                accentHex: accentHex,
                after: tabs.orderedSpaces.last?.id,
                sharingLoginsWith: tabs.windowRegistry.activeWindow?.spaceID ?? tabs.regularWindows.first?.spaceID
            )
        }
    }

    private func showDeleteDialog(_ space: SpaceRecord) {
        actions?.confirmSpaceDeletion(
            spaceName: space.name,
            tabCount: tabs.tabCount(inSpace: space.id),
            isLastSpace: spaces.count <= 1,
            onDelete: { tabs.deleteSpace(space.id) }
        )
    }
}
