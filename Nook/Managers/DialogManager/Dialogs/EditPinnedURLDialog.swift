//
//  EditPinnedURLDialog.swift
//  Nook
//
//  Dialog to edit the pinned "home" URL of a pinned tab.
//

import SwiftUI

struct EditPinnedURLDialog: DialogPresentable {
    let originalURL: String
    let tabDisplayName: String
    let tabFavicon: SwiftUI.Image

    @State private var urlText: String

    let onSave: (URL) -> Void
    let onCancel: () -> Void

    init(
        tab: Tab,
        onSave: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let url = MainActor.assumeIsolated { tab.pinnedURL?.absoluteString ?? tab.url.absoluteString }
        let name = MainActor.assumeIsolated { tab.displayName }
        let icon = MainActor.assumeIsolated { tab.favicon }
        self.originalURL = url
        self.tabDisplayName = name
        self.tabFavicon = icon
        _urlText = State(initialValue: url)
        self.onSave = onSave
        self.onCancel = onCancel
    }

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "link",
            title: "Edit Pinned URL",
            subtitle: tabDisplayName
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This is the URL that opens when you reset this pinned tab.")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(.system(size: 14, weight: .medium))

                NookTextField(
                    text: $urlText,
                    placeholder: "https://example.com",
                    variant: isValidURL ? .default : .error,
                    iconName: "globe"
                )

                if !isValidURL && !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Please enter a valid URL")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
    }

    func dialogFooter() -> DialogFooter {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = normalizedURLString != originalURL
        let canSave = changed && isValidURL && !trimmed.isEmpty

        return DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    keyboardShortcut: .escape,
                    action: onCancel
                ),
                DialogButton(
                    text: "Save",
                    iconName: "checkmark",
                    variant: .primary,
                    keyboardShortcut: .return,
                    isEnabled: canSave,
                    action: {
                        if let url = URL(string: normalizedURLString) {
                            onSave(url)
                        }
                    }
                )
            ]
        )
    }

    private var isValidURL: Bool {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return URL(string: normalizedURLString) != nil
    }

    private var normalizedURLString: String {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return trimmed
        }
        return "https://\(trimmed)"
    }
}
