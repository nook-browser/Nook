//
//  EditPinnedURLDialog.swift
//  Nook
//
//  Dialog to edit the home URL of a pinned tab or favorite.
//

import SwiftUI
import NookDesign

struct EditPinnedURLDialog: DialogPresentable {
    let originalURL: String
    let tabDisplayName: String

    @State private var urlText: String

    let onSave: (URL) -> Void
    let onCancel: () -> Void

    /// `url` is the tab's current home URL; `title` names the tab in the header.
    init(
        url: URL,
        title: String,
        onSave: @escaping (URL) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.originalURL = url.absoluteString
        self.tabDisplayName = title
        _urlText = State(initialValue: url.absoluteString)
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
            Text("The page this tab opens after you close it or reset it.")
                .font(NookDesign.Font.body)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(NookDesign.Font.body)

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
