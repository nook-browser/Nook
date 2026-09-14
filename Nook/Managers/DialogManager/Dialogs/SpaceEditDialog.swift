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
    private let originalProfileId: UUID?
    private let originalAccentHex: String

    @State private var spaceName: String
    @State private var spaceIcon: String
    @State private var selectedProfileId: UUID?
    @State private var accentHex: String

    private let onSaveChanges: (String, String, UUID?, String) -> Void
    private let onCancelChanges: () -> Void

    init(
        space: Space,
        mode: Mode,
        onSave: @escaping (String, String, UUID?, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let name = MainActor.assumeIsolated { space.name }
        let icon = MainActor.assumeIsolated { space.icon }
        let profileId = MainActor.assumeIsolated { space.profileId }
        let accent = MainActor.assumeIsolated { space.accentHex }
        self.mode = mode
        self.originalSpaceName = name
        self.originalSpaceIcon = icon
        self.originalProfileId = profileId
        self.originalAccentHex = accent
        _spaceName = State(initialValue: name)
        _spaceIcon = State(initialValue: icon)
        _selectedProfileId = State(initialValue: profileId)
        _accentHex = State(initialValue: accent)
        self.onSaveChanges = onSave
        self.onCancelChanges = onCancel
    }

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "GEAR",
            title: "Space Settings",
            subtitle: originalSpaceName
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
        SpaceEditContent(
            spaceName: $spaceName,
            spaceIcon: $spaceIcon,
            selectedProfileId: $selectedProfileId,
            accentHex: $accentHex,
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
                        onSaveChanges(effectiveName, iconValue, selectedProfileId, accentHex)
                    }
                )
            ]
        )
    }
}

private struct SpaceEditContent: View {
    @Binding var spaceName: String
    @Binding var spaceIcon: String
    @Binding var selectedProfileId: UUID?
    @Binding var accentHex: String

    let originalIcon: String
    let mode: SpaceEditDialog.Mode

    @State private var showIconPicker = false
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
                        showIconPicker = true
                    } label: {
                        SpaceIconView(icon: currentIcon, size: NookDesign.Size.iconButton - NookDesign.Spacing.md, tint: .primary)
                            .padding(4)
                            .background(
                                NookDesign.Radius.shape(NookDesign.Radius.md)
                                    .fill(Color.primary.opacity(0.05))
                            )
                    }
                    .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                    .buttonStyle(PlainButtonStyle())
                    .popover(isPresented: $showIconPicker) {
                        SpaceIconPicker(selected: currentIcon, onPick: {
                            spaceIcon = $0
                            showIconPicker = false
                        })
                    }

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
    }

    private var currentIcon: String {
        if !spaceIcon.isEmpty {
            return spaceIcon
        }
        return originalIcon
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

