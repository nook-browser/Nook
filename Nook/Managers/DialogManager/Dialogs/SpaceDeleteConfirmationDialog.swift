//
//  SpaceDeleteConfirmationDialog.swift
//  Nook
//
//  Destructive confirmation for deleting a Space.
//

import SwiftUI

struct SpaceDeleteConfirmationDialog: DialogPresentable {
    let spaceName: String
    let tabsCount: Int
    let isLastSpace: Bool
    let onDelete: () -> Void
    let onCancel: () -> Void

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "trash",
            title: "Delete Space",
            subtitle: "This action cannot be undone"
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(spaceName)
                .font(NookDesign.Font.title)
                .padding(.bottom, 4)

            HStack(spacing: 8) {
                Label("\(tabsCount) tabs", systemImage: "rectangle.stack")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 6) {
                Label("All tabs in this space will be permanently deleted.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                if isLastSpace {
                    Label("You cannot delete the last remaining space.", systemImage: "hand.raised.fill")
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
                    text: "Delete Space",
                    iconName: "trash",
                    variant: isLastSpace ? .secondary : .primary,
                    isEnabled: !isLastSpace,
                    action: onDelete
                )
            ]
        )
    }
}
