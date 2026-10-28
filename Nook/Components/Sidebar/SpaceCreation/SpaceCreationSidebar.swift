// Licensed under GPL-3.0. See LICENSE.
//
//  SpaceCreationSidebar.swift
//  Nook
//
//  Create a Space, in the sidebar: name, profile and theme, with the window already showing
//  the theme. Open while `BrowserWindowState.spaceDraftTheme` is set.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookWeb
import NookUI

struct SpaceCreationSidebar: View {
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState

    @State private var name = ""
    @State private var icon = ""
    @State private var showIconPicker = false
    /// The space whose logins the new one shares; nil is a new profile.
    @State private var loginsFrom: UUID?
    @State private var showThemeEditor = false
    @FocusState private var nameFocused: Bool

    private let cardSize = CGSize(width: 44, height: 56)

    private var theme: SpaceTheme { windowState.spaceDraftTheme ?? SpaceTheme(points: [.center]) }

    private var draftTheme: Binding<SpaceTheme> {
        Binding(get: { theme }, set: { windowState.spaceDraftTheme = $0 })
    }

    var body: some View {
        VStack(spacing: NookDesign.Spacing.lg) {
            header
                .padding(.top, NookDesign.Spacing.xxxl)
                .padding(.bottom, NookDesign.Spacing.md)

            nameField
            profileRow
            themeRow

            Spacer(minLength: 0)

            VStack(spacing: NookDesign.Spacing.sm) {
                Button(action: create) {
                    Text("Create Space")
                        .font(NookDesign.Font.body)
                        .frame(maxWidth: .infinity)
                        .frame(height: NookDesign.Size.row + NookDesign.Spacing.xs)
                }
                .buttonStyle(CreateButtonStyle(fill: accent, darkText: accentRGB.luminance > 0.45))
                .keyboardShortcut(.defaultAction)

                Button("Cancel", action: cancel)
                    .buttonStyle(.plain)
                    .font(NookDesign.Font.body)
                    .foregroundStyle(.secondary)
                    .frame(height: NookDesign.Size.row)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.horizontal, NookDesign.Spacing.sidebarInset)
        .padding(.bottom, NookDesign.Spacing.lg)
        .onAppear {
            loginsFrom = windowState.spaceID.flatMap { tabs.space($0) }.flatMap { $0.isAgent ? nil : $0.id }
            nameFocused = true
        }
        .onExitCommand(perform: cancel)
    }

    // MARK: - Header

    /// Three cards fanned out in the theme's colors, the way spaces stack in the switcher.
    private var header: some View {
        VStack(spacing: NookDesign.Spacing.md) {
            ZStack {
                // Back cards in the theme's first and last color, a neutral card in front.
                let cards = [theme.points[0], .center, theme.points[theme.points.count - 1]]
                ForEach(0..<3, id: \.self) { index in
                    NookDesign.Radius.shape(NookDesign.Radius.md)
                        .fill(Color(hex: SpaceTheme.swatchColor(cards[index]).hex))
                        .overlay(NookDesign.Radius.shape(NookDesign.Radius.md).strokeBorder(NookDesign.Surface.hairline))
                        .frame(width: cardSize.width, height: cardSize.height)
                        .rotationEffect(.degrees(Double(index - 1) * 12))
                        .offset(x: CGFloat(index - 1) * NookDesign.Spacing.xl, y: index == 1 ? -NookDesign.Spacing.xs : 0)
                        .zIndex(index == 1 ? 1 : 0)
                        .nookElevation(.raised)
                }
            }
            .frame(height: cardSize.height + NookDesign.Spacing.lg)
            .animation(NookDesign.Motion.standard, value: theme.points)

            Text("Create a Space")
                .font(NookDesign.Font.titleLarge)
            Text("Organize your tabs into a new space")
                .font(NookDesign.Font.bodyRegular)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Fields

    private var nameField: some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            Button { showIconPicker = true } label: {
                SpaceIcon(icon)
                    .foregroundStyle(icon.isEmpty ? Color(hex: SpaceTheme.accentColor(theme.points[0]).hex) : .secondary)
                    .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Space icon")
            .popover(isPresented: $showIconPicker) {
                SpaceIconPicker(icon: $icon, onSelect: { showIconPicker = false })
            }
            TextField("Space name…", text: $name)
                .textFieldStyle(.plain)
                .focused($nameFocused)
                .onSubmit(create)
        }
        .font(NookDesign.Font.body)
        .padding(.horizontal, NookDesign.Spacing.rowPadding)
        .frame(height: NookDesign.Size.row + NookDesign.Spacing.xs)
        .nookControlSurface(in: NookDesign.Radius.shape(NookDesign.Radius.md))
    }

    private var profileRow: some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            Image(systemName: "person.2")
                .foregroundStyle(.secondary)
            Text("Profile")
            Spacer(minLength: 0)
            Menu {
                ForEach(tabs.profiles) { profile in
                    Button(profile.name) { loginsFrom = profile.spaceIDs.first }
                }
                Divider()
                Button("New Profile") { loginsFrom = nil }
            } label: {
                Text(profileName)
            }
            .menuStyle(.button)
            .buttonStyle(RectNavButtonStyle())
            .fixedSize()
        }
        .font(NookDesign.Font.body)
        .padding(.horizontal, NookDesign.Spacing.rowPadding)
        .frame(height: NookDesign.Size.row + NookDesign.Spacing.xs)
        .nookControlSurface(in: NookDesign.Radius.shape(NookDesign.Radius.md))
    }

