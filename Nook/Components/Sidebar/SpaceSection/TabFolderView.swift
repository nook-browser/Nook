//
//  TabFolderView.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-24.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

// MARK: - Helpers

private func haptic(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .alignment) {
    NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
}

struct TabFolderView: View {
    @ObservedObject var folder: TabFolder
    let space: Space
    let onDelete: () -> Void
    let onAddTab: () -> Void
    let onActivateTab: (Tab) -> Void

    @State private var isHovering: Bool = false
    @State private var isFolderIconAnimating: Bool = false
    @State private var draggedItem: UUID? = nil
    @State private var isDropTargeted: Bool = false
    @State private var dropPreviewIndex: Int? = nil
    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @FocusState private var nameFieldFocused: Bool

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
  

    // Get tabs in this folder
    private var tabsInFolder: [Tab] {
        let tabs = browserManager.tabManager.spacePinnedTabs(for: space.id)
            .filter { $0.folderId == folder.id }
            .sorted { $0.index < $1.index }
        print("📁 Folder '\(folder.name)' contains \(tabs.count) tabs: \(tabs.map { $0.name })")
        return tabs
    }

    var body: some View {
        VStack(spacing: 0) {
            // Folder header
            folderHeader

            // Folder content (tabs)
            if folder.isOpen {
                folderContent
                    .transition(.asymmetric(
                        insertion: .identity,
                        removal: .identity
                    ))
            }
        }
        .onDrop(
            of: [.text],
            delegate: SidebarSectionDropDelegateSimple(
                itemsCount: { tabsInFolder.count },
                draggedItem: $draggedItem,
                targetSection: .folder(folder.id),
                tabManager: browserManager.tabManager,
                targetIndex: { folderInsertionIndex(before: tabsInFolder.count, tabs: tabsInFolder) },
                onDropEntered: {
                    if !folder.isOpen {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            folder.isOpen = true
                        }
                    }
                    isDropTargeted = true
                },
                onDropCompleted: {
                    dropPreviewIndex = nil
                    isDropTargeted = false
                    triggerFolderAnimation()
                },
                onDropExited: {
                    dropPreviewIndex = nil
                    isDropTargeted = false
                }
            )
        )
    }

    private var folderHeader: some View {
        Button(action: {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                folder.isOpen.toggle()
            }
        }) {
            HStack(spacing: 8) {
                // Folder icon with animation
                folderIconView

                // Folder name - editable
                if isRenaming {
                    TextField("", text: $draftName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocorrectionDisabled()
                        .focused($nameFieldFocused)
                        .onAppear {
                            draftName = folder.name
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
                    Text(folder.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                // Context menu button
                if isHovering && !isRenaming {
                    Menu {
                        Button(action: startRenaming) {
                            Label("Rename Folder", systemImage: "pencil")
                        }
                        Button(action: onAddTab) {
                            Label("Add Tab to Folder", systemImage: "plus")
                        }
                        Divider()
                        Button(action: alphabetizeTabs) {
                            Label("Alphabetize Tabs", systemImage: "text.alignleft")
                        }
                        Divider()
                        Button(role: .destructive, action: onDelete) {
                            Label("Delete Folder", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                            .opacity(0.7)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .frame(height: 40)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isDropTargeted
                            ? AppColors.controlBackgroundActive.opacity(0.25)
                            : (isHovering ? AppColors.controlBackgroundHover : Color.clear)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .contextMenu {
            folderContextMenu
        }
        .onTabDrag(folder.id, draggedItem: $draggedItem)
        .opacity(draggedItem == folder.id ? 0.0 : 1.0)
        .onChange(of: draggedItem) { _, newValue in
            // Close folder immediately when drag starts on this folder
            if newValue == folder.id && folder.isOpen {
                withAnimation(.easeInOut(duration: 0.2)) {
                    folder.isOpen = false
                }
            }
        }
        .onChange(of: nameFieldFocused) { _, focused in
            // When losing focus during rename, commit
            if isRenaming && !focused {
                commitRename()
            }
        }
    }

    private var folderIconView: some View {
        Image(systemName: folder.isOpen ? "folder.fill" : "folder")
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(space.gradient.primaryColor)
            .symbolEffect(.bounce, options: .speed(0.5).repeat(1), value: isFolderIconAnimating)
            .onAppear {
                isFolderIconAnimating = false
            }
            .onChange(of: isFolderIconAnimating) { _, newValue in
                if newValue {
                    // Reset animation after it completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        isFolderIconAnimating = false
                    }
                }
            }
    }

    private var folderContent: some View {
        let tabs = tabsInFolder

        return VStack(spacing: 0) {
            ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                folderDropSpacer(before: index, tabs: tabs)

                folderTabView(tab)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .top)
                                .combined(with: .opacity)
                                .animation(.spring(response: 0.3, dampingFraction: 0.8).delay(Double(index) * 0.03)),
                            removal: .move(edge: .top)
                                .combined(with: .opacity)
                                .animation(.spring(response: 0.2, dampingFraction: 0.7).delay(Double(tabs.count - index - 1) * 0.02))
                        )
                    )
            }

            folderDropSpacer(before: tabs.count, tabs: tabs)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isDropTargeted ? AppColors.controlBackgroundActive.opacity(0.18) : Color.clear)
        )
    }

    private func folderTabView(_ tab: Tab) -> some View {
        print("👀 Rendering folder tab: \(tab.name)")
        return SpaceTab(
            tab: tab,
            action: {
                print("🖱️ Folder tab clicked: \(tab.name)")
                onActivateTab(tab)
            },
            onClose: { browserManager.tabManager.removeTab(tab.id) },
            onMute: { tab.toggleMute() }
        )
        .padding(.leading, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .contextMenu {
            folderTabContextMenu(tab)
        }
        .onTabDrag(tab.id, draggedItem: $draggedItem)
        .opacity(draggedItem == tab.id ? 0.0 : 1.0)
        .onDrop(
            of: [.text],
            delegate: SidebarTabDropDelegateSimple(
                item: tab,
                draggedItem: $draggedItem,
                targetSection: .folder(folder.id),
                tabManager: browserManager.tabManager
            )
        )
    }

    private var folderContextMenu: some View {
        VStack {
            Button(action: startRenaming) {
                Label("Rename Folder", systemImage: "pencil")
            }
            Button(action: onAddTab) {
                Label("Add Tab to Folder", systemImage: "plus")
            }
            Divider()
            Button(action: alphabetizeTabs) {
                Label("Alphabetize Tabs", systemImage: "text.alignleft")
            }
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete Folder", systemImage: "trash")
            }
        }
    }

    private func folderTabContextMenu(_ tab: Tab) -> some View {
        VStack {
            // Split view
            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .right, in: windowState) }
            label: { Label("Open in Split (Right)", systemImage: "rectangle.split.2x1") }
            Button { browserManager.splitManager.enterSplit(with: tab, placeOn: .left, in: windowState) }
            label: { Label("Open in Split (Left)", systemImage: "rectangle.split.2x1") }
            
            Button { browserManager.duplicateCurrentTab() }
            label: { Label("Duplicate Tab", systemImage: "doc.on.doc") }
            
            Divider()
            // Mute/Unmute option (show if tab has audio content OR is muted)
            if tab.hasAudioContent || tab.isAudioMuted {
                Button(action: { tab.toggleMute() }) {
                    Label(tab.isAudioMuted ? "Unmute Audio" : "Mute Audio",
                          systemImage: tab.isAudioMuted ? "speaker.wave.2" : "speaker.slash")
                }
                Divider()
            }

            // Unload options
            Button(action: {
                browserManager.tabManager.unloadTab(tab)
            }) {
                Label("Unload Tab", systemImage: "arrow.down.circle")
            }
            .disabled(tab.isUnloaded)

            Button(action: {
                browserManager.tabManager.unloadAllInactiveTabs()
            }) {
                Label("Unload All Inactive Tabs", systemImage: "arrow.down.circle.fill")
            }

            Divider()

            Button(action: {
                browserManager.tabManager.removeTab(tab.id)
            }) {
                Label("Close Tab", systemImage: "xmark.circle")
            }
        }
    }

    private func triggerFolderAnimation() {
        isFolderIconAnimating = true
    }

    private func alphabetizeTabs() {
        let sortedTabs = tabsInFolder.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            // Update tab indices to match alphabetical order
            for (index, tab) in sortedTabs.enumerated() {
                tab.index = index
            }
            browserManager.tabManager.persistSnapshot()
        }
    }

    @ViewBuilder
    private func folderDropSpacer(before displayIndex: Int, tabs: [Tab]) -> some View {
        let isActive = dropPreviewIndex == displayIndex

        Color.clear
            .frame(height: 2)
            .contentShape(Rectangle())
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(AppColors.controlBackgroundHover)
                    .frame(height: isActive ? 4 : 0)
                    .padding(.leading, 26)
                    .padding(.trailing, 8)
                    .opacity(isActive ? 1 : 0)
                    .animation(.easeInOut(duration: 0.12), value: isActive)
            }
            .onDrop(
                of: [.text],
                delegate: SidebarSectionDropDelegateSimple(
                    itemsCount: { tabs.count },
                    draggedItem: $draggedItem,
                    targetSection: .folder(folder.id),
                    tabManager: browserManager.tabManager,
                    targetIndex: { folderInsertionIndex(before: displayIndex, tabs: tabs) },
                    onDropEntered: {
                        dropPreviewIndex = displayIndex
                        isDropTargeted = true
                    },
                    onDropCompleted: {
                        dropPreviewIndex = nil
                        isDropTargeted = false
                        triggerFolderAnimation()
                    },
                    onDropExited: {
                        if dropPreviewIndex == displayIndex {
                            dropPreviewIndex = nil
                        }
                        isDropTargeted = false
                    }
                )
            )
    }

    private func folderInsertionIndex(before displayIndex: Int, tabs: [Tab]) -> Int {
        let all = browserManager.tabManager.spacePinnedTabs(for: space.id)

        guard !tabs.isEmpty else {
            return folderFallbackInsertionIndex(within: all)
        }

        if displayIndex <= 0 {
            return tabs.first?.index ?? 0
        }

        if displayIndex >= tabs.count {
            let lastIndex = tabs.last?.index ?? (all.count - 1)
            return min(lastIndex + 1, all.count)
        }

        return tabs[displayIndex].index
    }

    private func folderFallbackInsertionIndex(within all: [Tab]) -> Int {
        let clampedIndex = max(0, min(folder.index, all.count))
        return clampedIndex
    }

    // MARK: - Rename Actions

    private func startRenaming() {
        draftName = folder.name
        isRenaming = true
    }

    private func cancelRename() {
        isRenaming = false
        draftName = folder.name
        nameFieldFocused = false
    }

    private func commitRename() {
        let newName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty && newName != folder.name {
            browserManager.tabManager.renameFolder(folder.id, newName: newName)
        }
        isRenaming = false
        nameFieldFocused = false
    }
}
