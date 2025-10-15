//
//  ProfileDeleteConfirmationDialog.swift
//  Nook
//
//  Destructive confirmation for deleting a Profile.
//

import SwiftUI

struct ProfileDeleteConfirmationDialog: DialogPresentable {
    let profileName: String
    let profileIcon: String
    let spacesCount: Int
    let tabsCount: Int
    let isLastProfile: Bool
    let onDelete: () -> Void
    let onCancel: () -> Void

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "trash",
            title: "Delete Profile",
            subtitle: "This action cannot be undone"
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: profileIcon)
                    .font(.system(size: 20, weight: .semibold))
                Text(profileName)
                    .font(.system(size: 16, weight: .semibold))
            }
            .padding(.bottom, 4)

            HStack(spacing: 8) {
                Label("\(spacesCount) spaces", systemImage: "rectangle.3.group")
                Text("•")
                Label("\(tabsCount) tabs", systemImage: "rectangle.stack")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 6) {
                Label("All associated tabs and spaces will be unlinked.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                Text("Website data is currently shared across profiles and will not be deleted automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if isLastProfile {
                    Label("You cannot delete the last remaining profile.", systemImage: "hand.raised.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
    }

    func dialogFooter() -> DialogFooter {
        DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    action: onCancel
                ),
                DialogButton(
                    text: "Delete Profile",
                    iconName: "trash",
                    variant: isLastProfile ? .secondary : .primary,
                    isEnabled: !isLastProfile,
                    action: onDelete
                )
            ]
        )
    }
}
