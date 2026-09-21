// Licensed under GPL-3.0. See LICENSE.
//
//  SpaceContextMenu.swift
//  Nook
//
//  Created by Aether on 15/11/2025.
//

import SwiftUI
import NookTabsCore
import NookWeb

/// Shared context menu for spaces (used in SpacesList)
struct SpaceContextMenu: View {
    @Environment(TabsController.self) private var tabs
    @Environment(\.tabActions) private var actions
    let space: SpaceRecord
    let canDelete: Bool
    let onOpenSettings: () -> Void
    let onDeleteSpace: () -> Void

    init(
        space: SpaceRecord,
        canDelete: Bool,
        onOpenSettings: @escaping () -> Void,
        onDeleteSpace: @escaping () -> Void
    ) {
        self.space = space
        self.canDelete = canDelete
        self.onOpenSettings = onOpenSettings
        self.onDeleteSpace = onDeleteSpace
    }

    var body: some View {
        Group {
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
        actions?.confirmSpaceDeletion(
            spaceName: space.name,
            tabCount: tabs.tabCount(inSpace: space.id),
            isLastSpace: !canDelete,
            onDelete: onDeleteSpace
        )
    }
}
