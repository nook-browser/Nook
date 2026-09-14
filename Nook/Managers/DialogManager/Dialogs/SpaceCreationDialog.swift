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
    @State private var selectedProfileId: UUID?
    @State private var accentHex: String = SpaceAccent.defaultHex

    let onCreate: (String, String, UUID?, String) -> Void
    let onCancel: () -> Void

    init(
        onCreate: @escaping (String, String, UUID?, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _spaceName = State(initialValue: "")
        _spaceIcon = State(initialValue: "")
        _selectedProfileId = State(initialValue: nil)
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
            spaceIcon: $spaceIcon,
            selectedProfileId: $selectedProfileId,
            accentHex: $accentHex
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
        onCreate(trimmedName, spaceIcon, selectedProfileId, accentHex)
    }
}

struct SpaceCreationContent: View {
    @Binding var spaceName: String
    @Binding var spaceIcon: String
    @Binding var selectedProfileId: UUID?
    @Binding var accentHex: String
    @StateObject private var emojiManager = EmojiPickerManager()
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Space Name")
                    .font(NookDesign.Font.label)
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
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.primary)

                HStack(spacing: 12) {
                    Button {
                        emojiManager.toggle()
                    } label: {
                        SpaceCreationIconPreview(icon: emojiManager.selectedEmoji)
                            .frame(width: 20, height: 20)
                            .padding(4)
                            .background(.white.opacity(0.2))
                            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                    }
                    .contentShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                    .background(EmojiPickerAnchor(manager: emojiManager))
                    .buttonStyle(PlainButtonStyle())

                    Text("Choose an icon to represent this space")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            VStack(alignment: .leading, spacing: NookDesign.Spacing.sectionGap) {
                Text("Accent")
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.primary)
                SpaceAccentPicker(selectedHex: $accentHex)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Profile")
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.primary)

                Picker(
                    currentProfileName,
                    systemImage: currentProfileIcon,
                    selection: Binding(
                        get: {
                            selectedProfileId ?? browserManager.profileManager.profiles.first?.id ?? UUID()
                        },
                        set: { newId in
                            selectedProfileId = newId
                        }
                    )
                ) {
                    ForEach(browserManager.profileManager.profiles, id: \.id) { profile in
                        Label(profile.name, systemImage: profile.icon).tag(profile.id)
                    }
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

    private var currentProfileName: String {
        guard let profileId = selectedProfileId,
              let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId })
        else {
            return browserManager.profileManager.profiles.first?.name ?? "Default"
        }
        return profile.name
    }

    private var currentProfileIcon: String {
        guard let profileId = selectedProfileId,
              let profile = browserManager.profileManager.profiles.first(where: { $0.id == profileId })
        else {
            return browserManager.profileManager.profiles.first?.icon ?? "person.circle"
        }
        return profile.icon
    }
}

private struct SpaceCreationIconPreview: View {
    let icon: String

    var body: some View {
        if icon.isEmpty {
            Image(systemName: "square.grid.2x2")
                .font(NookDesign.Font.body)
        } else if isEmoji(icon) {
            Text(icon)
                .font(NookDesign.Font.body)
        } else {
            Image(systemName: icon)
                .font(NookDesign.Font.body)
        }
    }

    private func isEmoji(_ string: String) -> Bool {
        string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF)
                || (scalar.value >= 0x2600 && scalar.value <= 0x26FF)
                || (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }
}

