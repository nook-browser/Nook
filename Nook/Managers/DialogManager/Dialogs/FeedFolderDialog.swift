// Licensed under GPL-3.0. See LICENSE.
//
//  FeedFolderDialog.swift
//  Nook
//
//  Asks for the feed a new live feed folder follows.
//

import SwiftUI
import NookDesign

struct FeedFolderDialog: DialogPresentable {
    @State private var urlText = ""

    let onAdd: (URL) -> Void
    let onCancel: () -> Void

    func dialogHeader() -> DialogHeader {
        DialogHeader(icon: "dot.radiowaves.up.forward", title: "New Feed Folder")
    }

    @ViewBuilder
    func dialogContent() -> some View {
        NookTextField(
            text: $urlText,
            placeholder: "Feed URL",
            variant: .default,
            iconName: "link"
        )
    }

    func dialogFooter() -> DialogFooter {
        DialogFooter(
            rightButtons: [
                DialogButton(text: "Cancel", variant: .secondary, keyboardShortcut: .escape, action: onCancel),
                DialogButton(
                    text: "Add",
                    iconName: "plus",
                    variant: .primary,
                    keyboardShortcut: .return,
                    isEnabled: feedURL != nil,
                    action: { if let feedURL { onAdd(feedURL) } }
                )
            ]
        )
    }

    /// http(s) with a host; a bare host gets https.
    private var feedURL: URL? {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let string = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: string), url.scheme == "http" || url.scheme == "https",
              let host = url.host, host.contains(".") || host == "localhost" else { return nil }
        return url
    }
}
