//
//  ProfileCreationDialog.swift
//  Nook
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
    let onClose: () -> Void

    @State private var isCreating: Bool = false {
        didSet {
            print("📊 ProfileCreationDialog isCreating changed to: \(isCreating)")
        }
    }

    init(
        profileName: Binding<String>,
        profileIcon: Binding<String>,
        isNameAvailable: @escaping (String) -> Bool = { _ in true },
        onSave: @escaping () -> Void,
        onCancel: @escaping () -> Void,
        onClose: @escaping () -> Void = {}
    ) {
        _profileName = profileName
        _profileIcon = profileIcon
        self.isNameAvailable = isNameAvailable
        self.onSave = onSave
        self.onCancel = onCancel
        self.onClose = onClose
    }

    var header: AnyView {
        AnyView(
            HStack(spacing: 0) {
                VStack(spacing: 18) {
                    // Icon with modern styling
                    ZStack {
                        Circle()
                            .fill(Color.accentColor.opacity(0.1))
                            .frame(width: 48, height: 48)

                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                    }

                    VStack(spacing: 4) {
                        Text("Create New Profile")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("Switch between different browsing personas")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding(.top, 8)
            })
    }

    var content: AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 20) {
                // Profile Name Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Profile Name")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    NookTextField(
                        text: $profileName,
                        placeholder: "Enter profile name",
                        variant: .default,
                        iconName: "person"
                    )
                }

                // Profile Icon Section
                VStack(alignment: .leading, spacing: 10) {
                    Text("Profile Icon")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose an icon to represent this profile")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)

                        SimpleIconPicker(selectedIcon: $profileIcon)
                    }
                }
            }
            .padding(.horizontal, 4)
        )
    }

    var footer: AnyView {
        AnyView(
            HStack(spacing: 12) {
                Spacer()

                HStack(spacing: 8) {
                    NookButton.createButton(
                        text: "Cancel",
                        variant: .secondary,
                        action: onCancel,
                        keyboardShortcut: .escape
                    )

                    NookButton(
                        text: "Create Profile  ",
                        iconName: "plus",
                        variant: .primary,
                        action: {
                            print("Custom button tapped")
                            handleSave()
                        },
                        keyboardShortcut: .space,
                        animationType: .custom("checkmark"),
                        shadowStyle: .subtle,
                        customColors: NookButton.CustomColors(backgroundColor: Color.accentColor, textColor: Color.primary, borderColor: Color.white, shadowColor: Color.gray, shadowOffset: CGSize(width: 0, height: 5)),
                    )
                }
            }
            .padding(.top, 8)
        )
    }

    private func handleSave() {
        print("🚀 ProfileCreationDialog handleSave called")

        // Call the original onSave immediately
        print("📞 Calling onSave")
        onSave()

        // Wait for 1 second then close the dialog
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            print("🚪 Closing dialog")
            onClose()
        }
    }
}

// MARK: - Simple Icon Picker

struct SimpleIconPicker: View {
    @Binding var selectedIcon: String

    // 8 key icons for profiles
    private let keyIcons = [
        "person.crop.circle",
        "person.crop.circle.fill",
        "person.2.circle",
        "briefcase",
        "house",
        "sparkles",
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(keyIcons, id: \.self) { icon in
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedIcon = icon
                    }
                }) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(selectedIcon == icon ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.05))
                            .frame(width: 48, height: 48)

                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                selectedIcon == icon ? Color.accentColor : Color.primary.opacity(0.1),
                                lineWidth: selectedIcon == icon ? 2 : 1
                            )
                            .frame(width: 48, height: 48)

                        Image(systemName: icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(selectedIcon == icon ? Color.accentColor : Color.primary)
                            .scaleEffect(selectedIcon == icon ? 1.1 : 1.0)
                    }
                }
                .buttonStyle(.plain)
                .alwaysArrowCursor()
                .help(icon)
                .accessibilityLabel(icon)
                .accessibilityAddTraits(selectedIcon == icon ? .isSelected : [])
                .animation(.easeInOut(duration: 0.15), value: selectedIcon == icon)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Icon Picker")
    }
}

struct DialogPreviewContainer: View {
    let dialog: ProfileCreationDialog
    var body: some View {
        VStack(spacing: 24) {
            dialog.header
            dialog.content
            dialog.footer
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.windowBackgroundColor))
                .shadow(radius: 8, y: 4)
        )
        .frame(maxWidth: 400)
    }
}

#Preview("Profile Creation Dialog") {
    struct PreviewHost: View {
        @State private var profileName: String = "Guest"
        @State private var profileIcon: String = "person.crop.circle"
        @State private var presented: Bool = true

        var body: some View {
            if presented {
                DialogPreviewContainer(
                    dialog: ProfileCreationDialog(
                        profileName: $profileName,
                        profileIcon: $profileIcon,
                        isNameAvailable: { name in !name.isEmpty },
                        onSave: { presented = false },
                        onCancel: { presented = false }
                    )
                )
            }
        }
    }
    return PreviewHost()
}

#Preview("NookButton Examples") {
    struct ButtonPreview: View {
        var body: some View {
            VStack(spacing: 20) {
                NookButton.animatedCreateButton(
                    text: "Create Profile",
                    iconName: "plus",
                    variant: .primary,
                    action: {
                        print("Create button tapped")
                    }
                )

                NookButton.createButton(
                    text: "Cancel",
                    variant: .secondary,
                    action: {
                        print("Cancel button tapped")
                    }
                )

                NookButton(
                    text: "Custom Animation",
                    iconName: "star",
                    variant: .primary,
                    action: {
                        print("Custom button tapped")
                    },
                    animationType: .custom("star.fill"),
                    shadowStyle: .subtle
                )
            }
            .padding()
        }
    }

    return ButtonPreview()
}
