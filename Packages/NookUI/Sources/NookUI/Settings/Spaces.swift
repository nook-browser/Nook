// Licensed under GPL-3.0. See LICENSE.
//
//  Spaces.swift
//  Nook
//
//  Spaces settings. A space is a login context: it owns its cookies and site data, so this is
//  also where that data is inspected and cleared.
//

import NookTabsCore
import SwiftUI
import NookDesign
import NookWeb

public struct SpacesSettingsView: View {
    @Environment(TabsController.self) private var tabs
    @Environment(\.tabActions) private var actions

    /// Cookie and record counts per space, filled in as each store answers.
    @State private var showIconPickerFor: UUID?
    @State private var stats: [UUID: String] = [:]
    @State private var showAccentPickerFor: UUID?

    public init() {}

    private var spaces: [SpaceRecord] { tabs.orderedSpaces.filter { !$0.isAgent } }

    public var body: some View {
        Form {
            Section {
                // The Agent space keeps its look and borrows another space's data, so it has no row.
                ForEach(spaces) { space in
                    row(space)
                }
            } header: {
                Text("Spaces")
            } footer: {
                Text("Spaces organize your tabs. Spaces using the same profile share cookies and logins; a new profile keeps them separate.")
            }

            Section {
                Button("New Space…", systemImage: "plus", action: showCreateDialog)
            }
        }
        .formStyle(.grouped)
        .task(id: tabs.orderedSpaces.count) { await refreshStats() }
    }

    @ViewBuilder
    private func row(_ space: SpaceRecord) -> some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Button {
                showAccentPickerFor = space.id
            } label: {
                SpaceThemeSurface(appearance: space.resolvedAppearance)
                    .clipShape(Circle())
                    .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Customize appearance for \(space.name)")
            .help("Customize space appearance")
            .popover(isPresented: Binding(
                get: { showAccentPickerFor == space.id },
                set: { if !$0 { showAccentPickerFor = nil } }
            )) {
                SpaceAppearancePicker(appearance: Binding(
                    get: { tabs.space(space.id)?.resolvedAppearance ?? space.resolvedAppearance },
                    set: { tabs.updateSpaceAppearance(space.id, appearance: $0) }
                ))
            }

            Button { showIconPickerFor = space.id } label: {
                SpaceIcon(space.icon).frame(width: 32, height: 32).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Change Icon or Emoji…")
            .accessibilityLabel("Space icon for \(space.name)")
            .popover(isPresented: Binding(
                get: { showIconPickerFor == space.id },
                set: { if !$0 { showIconPickerFor = nil } }
            )) {
                SpaceIconPicker(icon: Binding(
                    get: { tabs.space(space.id)?.icon ?? space.icon },
                    set: { tabs.updateSpace(space.id, name: nil, icon: $0, accentHex: nil) }
                ), onSelect: { showIconPickerFor = nil })
            }

            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                TextField("Space name", text: Binding(
                    get: { space.name },
                    set: { tabs.updateSpace(space.id, name: $0, icon: nil, accentHex: nil) }
                ))
                .textFieldStyle(.plain)
                if sharedProfileCount(space) > 1 {
                    Text("Profile shared by \(sharedProfileCount(space)) spaces")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.secondary)
                }
                Text(stats[space.id] ?? "Checking…")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button(sharedProfileCount(space) > 1 ? "Clear Shared Profile Data" : "Clear Website Data", systemImage: "trash") {
                    Task { await clearData(space) }
                }
                if spaces.count > 1 {
                    Divider()
                    Button("Delete Space…", systemImage: "trash", role: .destructive) {
                        showDeleteDialog(space)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func sharedProfileCount(_ space: SpaceRecord) -> Int {
        guard let id = tabs.profileIdentifier(forSpace: space.id) else { return 0 }
        return spaces.filter { tabs.profileIdentifier(forSpace: $0.id) == id }.count
    }

    // MARK: - Data

    private func refreshStats() async {
        for space in spaces {
            guard let profile = tabs.profile(forSpace: space.id) else { continue }
            await profile.refreshDataStoreStats()
            stats[space.id] = profile.estimatedDataSize
        }
    }

    private func clearData(_ space: SpaceRecord) async {
        guard let profile = tabs.profile(forSpace: space.id) else { return }
        await profile.clearAllData()
        stats[space.id] = profile.estimatedDataSize
    }

    // MARK: - Dialogs

    private func showCreateDialog() {
        actions?.presentSpaceCreation { name, accentHex in
            tabs.createSpace(
                name: name.isEmpty ? "New Space" : name,
                icon: "square.grid.2x2",
                accentHex: accentHex,
                after: tabs.orderedSpaces.last?.id
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
