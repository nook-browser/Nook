//
//  ProfileCreationDialog.swift
//  Nook
//
//  Dialog to create a new Profile.
//

import SwiftUI

struct ProfileCreationDialog: View {
    @State private var profileName: String
    @State private var profileIcon: String

    var isNameAvailable: (String) -> Bool
    let onCreate: (String, String) -> Void
    let onCancel: () -> Void

    init(
        initialName: String = "",
        initialIcon: String = "person.crop.circle",
        isNameAvailable: @escaping (String) -> Bool = { _ in true },
        onCreate: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        _profileName = State(initialValue: initialName)
        _profileIcon = State(initialValue: initialIcon)
        self.isNameAvailable = isNameAvailable
        self.onCreate = onCreate
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
        HStack(spacing: 0) {
            VStack(spacing: 18) {
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
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: 20) {
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
    }

    @ViewBuilder
    private var footer: some View {
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
                    text: "Create Profile",
                    iconName: "plus",
                    variant: .primary,
                    action: handleCreate,
                    keyboardShortcut: .return,
                    animationType: .custom("checkmark"),
                    shadowStyle: .subtle,
                    customColors: NookButton.CustomColors(
                        backgroundColor: Color.accentColor,
                        textColor: Color.primary,
                        borderColor: Color.white,
                        shadowColor: Color.gray,
                        shadowOffset: CGSize(width: 0, height: 5)
                    )
                )
                .disabled(!isNameAvailable(profileName.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }
        .padding(.top, 8)
    }

    private func handleCreate() {
        let trimmedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveName = trimmedName.isEmpty ? "New Profile" : trimmedName
        onCreate(effectiveName, profileIcon)
    }
}

struct SimpleIconPicker: View {
    @Binding var selectedIcon: String

    private let keyIcons: [String] = [
        "person.crop.circle",
        "person.crop.circle.fill",
        "person.2.circle",
        "briefcase",
        "house",
        "sparkles"
    ]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 6)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(keyIcons, id: \.self) { icon in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selectedIcon = icon
                    }
                } label: {
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

#if DEBUG
#Preview("Profile Creation Dialog") {
    ProfileCreationDialog(
        initialName: "Guest",
        initialIcon: "person.crop.circle",
        isNameAvailable: { !$0.isEmpty },
        onCreate: { _, _ in },
        onCancel: {}
    )
    .padding()
}
#endif