    private var profileName: String {
        guard let loginsFrom else { return "New Profile" }
        return tabs.profiles.first { $0.spaceIDs.contains(loginsFrom) }?.name ?? "New Profile"
    }

    private var themeRow: some View {
        Button {
            showThemeEditor = true
        } label: {
            HStack(spacing: NookDesign.Spacing.sm) {
                Image(systemName: "paintbrush.pointed")
                    .foregroundStyle(.secondary)
                Text("Choose a Theme")
                Spacer(minLength: 0)
                Circle()
                    .fill(accent)
                    .frame(width: NookDesign.Spacing.lg, height: NookDesign.Spacing.lg)
            }
            .font(NookDesign.Font.body)
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(height: NookDesign.Size.row + NookDesign.Spacing.xs)
            .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        }
        .buttonStyle(.plain)
        .nookControlSurface(in: NookDesign.Radius.shape(NookDesign.Radius.md))
        .popover(isPresented: $showThemeEditor, arrowEdge: .trailing) {
            SpaceThemePanel(theme: draftTheme)
        }
    }

    private var accentRGB: ThemeRGB { SpaceTheme.accentColor(theme.points[0]) }
    private var accent: Color { Color(hex: accentRGB.hex) }

    // MARK: - Actions

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let theme = self.theme
        guard let spaceID = tabs.createSpace(
            name: trimmed.isEmpty ? "New Space" : trimmed,
            icon: icon,
            accentHex: SpaceTheme.accentColor(theme.points[0]).hex,
            after: tabs.orderedSpaces.last { !$0.isAgent }?.id,
            sharingLoginsWith: loginsFrom
        ) else { return }
        tabs.setTheme(theme, forSpace: spaceID)
        withAnimation(NookDesign.Motion.standard) {
            windowState.spaceDraftTheme = nil
            tabs.setSpace(spaceID, in: windowState)
        }
    }

    private func cancel() {
        withAnimation(NookDesign.Motion.standard) { windowState.spaceDraftTheme = nil }
    }
}

private struct CreateButtonStyle: ButtonStyle {
    let fill: Color
    let darkText: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(darkText ? Color.black : Color.white)
            .background(fill.opacity(configuration.isPressed ? 0.85 : 1), in: NookDesign.Radius.shape(NookDesign.Radius.md))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(NookDesign.Motion.quick, value: configuration.isPressed)
    }
}
