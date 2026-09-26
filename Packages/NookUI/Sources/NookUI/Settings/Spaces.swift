// Licensed under GPL-3.0. See LICENSE.
//
//  Spaces.swift
//  Nook
//
//  Spaces settings. A space is a login context: it owns its cookies and site data, so this is
//  also where that data is inspected and cleared.
//

import NookTabsCore
import SwiftUI
import NookDesign
import NookWeb

public struct SpacesSettingsView: View {
    @Environment(TabsController.self) private var tabs
    @Environment(\.tabActions) private var actions

    /// Cookie and record counts per space, filled in as each store answers.
    @State private var stats: [UUID: String] = [:]
    @State private var showAccentPickerFor: UUID?

    public init() {}

    public var body: some View {
        Form {
            Section {
                ForEach(tabs.orderedSpaces) { space in
                    row(space)
                }
            } header: {
                VStack(alignment: .leading, spacing: NookDesign.Spacing.sm) {
                    HStack {
                        Text("Spaces")
                        Spacer()
                        Button("New Space…", systemImage: "plus", action: showCreateDialog)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    Text("Each space keeps its own cookies and logins. Sites you sign into in one space stay signed out in the others.")
                        .font(NookDesign.Font.secondary)
                        .foregroundStyle(.secondary)
                }
                .textCase(nil)
            }
        }
        .formStyle(.grouped)
        .task(id: tabs.orderedSpaces.count) { await refreshStats() }
    }

    @ViewBuilder
    private func row(_ space: SpaceRecord) -> some View {
        HStack(spacing: NookDesign.Spacing.md) {
            Button {
                showAccentPickerFor = space.id
            } label: {
                Circle()
                    .fill(space.accentColor)
                    .frame(width: NookDesign.Size.iconButton, height: NookDesign.Size.iconButton)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Space color")
            .accessibilityLabel("Space color for \(space.name)")
            .popover(isPresented: Binding(
                get: { showAccentPickerFor == space.id },
                set: { if !$0 { showAccentPickerFor = nil } }
            )) {
                SpaceAccentPicker(selectedHex: Binding(
                    get: { space.accentHex },
                    set: { tabs.updateSpace(space.id, name: nil, icon: nil, accentHex: $0) }
                ))
                .padding(NookDesign.Spacing.lg)
            }

            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                TextField("Space name", text: Binding(
                    get: { space.name },
                    set: { tabs.updateSpace(space.id, name: $0, icon: nil, accentHex: nil) }
                ))
                .textFieldStyle(.plain)
                .labelsHidden()
                Text(stats[space.id] ?? "Checking…")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Menu {
#if os(macOS)
                Button("Window Tint…", systemImage: "circle.lefthalf.filled") {
                    actions?.presentWindowTint(for: space.id)
                }
                Divider()
#endif
                Button("Clear Website Data", systemImage: "trash") {
                    Task { await clearData(space) }
                }
                if tabs.orderedSpaces.count > 1 {
                    Divider()
                    Button("Delete Space…", systemImage: "trash", role: .destructive) {
                        showDeleteDialog(space)
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabel("More options for \(space.name)")
            .fixedSize()
        }
    }

    // MARK: - Data

    private func refreshStats() async {
        for space in tabs.orderedSpaces {
            guard let profile = tabs.profile(forSpace: space.id) else { continue }
            await profile.refreshDataStoreStats()
            stats[space.id] = profile.websiteDataSummary
        }
    }

    private func clearData(_ space: SpaceRecord) async {
        guard let profile = tabs.profile(forSpace: space.id) else { return }
        await profile.clearAllData()
        stats[space.id] = profile.websiteDataSummary
    }

    // MARK: - Dialogs

    private func showCreateDialog() {
        actions?.presentSpaceCreation { name, accentHex in
            tabs.createSpace(
                name: name.isEmpty ? "New Space" : name,
                icon: "square.grid.2x2",
                accentHex: accentHex,
                after: tabs.orderedSpaces.last?.id
            )
        }
    }

    private func showDeleteDialog(_ space: SpaceRecord) {
        actions?.confirmSpaceDeletion(
            spaceName: space.name,
            tabCount: tabs.tabCount(inSpace: space.id),
            isLastSpace: tabs.orderedSpaces.count <= 1,
            onDelete: { tabs.deleteSpace(space.id) }
        )
    }
}

#if os(macOS)
public struct WindowTintSettingsPanel: View {
    @Environment(TabsController.self) private var tabs

    private let spaceID: UUID
    private let onClose: () -> Void

    public init(spaceID: UUID, onClose: @escaping () -> Void) {
        self.spaceID = spaceID
        self.onClose = onClose
    }

    public var body: some View {
        if let space = tabs.space(spaceID) {
            NookPanel {
                VStack(alignment: .leading, spacing: NookDesign.Spacing.xl) {
                    Text("Window Tint")
                    Text(space.name)

                    Toggle("Tint window", isOn: Binding(
                        get: { space.windowTintHex != nil },
                        set: { isEnabled in
                            tabs.updateSpace(
                                space.id,
                                name: nil,
                                icon: nil,
                                accentHex: nil,
                                windowTintHex: .some(isEnabled ? (space.windowTintHex ?? space.accentHex) : nil)
                            )
                        }
                    ))

                    if space.windowTintHex != nil {
                        SpaceAccentPicker(selectedHex: Binding(
                            get: { space.windowTintHex ?? space.accentHex },
                            set: {
                                tabs.updateSpace(
                                    space.id,
                                    name: nil,
                                    icon: nil,
                                    accentHex: nil,
                                    windowTintHex: .some($0)
                                )
                            }
                        ))
                    }

                    Button("Done", action: onClose)
                }
            }
            .onExitCommand(perform: onClose)
        }
    }
}
#endif
