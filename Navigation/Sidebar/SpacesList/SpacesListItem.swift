//
//  SpacesListItem.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//  Refactored by Aether on 15/11/2025.
//

import SwiftUI

struct SpacesListItem: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState

    let space: Space
    let isActive: Bool
    let compact: Bool
    let isFaded: Bool

    @State private var isHovering: Bool = false

    private let dotSize: CGFloat = 6

    var body: some View {
        Button {
            withAnimation(.easeOut(duration: 0.2)) {
                browserManager.setActiveSpace(space, in: windowState)
            }
        } label: {
            spaceIcon
        }
        .labelStyle(.iconOnly)
        .buttonStyle(NavButtonStyle())
        .foregroundStyle(Color.primary)
        .layoutPriority(isActive ? 1 : 0)
        .opacity(isFaded ? 0.3 : 1.0)
        .onHover { hovering in
            isHovering = hovering
        }
        .contextMenu {
            spaceContextMenu
        }
    }

    // MARK: - Icon

    @ViewBuilder
    private var spaceIcon: some View {
        if compact && !isActive {
            // Compact mode: show dot
            Circle()
                .fill(iconColor)
                .frame(width: dotSize, height: dotSize)
        } else {
            // Normal mode: show icon or emoji
            if isEmoji(space.icon) {
                Text(space.icon)
            } else {
                Image(systemName: space.icon)
                    .foregroundStyle(iconColor)
            }
        }
    }

    private var iconColor: Color {
        browserManager.gradientColorManager.isDark
            ? AppColors.spaceTabTextDark
            : AppColors.spaceTabTextLight
    }

    // MARK: - Context Menu

    @ViewBuilder
    private var spaceContextMenu: some View {
        SpaceContextMenu(
            space: space,
            canDelete: browserManager.tabManager.spaces.count > 1,
            onEditSpace: showSpaceEditDialog,
            onDeleteSpace: {
                browserManager.tabManager.removeSpace(space.id)
            }
        )
        .environmentObject(browserManager)
    }

    // MARK: - Helper Methods

    private func showSpaceEditDialog() {
        browserManager.dialogManager.showDialog(
            SpaceEditDialog(
                space: space,
                mode: .icon,
                onSave: { newName, newIcon, newProfileId in
                    do {
                        if newIcon != space.icon {
                            try browserManager.tabManager.updateSpaceIcon(
                                spaceId: space.id,
                                icon: newIcon
                            )
                        }

                        if newName != space.name {
                            try browserManager.tabManager.renameSpace(
                                spaceId: space.id,
                                newName: newName
                            )
                        }

                        // Update profile if changed
                        if newProfileId != space.profileId, let profileId = newProfileId {
                            browserManager.tabManager.assign(spaceId: space.id, toProfile: profileId)
                        }

                        browserManager.dialogManager.closeDialog()
                    } catch {
                        print("⚠️ Failed to update space \(space.id.uuidString):", error)
                    }
                },
                onCancel: {
                    browserManager.dialogManager.closeDialog()
                }
            )
        )
    }

    private func isEmoji(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) // Emoticons & pictographs
                || (scalar.value >= 0x2600 && scalar.value <= 0x26FF) // Miscellaneous symbols
                || (scalar.value >= 0x2700 && scalar.value <= 0x27BF) // Dingbats
        }
    }
}
