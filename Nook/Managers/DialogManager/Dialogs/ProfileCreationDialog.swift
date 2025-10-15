//
//  ProfileCreationDialog.swift
//  Nook
//
//  Dialog to create a new Profile.
//

import SwiftUI

struct ProfileCreationDialog: DialogPresentable {
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

    func dialogHeader() -> DialogHeader {
        DialogHeader(
            icon: "person.crop.circle.badge.plus",
            title: "Create New Profile",
            subtitle: "Switch between different browsing personas"
        )
    }

    @ViewBuilder
    func dialogContent() -> some View {
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

    func dialogFooter() -> DialogFooter {
        let trimmed = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        let canCreate = isNameAvailable(trimmed) && !trimmed.isEmpty

        return DialogFooter(
            rightButtons: [
                DialogButton(
                    text: "Cancel",
                    variant: .secondary,
                    keyboardShortcut: .escape,
                    action: onCancel
                ),
                DialogButton(
                    text: "Create Profile",
                    iconName: "plus",
                    variant: .primary,
                    keyboardShortcut: .return,
                    shadowStyle: .prominent,
                    isEnabled: canCreate,
                    action: {
                        handleCreate()
                    }
                )
            ]
        )
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
