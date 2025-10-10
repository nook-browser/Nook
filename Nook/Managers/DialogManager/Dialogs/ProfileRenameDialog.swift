//
//  ProfileRenameDialog.swift
//  Nook
//
//  Dialog to edit existing Profile name and icon.
//

import SwiftUI

struct ProfileRenameDialog: View {
    let originalProfileName: String
    let originalProfileIcon: String

    @State private var profileName: String
    @State private var profileIcon: String

    var isNameAvailable: (String) -> Bool
    let onSave: (String, String) -> Void
    let onCancel: () -> Void

    init(
        originalProfile: Profile,
        isNameAvailable: @escaping (String) -> Bool,
        onSave: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let name = MainActor.assumeIsolated { originalProfile.name }
        let icon = MainActor.assumeIsolated { originalProfile.icon }
        self.originalProfileName = name
        self.originalProfileIcon = icon
        _profileName = State(initialValue: name)
        _profileIcon = State(initialValue: icon)
        self.isNameAvailable = isNameAvailable
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        StandardDialog(
            header: { header },
            content: { content },
            footer: { footer }
        )
    }

    @ViewBuilder
    private var header: some View {
        DialogHeader(
            icon: "square.and.pencil",
            title: "Rename Profile",
            subtitle: originalProfileName
        )
    }

    @ViewBuilder
    private var content: some View {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDuplicate = trimmed.lowercased() != originalProfileName.lowercased() && !isNameAvailable(trimmed)

        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("New Name")
                    .font(.system(size: 14, weight: .medium))

                NookTextField(
                    text: $profileName,
                    placeholder: "Enter new name",
                    variant: isDuplicate ? .error : .default,
                    iconName: "character.cursor.ibeam"
                )

                if isDuplicate {
                    Text("A profile with this name already exists.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Profile Icon")
                    .font(.system(size: 14, weight: .medium))

                SimpleIconPicker(selectedIcon: $profileIcon)
                    .frame(maxHeight: 200)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = trimmed != originalProfileName || profileIcon != originalProfileIcon
        let isValid = !trimmed.isEmpty && (trimmed.lowercased() == originalProfileName.lowercased() || isNameAvailable(trimmed))
        let canSave = changed && isValid

        DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    action: onCancel
                ),
                DialogButton(
                    text: "Save Settings",
                    iconName: "checkmark",
                    variant: .primary,
                    action: {
                        if canSave {
                            onSave(trimmed, profileIcon)
                        }
                    }
                )
            ]
        )
    }
}
