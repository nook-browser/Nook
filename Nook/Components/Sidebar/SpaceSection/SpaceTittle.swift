import SwiftUI

struct SpaceTitle: View {
    @EnvironmentObject var browserManager: BrowserManager

    let space: Space
    var iconSize: CGFloat = 12

    @State private var isHovering: Bool = false
    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @State private var selectedEmoji: String = ""
    @FocusState private var nameFieldFocused: Bool
    @FocusState private var emojiFieldFocused: Bool
    @State private var isEllipsisHovering: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            // Show emoji or SF Symbol icon
            if isEmoji(space.icon) {
                Text(space.icon)
                    .font(.system(size: iconSize))
            } else {
                Image(systemName: space.icon)
                    .font(.system(size: iconSize))
            }

            if isRenaming {
                TextField("", text: $draftName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
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
                HStack(spacing: 6) {
                    Text(space.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()
            
            // Hidden TextField for capturing emoji selection
            TextField("", text: $selectedEmoji)
                .frame(width: 0, height: 0)
                .opacity(0)
                .focused($emojiFieldFocused)
                .onChange(of: selectedEmoji) { _, newValue in
                    if !newValue.isEmpty {
                        space.icon = String(newValue.last!)
                        browserManager.tabManager.persistSnapshot()
                        selectedEmoji = ""
                    }
                }

            Menu {
                // Profile assignment submenu
                Menu("Assign to Profile") {
                    // Quick info item
                    let currentName = resolvedProfileName(for: space.profileId) ?? browserManager.profileManager.profiles.first?.name ?? "Default"
                    Text("Current: \(currentName)")
                        .foregroundStyle(.secondary)
                    Divider()
                    ProfilePickerView(
                        selectedProfileId: Binding(
                            get: { space.profileId ?? browserManager.profileManager.profiles.first?.id ?? UUID() },
                            set: { assignProfile($0) }
                        ),
                        onSelect: { _ in },
                        compact: true
                    )
                    .environmentObject(browserManager)
                }
                Divider()
                Button {
                    startRenaming()
                } label: {
                    Label("Rename Space", systemImage: "pencil")
                }
                Button {
                    emojiFieldFocused = true
                    NSApp.orderFrontCharacterPalette(nil)
                } label: {
                    Label("Change Icon", systemImage: "face.smiling")
                }
                Divider()
                Button {
                    createFolder()
                } label: {
                    Label("Create Folder", systemImage: "folder.badge.plus")
                }
                Button(role: .destructive) {
                    deleteSpace()
                } label: {
                    Label("Delete Space", systemImage: "trash")
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isEllipsisHovering ? (isHovering ? AppColors.controlBackgroundActive : AppColors.controlBackgroundHoverLight) : Color.clear)
                        .frame(width: 24, height: 24)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textSecondary)
                        .opacity(isHovering ? 1.0 : 0.0)
                }
                .onHover { hovering in
                    isEllipsisHovering = hovering
                }
            }
            .buttonStyle(PlainButtonStyle())
        }
        // Match tabs' internal left/right padding so text aligns
        .padding(.horizontal, 10)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(isHovering ? AppColors.controlBackgroundHover : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onChange(of: nameFieldFocused) { _, focused in
            // When losing focus during rename, commit
            if isRenaming && !focused {
                commitRename()
            }
        }
        // Provide a right-click context menu mirroring the hover menu
        .contextMenu {
            Button {
                emojiFieldFocused = true
                NSApp.orderFrontCharacterPalette(nil)
            } label: {
                Label("Change Space Icon", systemImage: "face.smiling")
            }
            Button {
                startRenaming()
            } label: {
                Label("Rename Space", systemImage: "pencil")
            }
            Button {
                browserManager.showGradientEditor()
            } label: {
                Label("Edit Theme Color", systemImage: "paintpalette")
            }
            Menu("Set Profile") {
                let currentName = resolvedProfileName(for: space.profileId) ?? browserManager.profileManager.profiles.first?.name ?? "Default"
                Text("Current: \(currentName)")
                    .foregroundStyle(.secondary)
                Divider()
                ProfilePickerView(
                    selectedProfileId: Binding(
                        get: { space.profileId ?? browserManager.profileManager.profiles.first?.id ?? UUID() },
                        set: { assignProfile($0) }
                    ),
                    onSelect: { _ in },
                    compact: true
                )
                .environmentObject(browserManager)
            }
            Divider()
            Button {
                createFolder()
            } label : {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
            Divider()
            Button(role: .destructive) {
                deleteSpace()
            } label: {
                Label("Delete Space", systemImage: "trash")
            }
        }
    }

    // MARK: - Actions

    private func startRenaming() {
        draftName = space.name
        isRenaming = true
    }

    private func cancelRename() {
        isRenaming = false
        draftName = space.name
        nameFieldFocused = false
    }

    private func commitRename() {
        let newName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty, newName != space.name {
            browserManager.tabManager.renameSpace(
                spaceId: space.id,
                newName: newName
            )
        }
        isRenaming = false
        nameFieldFocused = false
    }

    private func deleteSpace() {
        browserManager.tabManager.removeSpace(space.id)
    }

    private func createFolder() {
        browserManager.tabManager.createFolder(for: space.id)
    }

    private func assignProfile(_ id: UUID) {
        browserManager.tabManager.assign(spaceId: space.id, toProfile: id)
    }
    
    private func resolvedProfileName(for id: UUID?) -> String? {
        guard let id else { return nil }
        return browserManager.profileManager.profiles.first(where: { $0.id == id })?.name
    }
    
    private func isEmoji(_ string: String) -> Bool {
        return string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) ||
            (scalar.value >= 0x2600 && scalar.value <= 0x26FF) ||
            (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }
}
