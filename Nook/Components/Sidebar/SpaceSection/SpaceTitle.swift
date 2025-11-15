import SwiftUI

struct SpaceTitle: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.colorScheme) var colorScheme

    let space: Space
    var iconSize: CGFloat = 12

    @State private var isHovering: Bool = false
    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @State private var selectedEmoji: String = ""
    @FocusState private var nameFieldFocused: Bool
    @FocusState private var emojiFieldFocused: Bool
    @State private var isEllipsisHovering: Bool = false
    @State private var isDropHovering: Bool = false
    @State private var dropDraggedItem: UUID?
    
    @StateObject private var emojiManager = EmojiPickerManager()

    var body: some View {
        HStack(spacing: 6) {
            // Show emoji or SF Symbol icon
            ZStack {
                // Hidden TextField for capturing emoji selection
                TextField("", text: $selectedEmoji)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .focused($emojiFieldFocused)
                    .onChange(of: selectedEmoji) { _, newValue in
                        if !newValue.isEmpty {
                            // Safely unwrap the last character
                            guard let lastChar = newValue.last else { return }
                            space.icon = String(lastChar)
                            browserManager.tabManager.persistSnapshot()
                            selectedEmoji = ""
                        }
                    }

                if isEmoji(space.icon) {
                    Text(space.icon)
                        .font(.system(size: iconSize))
                        .background(EmojiPickerAnchor(manager: emojiManager))
                        .onTapGesture(count: 2) {
                            emojiManager.toggle()
                        }
                        .onChange(of: emojiManager.selectedEmoji) { _, newValue in
                            print(newValue)
                            space.icon = newValue
                            browserManager.tabManager.persistSnapshot()
                         }
                } else {
                    Image(systemName: space.icon)
                        .font(.system(size: iconSize))
                        .background(EmojiPickerAnchor(manager: emojiManager))
                        .onTapGesture(count: 2) {
                            emojiManager.toggle()
                        }
                        .onChange(of: emojiManager.selectedEmoji) { _, newValue in
                            print(newValue)
                            space.icon = newValue
                            browserManager.tabManager.persistSnapshot()
                         }
                }

            }


            if isRenaming {
                TextField("", text: $draftName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(textColor)
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
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .onTapGesture(count: 2) {
                            startRenaming()
                        }
                }
            }

            Spacer()
            


            Menu {
                SpaceProfileDropdown(
                    currentProfileId: space.profileId ?? browserManager.profileManager.profiles.first?.id ?? UUID(),
                    onProfileSelected: { assignProfile($0) }
                )
                .environmentObject(browserManager)
                Divider()
                Button {
                    startRenaming()
                } label: {
                    Label("Rename Space", systemImage: "pencil")
                }
                Button {
                    emojiManager.toggle()
                } label: {
                    Label("Change Icon", systemImage: "face.smiling")
                }
                Divider()
                Button {
                    createFolder()
                } label: {
                    Label("Create Folder", systemImage: "folder.badge.plus")
                }
                if canDeleteSpace {
                    Button(role: .destructive) {
                        deleteSpace()
                    } label: {
                        Label("Delete Space", systemImage: "trash")
                    }
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isEllipsisHovering ? .white.opacity(0.07) : .clear)
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16))
                        .foregroundStyle(AppColors.textSecondary)
                        .opacity(isHovering ? 1.0 : 0.0)
                }
                .frame(width: 24, height: 24)
                .contentShape(RoundedRectangle(cornerRadius: 6))
                .onHover { hovering in
                    isEllipsisHovering = hovering
                }
            }
            .menuStyle(.button)
            .buttonStyle(PlainButtonStyle())

        }
        // Match tabs' internal left/right padding so text aligns
        .overlay {
            if browserManager.tabManager.spacePinnedTabs(for: space.id).isEmpty {
                Color.clear
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onDrop(
                        of: [.text],
                        delegate: SidebarSectionDropDelegateSimple(
                            itemsCount: {
                                browserManager.tabManager.spacePinnedTabs(for: space.id).count
                            },
                            draggedItem: $dropDraggedItem,
                            targetSection: .spacePinned(space.id),
                            tabManager: browserManager.tabManager,
                            targetIndex: nil,
                            onDropEntered: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                                    isDropHovering = true
                                }
                            },
                            onDropCompleted: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isDropHovering = false
                                }
                            },
                            onDropExited: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    isDropHovering = false
                                }
                            }
                        )
                    )
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 40)
        .frame(maxWidth: .infinity)
        .background(hoverColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.1)) {
                isHovering = hovering
            }
        }
        .onChange(of: nameFieldFocused) { _, focused in
            // When losing focus during rename, commit
            if isRenaming && !focused {
                commitRename()
            }
        }
        // Provide a right-click context menu
        .contextMenu {
            SpaceContextMenu(
                space: space,
                canDelete: canDeleteSpace,
                showNewFolder: true,
                onEditSpace: {
                    browserManager.dialogManager.showDialog(
                        SpaceEditDialog(
                            space: space,
                            mode: .icon,
                            onSave: { newName, newIcon, newProfileId in
                                updateSpace(name: newName, icon: newIcon, profileId: newProfileId)
                            },
                            onCancel: {
                                browserManager.dialogManager.closeDialog()
                            }
                        )
                    )
                },
                onDeleteSpace: deleteSpace,
                onNewFolder: createFolder
            )
            .environmentObject(browserManager)
        }
    }
    
    //MARK: - Colors
    
    private var hoverColor: Color {
        if isHovering || isDropHovering {
            return colorScheme == .dark ? AppColors.spaceTabHoverLight : AppColors.spaceTabHoverDark
        } else {
            return .clear
        }
    }
    private var textColor: Color {
        return colorScheme == .dark ? AppColors.sidebarTextLight : AppColors.sidebarTextDark
    }

    private var canDeleteSpace: Bool {
        browserManager.tabManager.spaces.count > 1
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
            do {
                try browserManager.tabManager.renameSpace(
                    spaceId: space.id,
                    newName: newName
                )
            } catch {
                print("⚠️ Failed to rename space \(space.id.uuidString):", error)
            }
        }
        isRenaming = false
        nameFieldFocused = false
    }

    private func deleteSpace() {
        browserManager.tabManager.removeSpace(space.id)
    }

    private func createFolder() {
        print("🎯 SpaceTitle.createFolder() called for space '\(space.name)' (id: \(space.id.uuidString.prefix(8))...)")
        browserManager.tabManager.createFolder(for: space.id)
    }

    private func assignProfile(_ id: UUID) {
        browserManager.tabManager.assign(spaceId: space.id, toProfile: id)
    }

    private func updateSpace(name: String, icon: String, profileId: UUID?) {
        do {
            if icon != space.icon {
                try browserManager.tabManager.updateSpaceIcon(spaceId: space.id, icon: icon)
            }
            if name != space.name {
                try browserManager.tabManager.renameSpace(spaceId: space.id, newName: name)
            }
            if profileId != space.profileId, let profileId = profileId {
                browserManager.tabManager.assign(spaceId: space.id, toProfile: profileId)
            }
            browserManager.dialogManager.closeDialog()
        } catch {
            print("⚠️ Failed to update space \(space.id.uuidString):", error)
        }
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
