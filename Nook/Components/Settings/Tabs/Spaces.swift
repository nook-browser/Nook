//
//  Spaces.swift
//  Nook
//
//  Spaces settings. A space is a login context: it owns its cookies and site data, so this is
//  also where that data is inspected and cleared.
//

import NookTabsCore
import SwiftUI

struct SpacesSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs

    /// Cookie and record counts per space, filled in as each store answers.
    @State private var stats: [UUID: String] = [:]

    var body: some View {
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
            SpaceIconView(icon: space.icon, tint: space.accentColor)
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(space.name)
                Text(stats[space.id] ?? "Checking…")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Edit Space…", systemImage: "pencil") {
                    SpaceEditDialog.present(spaceID: space.id, tabs: tabs, dialogManager: browserManager.dialogManager)
                }
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
        browserManager.dialogManager.showDialog(
            SpaceCreationDialog(
                onCreate: { name, icon, accentHex in
                    tabs.createSpace(
                        name: name.isEmpty ? "New Space" : name,
                        icon: icon.isEmpty ? "square.grid.2x2" : icon,
                        accentHex: accentHex,
                        after: tabs.orderedSpaces.last?.id
                    )
                    browserManager.dialogManager.closeDialog()
                },
                onCancel: { browserManager.dialogManager.closeDialog() }
            )
        )
    }

    private func showDeleteDialog(_ space: SpaceRecord) {
        browserManager.dialogManager.showDialog(
            SpaceDeleteConfirmationDialog(
                spaceName: space.name,
                spaceIcon: space.icon,
                tabsCount: tabs.tabCount(inSpace: space.id),
                isLastSpace: tabs.orderedSpaces.count <= 1,
                onDelete: {
                    tabs.deleteSpace(space.id)
                    browserManager.dialogManager.closeDialog()
                },
                onCancel: { browserManager.dialogManager.closeDialog() }
            )
        )
    }
}
