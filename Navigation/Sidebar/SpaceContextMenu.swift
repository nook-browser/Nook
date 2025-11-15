//
//  SpaceContextMenu.swift
//  Nook
//
//  Created by Aether on 15/11/2025.
//

import SwiftUI

/// Shared context menu for spaces (used in SpaceTitle, SpacesList, and Sidebar)
struct SpaceContextMenu: View {
    @EnvironmentObject var browserManager: BrowserManager

    let space: Space
    let canDelete: Bool
    let showNewFolder: Bool

    let onEditSpace: () -> Void
    let onDeleteSpace: () -> Void
    let onNewFolder: (() -> Void)?

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
                        browserManager.tabManager.assign(spaceId: space.id, toProfile: newProfileId)
                    }
                )
            ) {
                ForEach(browserManager.profileManager.profiles, id: \.id) { profile in
                    Label(profile.name, systemImage: profile.icon).tag(profile.id)
                }
            }

            Divider()

            // Edit space
            Button {
                onEditSpace()
            } label: {
                Label("Edit Space", systemImage: "square.and.pencil")
            }

            // Theme color
            Button {
                browserManager.showGradientEditor()
            } label: {
                Label("Edit Theme Color", systemImage: "paintpalette")
            }

            // New folder (optional)
            if showNewFolder, let onNewFolder = onNewFolder {
                Divider()
                Button {
                    onNewFolder()
                } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
            }

            // Delete space
            if canDelete {
                Divider()
                Button(role: .destructive) {
                    onDeleteSpace()
                } label: {
                    Label("Delete Space", systemImage: "trash")
                }
            }
        }
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
