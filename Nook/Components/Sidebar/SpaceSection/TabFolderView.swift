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
    var isRegular: Bool = false

    @State private var isHovering: Bool = false
    @State private var isRenaming: Bool = false
    @State private var draftName: String = ""
    @FocusState private var nameFieldFocused: Bool

    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var tabManager: TabManager
    @Environment(BrowserWindowState.self) private var windowState
    @ObservedObject private var dragSession = NookDragSessionManager.shared

    // Get tabs in this folder
    private var tabsInFolder: [Tab] {
        if isRegular {
            return tabManager.regularFolderTabs(for: space.id, folderId: folder.id)
        }
        let tabs = tabManager.spacePinnedTabs(for: space.id)
            .filter { $0.folderId == folder.id }
            .sorted { $0.index < $1.index }
        return tabs
    }

    private var tabCount: Int {
        tabsInFolder.count
    }

    private var isDropTargeted: Bool {
        dragSession.isDragging && dragSession.activeZone == .folder(folder.id)
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
        let allTabs = tabManager.allTabs()
        guard let tab = allTabs.first(where: { $0.id == drop.item.tabId }) else { return }
        let op = dragSession.makeDragOperation(from: drop, tab: tab)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragSession.clearDrag()
            tabManager.handleDragOperation(op)
        }
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
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            dragSession.clearDrag()
            tabManager.handleDragOperation(op)
        }
        dragSession.pendingReorder = nil
    }

    private var folderHeader: some View {
        Button(action: {
            withAnimation(NookDesign.Motion.spring) {
                folder.isOpen.toggle()
            }
        }) {
            HStack(spacing: NookDesign.Spacing.md) {
                Image(systemName: "chevron.right")
                    .font(.system(size: NookDesign.Size.rowGlyph - 1, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(folder.isOpen ? 90 : 0))
                    .animation(NookDesign.Motion.standard, value: folder.isOpen)

                Image(systemName: folder.isOpen ? "folder.fill" : "folder")
                    .font(.system(size: NookDesign.Size.spaceIcon, weight: .medium))
                    .foregroundStyle(space.accentColor)

                // Folder name - editable
                if isRenaming {
                    TextField("", text: $draftName)
                        .font(NookDesign.Font.label)
                        .foregroundStyle(.primary)
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
                        .font(NookDesign.Font.label)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: NookDesign.Spacing.xs)

                if !isHovering {
                    Text("\(tabCount)")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.tertiary)
                }

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
                    }
                    .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.rowButton, radius: NookDesign.Radius.sm))
                }
            }
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(height: NookDesign.Size.row)
            .frame(maxWidth: .infinity)
            .background(
                NookDesign.Radius.shape(NookDesign.Radius.md)
                    .fill(
                        isDropTargeted
                            ? NookDesign.Surface.fillPressed
                            : (isHovering ? NookDesign.Surface.fill : Color.clear)
                    )
            )
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
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

    private var folderContent: some View {
        let tabs = tabsInFolder

        return NookDropZoneHostView(
            zoneID: .folder(folder.id),
            isVertical: true,
            manager: dragSession
        ) {
            VStack(spacing: NookDesign.Spacing.rowGap) {
                ForEach(Array(tabs.enumerated()), id: \.element.id) { index, tab in
                    folderTabView(tab, index: index)
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .top)
                                    .combined(with: .opacity)
                                    .animation(NookDesign.Motion.spring.delay(Double(index) * 0.03)),
                                removal: .move(edge: .top)
                                    .combined(with: .opacity)
                                    .animation(NookDesign.Motion.spring.delay(Double(tabs.count - index - 1) * 0.02))
                            )
                        )
                }
            }
        }
        .padding(.vertical, NookDesign.Spacing.xxs)
        .onAppear {
            let zone = DropZoneID.folder(folder.id)
            dragSession.itemCellSize[zone] = NookDesign.Size.row
            dragSession.itemCellSpacing[zone] = NookDesign.Spacing.rowGap
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
            item: NookDragItem(tabId: tab.id, title: tab.displayName, urlString: tab.url.absoluteString),
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
                onClose: { tabManager.removeTab(tab.id) },
                onMute: { tab.toggleMute() }
            )
            .padding(.leading, NookDesign.Spacing.folderIndent)
        }
        .opacity(dragSession.draggedItem?.tabId == tab.id ? 0.0 : 1.0)
        .offset(y: dragSession.reorderOffset(for: .folder(folder.id), at: index))
        .animation(NookDesign.Motion.spring, value: dragSession.insertionIndex[.folder(folder.id)])
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

            if tab.displayNameOverride != nil {
                Button {
                    tab.displayNameOverride = nil
                } label: {
                    Label("Reset Tab Name", systemImage: "arrow.uturn.backward")
                }
            }

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
                tabManager.unloadTab(tab)
            }) {
                Label("Unload Tab", systemImage: "arrow.down.circle")
            }
            .disabled(tab.isUnloaded)

            Button(action: {
                tabManager.unloadAllInactiveTabs()
            }) {
                Label("Unload All Inactive Tabs", systemImage: "arrow.down.circle.fill")
            }

            Divider()

            Button(action: {
                tabManager.removeTab(tab.id)
            }) {
                Label("Close Tab", systemImage: "xmark.circle")
            }
        }
    }

    private func alphabetizeTabs() {
        let sortedTabs = tabsInFolder.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        withAnimation(NookDesign.Motion.spring) {
            // Update tab indices to match alphabetical order
            for (index, tab) in sortedTabs.enumerated() {
                tab.index = index
            }
            tabManager.persistSnapshot()
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
            tabManager.renameFolder(folder.id, newName: newName)
        }
        isRenaming = false
        nameFieldFocused = false
    }
}
