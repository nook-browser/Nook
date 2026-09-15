import NookTabsCore
import SwiftUI

struct SpaceTitle: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState

    let spaceID: UUID
    var iconSize: CGFloat = NookDesign.Size.spaceIcon

    @State private var isHovering: Bool = false
    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @FocusState private var nameFieldFocused: Bool
    @State private var isEllipsisHovering: Bool = false

    @State private var showIconPicker = false

    /// Set by the drop zone wrapping the title while a tab hovers it over an empty pinned section.
    var isDropHovering: Bool = false

    init(spaceID: UUID, iconSize: CGFloat = NookDesign.Size.spaceIcon, isDropHovering: Bool = false) {
        self.spaceID = spaceID
        self.iconSize = iconSize
        self.isDropHovering = isDropHovering
    }

    /// Old-model initializer kept for SpaceView (T1) until it stops rendering the title.
    init(space: Space) {
        self.init(spaceID: MainActor.assumeIsolated { space.id })
    }

    var body: some View {
        if let space = tabs.space(spaceID) {
            content(space)
        }
    }

    private func content(_ space: SpaceRecord) -> some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            SpaceIconView(icon: space.icon, size: iconSize, tint: space.accentColor)
                .onTapGesture(count: 2) {
                    showIconPicker = true
                }
                .popover(isPresented: $showIconPicker) {
                    SpaceIconPicker(selected: space.icon, onPick: {
                        tabs.updateSpace(spaceID, name: nil, icon: $0, accentHex: nil)
                        showIconPicker = false
                    })
                }

            if isRenaming {
                TextField("", text: $draftName)
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.primary)
                    .textFieldStyle(PlainTextFieldStyle())
                    .autocorrectionDisabled()
                    .focused($nameFieldFocused)
                    .onAppear {
                        draftName = space.name
                        DispatchQueue.main.async {
                            nameFieldFocused = true
                        }
                    }
                    .onSubmit {
                        commitRename()
                    }
                    .onExitCommand {
                        cancelRename()
                    }
            } else {
                Text(space.name)
                    .font(NookDesign.Font.label)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) {
                        startRenaming()
                    }
            }

            Spacer()

            if isHovering {
                Menu {
                    contextMenu(space)
                        .environment(\.controlSize, .regular)
                } label: {
                    Label("Configure Space", systemImage: "ellipsis")
                        .font(.body.weight(.semibold))
                        .labelStyle(.iconOnly)
                }
                .menuStyle(.button)
                .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.rowButton, radius: NookDesign.Radius.sm))
            }
        }
        .padding(.horizontal, NookDesign.Spacing.sm)
        .frame(height: NookDesign.Size.navRow)
        .frame(maxWidth: .infinity)
        .background(isHovering || isDropHovering ? NookDesign.Surface.fill : .clear)
        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
                isHovering = hovering
            }
        }
        .onChange(of: nameFieldFocused) { _, focused in
            // When losing focus during rename, commit
            if isRenaming && !focused {
                commitRename()
            }
        }
        .contextMenu {
            contextMenu(space)
        }
    }

    private func contextMenu(_ space: SpaceRecord) -> some View {
        SpaceContextMenu(
            space: space,
            canDelete: tabs.switchableSpaces(for: windowState).count > 1,
            onEditName: { startRenaming() },
            onEditIcon: { showIconPicker = true },
            onOpenSettings: {
                SpaceEditDialog.present(spaceID: spaceID, tabs: tabs, dialogManager: browserManager.dialogManager)
            },
            onDeleteSpace: { tabs.deleteSpace(spaceID) }
        )
        .environmentObject(browserManager)
    }

    // MARK: - Actions

    private func startRenaming() {
        draftName = tabs.space(spaceID)?.name ?? ""
        isRenaming = true
    }

    private func cancelRename() {
        isRenaming = false
        draftName = tabs.space(spaceID)?.name ?? ""
        nameFieldFocused = false
    }

    private func commitRename() {
        let newName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty, newName != tabs.space(spaceID)?.name {
            tabs.updateSpace(spaceID, name: newName, icon: nil, accentHex: nil)
        }
        isRenaming = false
        nameFieldFocused = false
    }
}
