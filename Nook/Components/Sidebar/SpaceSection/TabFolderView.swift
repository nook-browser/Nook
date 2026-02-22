//
//  TabFolderView.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-24.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct TabFolderView: View {
    @ObservedObject var folder: TabFolder
    let space: Space
    let onDelete: () -> Void
    let onAddTab: () -> Void
    let onActivateTab: (Tab) -> Void

    @State private var isHovering: Bool = false
    @State private var isFolderIconAnimating: Bool = false
    @State private var isDropTargeted: Bool = false
    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @FocusState private var nameFieldFocused: Bool

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @ObservedObject private var dragSession = NookDragSessionManager.shared

    // Get tabs in this folder
    private var tabsInFolder: [Tab] {
        let tabs = browserManager.tabManager.spacePinnedTabs(for: space.id)
            .filter { $0.folderId == folder.id }
            .sorted { $0.index < $1.index }
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
        .onChange(of: dragSession.pendingDrop) { _, drop in
            handleFolderDrop(drop)
        }
        .onChange(of: dragSession.pendingReorder) { _, reorder in
            handleFolderReorder(reorder)
        }
    }

    // MARK: - Drop Handling

    private func handleFolderDrop(_ drop: PendingDrop?) {
        guard let drop = drop, case .folder(let folderId) = drop.targetZone, folderId == folder.id else { return }
        let allTabs = browserManager.tabManager.allTabs()
        guard let tab = allTabs.first(where: { $0.id == drop.item.tabId }) else { return }
        let op = dragSession.makeDragOperation(from: drop, tab: tab)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            browserManager.tabManager.handleDragOperation(op)
        }
        triggerFolderAnimation()
        dragSession.pendingDrop = nil
    }

    private func handleFolderReorder(_ reorder: PendingReorder?) {
        guard let reorder = reorder, case .folder(let folderId) = reorder.zone, folderId == folder.id else { return }
        let tabs = tabsInFolder
        guard reorder.fromIndex < tabs.count else {
            dragSession.pendingReorder = nil
            return
        }
        let tab = tabs[reorder.fromIndex]
        let op = dragSession.makeDragOperation(from: reorder, tab: tab)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            browserManager.tabManager.handleDragOperation(op)
        }
        dragSession.pendingReorder = nil
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

        return NookDropZoneHostView(
            zoneID: .folder(folder.id),
            isVertical: true,
            manager: dragSession
        ) {
            VStack(spacing: 0) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    folderTabView(tab, index: index)
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
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isDropTargeted ? AppColors.controlBackgroundActive.opacity(0.18) : Color.clear)
        )
        .onAppear {
            let zone = DropZoneID.folder(folder.id)
            dragSession.itemCellSize[zone] = 36
            dragSession.itemCellSpacing[zone] = 2
            dragSession.itemCounts[zone] = tabs.count
        }
        .onDisappear {
            let zone = DropZoneID.folder(folder.id)
            dragSession.itemCellSize[zone] = nil
            dragSession.itemCellSpacing[zone] = nil
            dragSession.itemCounts[zone] = nil
        }
        .onChange(of: tabs.count) { _, newCount in
            dragSession.itemCounts[.folder(folder.id)] = newCount
        }
    }

    private func folderTabView(_ tab: Tab, index: Int) -> some View {
        NookDragSourceView(
            item: NookDragItem(tabId: tab.id, title: tab.name, urlString: tab.url.absoluteString),
            tab: tab,
            zoneID: .folder(folder.id),
            index: index,
            manager: dragSession
        ) {
            SpaceTab(
                tab: tab,
                action: {
                    onActivateTab(tab)
                },
                onClose: { browserManager.tabManager.removeTab(tab.id) },
                onMute: { tab.toggleMute() }
            )
            .padding(.leading, 12)
        }
        .opacity(dragSession.draggedItem?.tabId == tab.id ? 0.0 : 1.0)
        .offset(y: dragSession.reorderOffset(for: .folder(folder.id), at: index))
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragSession.insertionIndex[.folder(folder.id)])
        .transition(.move(edge: .top).combined(with: .opacity))
        .contextMenu {
            folderTabContextMenu(tab)
        }
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
