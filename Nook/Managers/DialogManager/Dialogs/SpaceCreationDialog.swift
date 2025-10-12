//
//  SpaceCreationDialog.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import AppKit
import SwiftUI

struct SpaceCreationDialog: DialogPresentable {
    @State private var spaceName: String
    @State private var spaceIcon: String

    let onCreate: (String, String) -> Void
    let onCancel: () -> Void

    init(
        onCreate: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _spaceName = State(initialValue: "")
        _spaceIcon = State(initialValue: "")
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "folder.badge.plus",
            title: "Create a New Space",
            subtitle: "Organize your tabs into a new space"
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        SpaceCreationContent(
            spaceName: $spaceName,
            spaceIcon: $spaceIcon
        )
    }

    func dialogFooter() -> DialogFooter {
        DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    keyboardShortcut: .escape,
                    action: onCancel
                ),
                DialogButton(
                    text: "Create Space",
                    iconName: "plus",
                    variant: .primary,
                    keyboardShortcut: .return,
                    action: handleCreate
                )
            ]
        )
    }

    private func handleCreate() {
        let trimmedName = spaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        onCreate(trimmedName, spaceIcon)
    }
}

struct SpaceCreationContent: View {
    @Binding var spaceName: String
    @Binding var spaceIcon: String
    @State private var emojiManager = EmojiPickerManager()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Space Name")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                NookTextField(
                    text: $spaceName,
                    placeholder: "Enter space name",
                    variant: .default,
                    iconName: "textformat"
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Space Icon")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    Button {
                        emojiManager.toggle()
                    } label: {
                        Text(
                            emojiManager.selectedEmoji.isEmpty
                                ? "✨" : emojiManager.selectedEmoji
                        )
                        .font(.system(size: 14))
                        .frame(width: 20, height: 20)
                        .padding(4)
                        .background(.white.opacity(0.2))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 6))
                    .background(EmojiPickerAnchor(manager: emojiManager))
                    .buttonStyle(PlainButtonStyle())

                    Text("Choose an emoji to represent this space")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(.horizontal, 4)
        .onAppear {
            if !spaceIcon.isEmpty {
                emojiManager.selectedEmoji = spaceIcon
            }
        }
        .onChange(of: emojiManager.selectedEmoji) { _, newValue in
            spaceIcon = newValue
        }
    }
}

