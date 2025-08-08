import SwiftUI

struct SpaceTittle: View {
    @EnvironmentObject var browserManager: BrowserManager

    let space: Space
    var iconSize: CGFloat = 12

    @State private var isHovering: Bool = false
    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @State private var showingIconPicker: Bool = false
    @FocusState private var nameFieldFocused: Bool

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
                Text(space.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer()

            if isHovering {
                Menu {
                    Button {
                        startRenaming()
                    } label: {
                        Label("Rename Space", systemImage: "pencil")
                    }
                    Button {
                        showingIconPicker = true
                    } label: {
                        Label("Change Icon", systemImage: "face.smiling")
                    }
                    Button(role: .destructive) {
                        deleteSpace()
                    } label: {
                        Label("Delete Space", systemImage: "trash")
                    }
                } label: {
                    NavButton(iconName: "ellipsis")
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
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
        .popover(isPresented: $showingIconPicker, arrowEdge: .trailing) {
            EmojiGridPicker { selectedEmoji in
                space.icon = selectedEmoji
                browserManager.tabManager.persistSnapshot()
                showingIconPicker = false
            }
            .padding()
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
    
    private func isEmoji(_ string: String) -> Bool {
        return string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF) ||
            (scalar.value >= 0x2600 && scalar.value <= 0x26FF) ||
            (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }
}
