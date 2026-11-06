// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserImportDialog.swift
//  Nook
//
//  Created by Maciek Bagiński on 14/10/2025.
//
//

import AppKit
import NookDesign
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
        Text("Brings over spaces, tabs, folders, favorites, extensions, Air Traffic Control rules and the last 30 days of archived tabs. Passwords and history stay in Arc.")
            .font(NookDesign.Font.body)
            .foregroundStyle(.secondary)
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
        let manager = browserManager
        onCancel()
        if manager.nookSettings?.didImportFromArc == true {
            let again = NSAlert()
            again.messageText = "Import from Arc again?"
            again.informativeText = "Spaces from your last import stay, so you'll end up with two of each."
            again.addButton(withTitle: "Import Again")
            again.addButton(withTitle: "Cancel")
            guard again.runModal() == .alertFirstButtonReturn else { return }
        }
        Task {
            let alert = NSAlert()
            if let summary = await manager.importArcData() {
                alert.messageText = "Imported from Arc"
                alert.informativeText = summary
            } else {
                alert.messageText = "Couldn't import from Arc"
                alert.informativeText = "Nook didn't find any Arc spaces on this Mac."
            }
            alert.runModal()
        }
    }
}

