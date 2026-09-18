// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
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
    @State private var stats: [UUID: String] = [:]
    @State private var showAccentPickerFor: UUID?

    public init() {}

    public var body: some View {
        Form {
            Section {
                ForEach(tabs.orderedSpaces) { space in
                    row(space)
                }
            } header: {
                Text("Spaces")
            } footer: {
                Text("Each space keeps its own cookies and logins. Sites you sign into in one space stay signed out in the others.")
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
                Text(stats[space.id] ?? "Checking…")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Clear Website Data", systemImage: "trash") {
                    Task { await clearData(space) }
                }
                if tabs.orderedSpaces.count > 1 {
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

    // MARK: - Data

    private func refreshStats() async {
        for space in tabs.orderedSpaces {
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
            isLastSpace: tabs.orderedSpaces.count <= 1,
            onDelete: { tabs.deleteSpace(space.id) }
        )
    }
}
