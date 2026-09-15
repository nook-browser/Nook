//
//  SpaceContextMenu.swift
//  Nook
//
//  Created by Aether on 15/11/2025.
//

import NookTabsCore
import SwiftUI

/// Shared context menu for spaces (used in SpacesList)
struct SpaceContextMenu: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    let space: SpaceRecord
    let canDelete: Bool
    let onEditName: (() -> Void)?
    let onEditIcon: (() -> Void)?
    let onOpenSettings: () -> Void
    let onDeleteSpace: () -> Void

    var body: some View {
        Group {
            // Profile picker
            Picker(
                currentProfile?.name ?? "Default",
                systemImage: currentProfile?.icon ?? "person.circle",
                selection: Binding(
                    get: { space.profileID },
                    set: { tabs.moveSpaceToEnd(space.id, ofProfile: $0) }
                )
            ) {
                ForEach(browserManager.profileManager.profiles, id: \.id) { profile in
                    Label(profile.name, systemImage: profile.icon).tag(profile.id)
                }
            }

            Divider()

            // Rename (optional)
            if let onEditName = onEditName {
                Button {
                    onEditName()
                } label: {
                    Label("Rename", systemImage: "textformat")
                }
            }

            // Change icon (optional)
            if let onEditIcon = onEditIcon {
                Button {
                    onEditIcon()
                } label: {
                    Label("Change Icon", systemImage: "face.smiling")
                }
            }

            // Space settings
            Button {
                onOpenSettings()
            } label: {
                Label("Space Settings", systemImage: "gear")
            }

            Divider()

            // Delete space
            if canDelete {
                Button(role: .destructive) {
                    showDeleteConfirmation()
                } label: {
                    Label("Delete Space", systemImage: "trash")
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func showDeleteConfirmation() {
        browserManager.dialogManager.showDialog(
            SpaceDeleteConfirmationDialog(
                spaceName: space.name,
                spaceIcon: space.icon,
                tabsCount: tabs.tabCount(inSpace: space.id),
                isLastSpace: !canDelete,
                onDelete: {
                    onDeleteSpace()
                    browserManager.dialogManager.closeDialog()
                },
                onCancel: {
                    browserManager.dialogManager.closeDialog()
                }
            )
        )
    }

    // MARK: - Helper Properties

    private var currentProfile: Profile? {
        let profiles = browserManager.profileManager.profiles
        return profiles.first { $0.id == space.profileID } ?? profiles.first
    }
}
