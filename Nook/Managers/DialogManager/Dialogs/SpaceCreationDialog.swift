//
//  SpaceCreationDialog.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import AppKit
import SwiftUI

struct SpaceCreationDialog: View {
    @State private var spaceName: String
    @State private var spaceIcon: String

    let onCreate: (String, String) -> Void
    let onCancel: () -> Void

    init(
        initialName: String = "",
        initialIcon: String = "",
        onCreate: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _spaceName = State(initialValue: initialName)
        _spaceIcon = State(initialValue: initialIcon)
        self.onCreate = onCreate
        self.onCancel = onCancel
    }

    var body: some View {
        StandardDialog(
            header: {
                HStack {
                    Spacer()
                    VStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(Color.accentColor.opacity(0.1))
                                .frame(width: 48, height: 48)

                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                        }

                        VStack(spacing: 4) {
                            Text("Create a New Space")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.primary)

                            Text("Organize your tabs into a new space")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    Spacer()
                }
                .padding(.top, 8)
            },
            content: {
                SpaceCreationContent(
                    spaceName: $spaceName,
                    spaceIcon: $spaceIcon
                )
            },
            footer: {
                HStack(spacing: 12) {
                    Spacer()

                    HStack(spacing: 8) {
                        NookButton.createButton(
                            text: "Cancel",
                            variant: .secondary,
                            action: onCancel,
                            keyboardShortcut: .escape
                        )

                        NookButton.createButton(
                            text: "Create Space",
                            iconName: "plus",
                            variant: .primary,
                            action: handleCreate,
                            keyboardShortcut: .return
                        )
                    }
                }
                .padding(.top, 8)
            }
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
    @StateObject private var emojiManager = EmojiPickerManager()

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

