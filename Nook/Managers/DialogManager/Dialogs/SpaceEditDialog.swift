//
//  SpaceEditDialog.swift
//  Nook
//
//  Created by OpenAI Codex on 22/01/2025.
//

import AppKit
import SwiftUI

struct SpaceEditDialog: DialogPresentable {
    enum Mode {
        case rename
        case icon
    }

    private let mode: Mode
    private let originalSpaceName: String
    private let originalSpaceIcon: String

    @State private var spaceName: String
    @State private var spaceIcon: String

    private let onSaveChanges: (String, String) -> Void
    private let onCancelChanges: () -> Void

    init(
        space: Space,
        mode: Mode,
        onSave: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let name = MainActor.assumeIsolated { space.name }
        let icon = MainActor.assumeIsolated { space.icon }
        self.mode = mode
        self.originalSpaceName = name
        self.originalSpaceIcon = icon
        _spaceName = State(initialValue: name)
        _spaceIcon = State(initialValue: icon)
        self.onSaveChanges = onSave
        self.onCancelChanges = onCancel
    }

    func dialogHeader() -> DialogHeader {
        let iconName: String
        let title: String

        switch mode {
        case .rename:
            iconName = "pencil"
            title = "Rename Space"
        case .icon:
            iconName = "face.smiling"
            title = "Change Space Icon"
        }

        return DialogHeader(
            icon: iconName,
            title: title,
            subtitle: originalSpaceName
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        SpaceEditContent(
            spaceName: $spaceName,
            spaceIcon: $spaceIcon,
            originalIcon: originalSpaceIcon,
            mode: mode
        )
    }

    func dialogFooter() -> DialogFooter {
        let trimmed = spaceName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName = trimmed.isEmpty ? originalSpaceName : trimmed
        let iconValue = spaceIcon.isEmpty ? originalSpaceIcon : spaceIcon

        return DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    action: onCancelChanges
                ),
                DialogButton(
                    text: "Save Changes",
                    iconName: "checkmark",
                    variant: .primary,
                    action: {
                        onSaveChanges(effectiveName, iconValue)
                    }
                )
            ]
        )
    }
}

private struct SpaceEditContent: View {
    @Binding var spaceName: String
    @Binding var spaceIcon: String

    let originalIcon: String
    let mode: SpaceEditDialog.Mode

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
                        SpaceIconView(icon: currentIcon)
                            .frame(width: 28, height: 28)
                            .padding(4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.primary.opacity(0.05))
                            )
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 8))
                    .background(EmojiPickerAnchor(manager: emojiManager))
                    .buttonStyle(PlainButtonStyle())

                    Text("Choose an emoji or symbol to represent this space")
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
            } else {
                emojiManager.selectedEmoji = originalIcon
            }
        }
        .onChange(of: emojiManager.selectedEmoji) { _, newValue in
            if !newValue.isEmpty {
                spaceIcon = newValue
            }
        }
    }

    private var currentIcon: String {
        if !spaceIcon.isEmpty {
            return spaceIcon
        }
        return originalIcon
    }
}

private struct SpaceIconView: View {
    let icon: String

    var body: some View {
        Group {
            if isEmoji(icon) {
                Text(icon)
                    .font(.system(size: 18))
            } else {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
            }
        }
        .frame(width: 20, height: 20)
    }

    private func isEmoji(_ string: String) -> Bool {
        return string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF)
                || (scalar.value >= 0x2600 && scalar.value <= 0x26FF)
                || (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }
}

