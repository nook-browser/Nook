//
//  ProfileRenameDialog.swift
//  Nook
//
//  Dialog to edit existing Profile name and icon.
//

import SwiftUI
import Observation

struct ProfileRenameDialog: DialogProtocol {
    let originalProfileName: String
    let originalProfileIcon: String
    @Binding var profileName: String
    @Binding var profileIcon: String
    var isNameAvailable: (String) -> Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    init(
        originalProfile: Profile,
        profileName: Binding<String>,
        profileIcon: Binding<String>,
        isNameAvailable: @escaping (String) -> Bool,
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        // Access MainActor-isolated properties using MainActor.assumeIsolated
        self.originalProfileName = MainActor.assumeIsolated { originalProfile.name }
        self.originalProfileIcon = MainActor.assumeIsolated { originalProfile.icon }
        self._profileName = profileName
        self._profileIcon = profileIcon
        self.isNameAvailable = isNameAvailable
        self.onSave = onSave
        self.onCancel = onCancel
    }

    func header() -> some View {
        DialogHeader(
            icon: "square.and.pencil",
            title: "Rename Profile",
            subtitle: originalProfileName
        )
    }

    func content() -> some View {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDuplicate = trimmed.lowercased() != originalProfileName.lowercased() && !isNameAvailable(trimmed)
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("New Name")
                    .font(.system(size: 14, weight: .medium))
                NookTextField(text: $profileName, placeholder: "Enter new name", variant: isDuplicate ? .error : .default, iconName: "character.cursor.ibeam")
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

    func footer() -> some View {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let changed = trimmed != originalProfileName || profileIcon != originalProfileIcon
        let isValid = !trimmed.isEmpty && (trimmed.lowercased() == originalProfileName.lowercased() || isNameAvailable(trimmed))
        let canSave = changed && isValid
        return DialogFooter(
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
                    action: { if canSave { onSave() } }
                )
            ]
        )
    }
}
