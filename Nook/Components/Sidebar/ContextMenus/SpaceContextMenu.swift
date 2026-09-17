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
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    let space: SpaceRecord
    let canDelete: Bool
    let onOpenSettings: () -> Void
    let onDeleteSpace: () -> Void

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
        browserManager.dialogManager.showDialog(
            SpaceDeleteConfirmationDialog(
                spaceName: space.name,
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
}
