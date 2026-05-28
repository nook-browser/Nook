//
//  SpaceContextMenu.swift
//  Nook
//
//  Created by Aether on 15/11/2025.
//

import SwiftUI

/// Shared context menu for spaces (used in SpaceTitle and SpacesList)
struct SpaceContextMenu: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var tabManager: TabManager
    let space: Space
    let canDelete: Bool
    let onEditName: (() -> Void)?
    let onEditIcon: (() -> Void)?
    let onOpenSettings: () -> Void
    let onDeleteSpace: () -> Void

    var body: some View {
        Group {
            // Profile picker
            Picker(
                currentProfileName,
                systemImage: currentProfileIcon,
                selection: Binding(
                    get: {
                        space.profileId ?? browserManager.profileManager.profiles.first?.id ?? UUID()
                    },
                    set: { newProfileId in
                        tabManager.assign(spaceId: space.id, toProfile: newProfileId)
                    }
                )
            ) {
                ForEach(browserManager.profileManager.profiles, id: \.id) { profile in
                    Label(profile.name, systemImage: profile.icon).tag(profile.id)
                }
            }

            Divider()

            // Rename (optional - only available for SpaceTitle)
            if let onEditName = onEditName {
                Button {
                    onEditName()
                } label: {
                    Label("Rename", systemImage: "textformat")
                }
            }

            // Change icon (optional - only available for SpaceTitle)
            if let onEditIcon = onEditIcon {
                Button {
                    onEditIcon()
                } label: {
                    Label("Change Icon", systemImage: "face.smiling")
                }
            }

            // Customize appearance
            Button {
                browserManager.showGradientEditor()
            } label: {
                Label("Customize Appearance", systemImage: "paintpalette")
            }

            Divider()

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
        // Count both regular and space-pinned tabs
        let regularTabsCount = tabManager.tabsBySpace[space.id]?.count ?? 0
        let spacePinnedTabsCount = tabManager.spacePinnedTabs(for: space.id).count
        let tabsCount = regularTabsCount + spacePinnedTabsCount

        browserManager.dialogManager.showDialog(
            SpaceDeleteConfirmationDialog(
                spaceName: space.name,
                spaceIcon: space.icon,
                tabsCount: tabsCount,
                isLastSpace: tabManager.spaces.count <= 1,
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

    private var currentProfileName: String {
        guard let profileId = space.profileId,
              let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId })
        else {
            return browserManager.profileManager.profiles.first?.name ?? "Default"
        }
        return profile.name
    }

    private var currentProfileIcon: String {
        guard let profileId = space.profileId,
              let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId })
        else {
            return browserManager.profileManager.profiles.first?.icon ?? "person.circle"
        }
        return profile.icon
    }
}
