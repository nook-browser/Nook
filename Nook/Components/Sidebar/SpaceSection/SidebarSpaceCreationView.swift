// Licensed under GPL-3.0. See LICENSE.
import SwiftUI
import NookDesign
import NookTabsCore
import NookWeb
import NookUI

/// An uncommitted space, edited in the sidebar while the window previews its theme.
struct SidebarSpaceCreationView: View {
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @State private var name = ""
    @State private var icon = "square.grid.2x2"
    @State private var profileID: UUID?
    @State private var showsTheme = false
    @State private var showsIcons = false
    @FocusState private var nameFocused: Bool


    private var theme: Binding<SpaceAppearance> {
        Binding(
            get: { windowState.spaceCreationAppearance ?? SpaceAppearance(accentHex: SpaceAccent.defaultHex) },
            set: { windowState.spaceCreationAppearance = $0 }
        )
    }

    private var profiles: [(id: UUID, name: String)] {
        var seen = Set<UUID>()
        return tabs.orderedSpaces.filter { !$0.isAgent }.compactMap { space in
            guard let id = tabs.profileIdentifier(forSpace: space.id), seen.insert(id).inserted else { return nil }
            return (id, space.name)
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: NookDesign.Spacing.lg) {
            ScrollView {
                VStack(spacing: NookDesign.Spacing.xxxl) {
                    VStack(spacing: NookDesign.Spacing.sm) {
                        Text("Create a Space")
                            .font(NookDesign.Font.titleLarge)
                        Text("Spaces help you organize your tabs and sessions.")
                            .font(NookDesign.Font.bodyRegular)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                    VStack(spacing: NookDesign.Spacing.sm) {
                        nameField
                        profileField
                        Button {
                            showsTheme = true
                        } label: {
                            Text("Change Theme")
                                .frame(maxWidth: .infinity)
                                .frame(height: NookDesign.Size.chromeControl)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .nookControlSurface(in: NookDesign.Radius.shape(NookDesign.Radius.md))
                        .popover(isPresented: $showsTheme) {
                            SpaceAppearancePicker(appearance: theme)
                        }
                    }
                    .font(NookDesign.Font.body)
                }
                .padding(.top, NookDesign.Spacing.xxxl)
                .padding(.bottom, NookDesign.Spacing.lg)
            }
            .scrollIndicators(.hidden)

            VStack(spacing: NookDesign.Spacing.sm) {
                Button(action: create) {
                    Text("Create Space")
                        .frame(maxWidth: .infinity)
                        .frame(height: NookDesign.Size.chromeControl)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(NookDesign.Surface.sidebarSelection.opacity(trimmedName.isEmpty ? 0.4 : 1))
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                .disabled(trimmedName.isEmpty)
                .accessibilityHint("Create the space with the selected profile and theme")

                Button(action: cancel) {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                        .frame(height: NookDesign.Size.chromeControl)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .nookControlSurface(in: NookDesign.Radius.shape(NookDesign.Radius.md))
            }
            .font(NookDesign.Font.body)
        }
        .padding(.horizontal, NookDesign.Spacing.sidebarInset)
        .onAppear {
            profileID = windowState.spaceID.flatMap { tabs.profileIdentifier(forSpace: $0) }
            nameFocused = true
        }
        .onExitCommand(perform: cancel)
    }

    private var nameField: some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Button {
                showsIcons = true
            } label: {
                SpaceIcon(icon)
                    .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
                    .overlay {
                        NookDesign.Radius.shape(NookDesign.Radius.sm)
                            .strokeBorder(NookDesign.Surface.dropBorderIdle, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Space icon")
            .popover(isPresented: $showsIcons) {
                SpaceIconPicker(icon: $icon, onSelect: { showsIcons = false })
            }

            TextField("Space name", text: $name)
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .onSubmit(create)
                .accessibilityIdentifier("spaceCreationName")
        }
        .padding(NookDesign.Spacing.sm)
        .nookControlSurface(in: NookDesign.Radius.shape(NookDesign.Radius.md))
    }

    private var profileField: some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            Text("Profile")
            Spacer(minLength: 0)
            Menu {
                Button("New Profile") { profileID = nil }
                Divider()
                ForEach(profiles, id: \.id) { profile in
                    Button {
                        profileID = profile.id
                    } label: {
                        if profile.id == profileID {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            } label: {
                Text(profiles.first { $0.id == profileID }?.name ?? "New Profile")
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, NookDesign.Spacing.md)
                    .frame(height: NookDesign.Size.row)
                    .background(NookDesign.Surface.fillPressed)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .accessibilityLabel("Profile")
        }
        .padding(NookDesign.Spacing.sm)
        .nookControlSurface(in: NookDesign.Radius.shape(NookDesign.Radius.md))
        .help("Spaces using the same profile share cookies and logins. Choose New Profile for separate sessions.")
    }

    private func create() {
        guard !trimmedName.isEmpty else { return }
        let appearance = theme.wrappedValue.normalized
        guard let id = tabs.createSpace(
            name: trimmedName, icon: icon, accentHex: appearance.primaryAccentHex,
            after: tabs.orderedSpaces.last?.id, appearance: appearance, profileID: profileID
        ) else { return }
        tabs.setSpace(id, in: windowState)
    }

    private func cancel() {
        withAnimation(NookDesign.Motion.standard) {
            windowState.isCreatingSpace = false
            windowState.spaceCreationAppearance = nil
        }
    }
}
