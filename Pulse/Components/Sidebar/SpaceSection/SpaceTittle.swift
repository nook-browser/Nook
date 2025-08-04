import SwiftUI

struct SpaceTittle: View {
    @EnvironmentObject var browserManager: BrowserManager

    let space: Space
    var iconSize: CGFloat = 12

    @State private var isHovering: Bool = false
    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @FocusState private var nameFieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: space.icon)
                .font(.system(size: iconSize))

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
}
