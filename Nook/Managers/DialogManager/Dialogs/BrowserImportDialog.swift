//
//  BrowserImportDialog.swift
//  Nook
//
//  Created by Maciek Bagiński on 14/10/2025.
//
//

import AppKit
import SwiftUI

struct BrowserImportDialog: DialogPresentable {
    @EnvironmentObject private var browserManager: BrowserManager
    let onCancel: () -> Void

    init(
        onCancel: @escaping () -> Void
    ) {
        self.onCancel = onCancel
    }

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "square.and.arrow.down.on.square",
            title: "Import your essentials",
            subtitle: "We can import your spaces, tabs and folders from Arc."
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        EmptyView()
    }

    func dialogFooter() -> DialogFooter {
        DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Maybe later",
                    variant: .secondary,
                    keyboardShortcut: .escape,
                    action: onCancel
                ),
                DialogButton(
                    text: "Import from Arc",
                    variant: .primary,
                    keyboardShortcut: .return,
                    action: handleCreate
                )
            ]
        )
    }

    private func handleCreate() {
        onCancel()
    }
}

