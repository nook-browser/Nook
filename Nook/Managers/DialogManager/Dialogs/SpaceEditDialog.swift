//
//  SpaceEditDialog.swift
//  Nook
//
//  Created by OpenAI Codex on 22/01/2025.
//

import AppKit
import NookTabsCore
import SwiftUI

struct SpaceEditDialog: DialogPresentable {
    enum Mode {
        case rename
        case icon
    }

    private let mode: Mode
    private let originalSpaceName: String
    private let originalSpaceIcon: String
    private let originalAccentHex: String

    @State private var spaceName: String
    @State private var spaceIcon: String
    @State private var accentHex: String

    private let onSaveChanges: (String, String, String) -> Void
    private let onCancelChanges: () -> Void

    init(
        space: SpaceRecord,
        mode: Mode,
        onSave: @escaping (String, String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.init(name: space.name, icon: space.icon, accentHex: space.accentHex,
                  mode: mode, onSave: onSave, onCancel: onCancel)
    }

    private init(
        name: String,
        icon: String,
        accentHex accent: String,
        mode: Mode,
        onSave: @escaping (String, String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.mode = mode
        self.originalSpaceName = name
        self.originalSpaceIcon = icon
        self.originalAccentHex = accent
        _spaceName = State(initialValue: name)
        _spaceIcon = State(initialValue: icon)
        _accentHex = State(initialValue: accent)
        self.onSaveChanges = onSave
        self.onCancelChanges = onCancel
    }

    /// Presents the edit dialog for a space and writes its changes through TabsController.
    @MainActor
    static func present(spaceID: UUID, tabs: TabsController, dialogManager: DialogManager) {
        guard let space = tabs.space(spaceID) else { return }
        dialogManager.showDialog(
            SpaceEditDialog(
                space: space,
                mode: .icon,
                onSave: { name, icon, accentHex in
                    guard let current = tabs.space(spaceID) else {
                        dialogManager.closeDialog()
                        return
                    }
                    tabs.updateSpace(
                        spaceID,
                        name: name != current.name ? name : nil,
                        icon: icon != current.icon ? icon : nil,
                        accentHex: accentHex.caseInsensitiveCompare(current.accentHex) != .orderedSame ? accentHex : nil
                    )
                    dialogManager.closeDialog()
                },
                onCancel: { dialogManager.closeDialog() }
            )
        )
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
                        onSaveChanges(effectiveName, iconValue, accentHex)
                    }
                )
            ]
        )
    }
}

private struct SpaceEditContent: View {
    @Binding var spaceName: String
    @Binding var spaceIcon: String
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
        }
        .padding(.horizontal, 4)
    }

    private var currentIcon: String {
        spaceIcon.isEmpty ? originalIcon : spaceIcon
    }
}

