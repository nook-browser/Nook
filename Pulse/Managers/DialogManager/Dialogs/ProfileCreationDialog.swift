//
//  ProfileCreationDialog.swift
//  Pulse
//
//  Dialog to create a new Profile.
//

import SwiftUI

struct ProfileCreationDialog: DialogProtocol {
    @Binding var profileName: String
    @Binding var profileIcon: String
    var isNameAvailable: (String) -> Bool = { _ in true }
    let onSave: () -> Void
    let onCancel: () -> Void

    init(
        profileName: Binding<String>,
        profileIcon: Binding<String>,
        isNameAvailable: @escaping (String) -> Bool = { _ in true },
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._profileName = profileName
        self._profileIcon = profileIcon
        self.isNameAvailable = isNameAvailable
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var header: AnyView {
        AnyView(
            DialogHeader(
                icon: "person.crop.circle.badge.plus",
                title: "Create New Profile",
                subtitle: "Switch between different browsing personas"
            )
        )
    }

    var content: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile Name")
                        .font(.system(size: 14, weight: .medium))
                    PulseTextField(text: $profileName, placeholder: "Enter profile name", variant: .default, iconName: "character.cursor.ibeam")
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile Icon")
                        .font(.system(size: 14, weight: .medium))
                    IconPickerView(selectedIcon: $profileIcon)
                        .frame(maxHeight: 200)
                }
            }
        )
    }

    var footer: AnyView {
        return AnyView(
            DialogFooter(
                rightButtons: [
                    DialogButton(
                        text: "Cancel",
                        variant: .secondary,
                        action: onCancel
                    ),
                    DialogButton(
                        text: "Create Profile",
                        iconName: "plus",
                        // Always enable; onSave validates and applies defaults
                        variant: .primary,
                        action: onSave
                    )
                ]
            )
        )
    }
}
