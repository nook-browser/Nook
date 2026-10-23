// Licensed under GPL-3.0. See LICENSE.
//
//  TabFolderView.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-24.
//

import NookTabsCore
import SwiftUI
import NookDesign
import NookWeb

/// A folder header row in the sidebar outline. Its children are separate rows below it.
public struct TabFolderView: View {
    let item: Item
    let spaceID: UUID
    /// True while a drag would drop into this folder.
    var isDropTarget: Bool = false

    @State private var isHovering: Bool = false
    @State private var draftName: String = ""
    @FocusState private var nameFieldFocused: Bool

    @Environment(BrowserWindowState.self) private var windowState
    private let renameState = SidebarRenameState.shared

    @Environment(TabsController.self) private var tabs
    private var isOpen: Bool { tabs.isOpen(folder: item.id) }
    private var isRenaming: Bool { renameState.itemID == item.id }

    public init(
        item: Item,
        spaceID: UUID,
        isDropTarget: Bool = false
    ) {
        self.item = item
        self.spaceID = spaceID
        self.isDropTarget = isDropTarget
    }

    public var body: some View {
        Button(action: {
            withAnimation(NookDesign.Motion.spring) {
                tabs.toggleFolder(item.id)
            }
        }) {
            HStack(spacing: NookDesign.Spacing.md) {
                Image(systemName: "chevron.right")
                    .font(.system(size: NookDesign.Size.rowGlyph - 1, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(isOpen ? 90 : 0))
                    .animation(NookDesign.Motion.standard, value: isOpen)

                Image(systemName: liveSymbol ?? (isOpen ? "folder.fill" : "folder"))
                    .font(.system(size: NookDesign.Size.spaceIcon, weight: .medium))
                    .foregroundStyle(tabs.space(spaceID)?.accentColor ?? .secondary)

                if isRenaming {
                    TextField("", text: $draftName)
                        .font(NookDesign.Tab.font)
                        .foregroundStyle(.primary)
                        .textFieldStyle(PlainTextFieldStyle())
                        .autocorrectionDisabled()
                        .focused($nameFieldFocused)
                        .onAppear {
                            draftName = item.displayTitle
                            DispatchQueue.main.async { nameFieldFocused = true }
                        }
                        .onSubmit { commitRename() }
                        .onEscapeKey { cancelRename() }
                } else {
                    Text(item.displayTitle)
                        .font(NookDesign.Tab.font)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer(minLength: NookDesign.Spacing.xs)

                if let status = tabs.liveStatus[item.id] {
                    Image(systemName: "exclamationmark.triangle")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.secondary)
                        .help(liveStatusHelp(status))
                }

                if !isHovering {
                    Text("\(tabs.children(of: .folder(itemID: item.id)).count)")
                        .font(NookDesign.Font.caption)
                        .foregroundStyle(.tertiary)
                }

                if isHovering && !isRenaming {
                    Menu {
                        folderMenu
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                    }
                    .buttonStyle(NookIconButtonStyle(size: NookDesign.Size.rowButton, radius: NookDesign.Radius.sm))
                }
            }
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(height: NookDesign.Tab.height)
            .frame(maxWidth: .infinity)
            .nookTabSurface(selected: isDropTarget, hovered: isHovering)
        }
        .buttonStyle(NookTabButtonStyle())
        .padding(.vertical, NookDesign.Tab.verticalInset)
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
                isHovering = hovering
            }
        }
        .contextMenu {
            folderMenu
                .environment(windowState)
                .environment(tabs)
        }
        .onChange(of: nameFieldFocused) { _, focused in
            if isRenaming && !focused { commitRename() }
        }
    }

    private var folderMenu: some View {
        FolderContextMenu(itemID: item.id, onRename: startRenaming)
    }

    // MARK: - Live

    private var liveSymbol: String? {
        switch item.live {
        case nil: return nil
        case .githubIssues?: return "smallcircle.filled.circle"
        case .githubNotifications?: return "bell"
        case .asanaTasks?: return "checkmark.circle"
        case let source?: return source.feedURL != nil ? "dot.radiowaves.up.forward" : "arrow.triangle.pull"
        }
    }

    private func liveStatusHelp(_ status: TabsController.LiveFolderStatus) -> String {
        let signedOut = status == .signedOut
        switch item.live {
        case .githubIssues?: return signedOut ? "Sign in to GitHub" : "Couldn't load issues"
        case .githubNotifications?: return signedOut ? "Sign in to GitHub" : "Couldn't load notifications"
        case .asanaTasks?: return signedOut ? "Sign in to Asana" : "Couldn't load tasks"
        case let source? where source.feedURL != nil: return "Couldn't load feed"
        default: return signedOut ? "Sign in to GitHub" : "Couldn't load pull requests"
        }
    }

    // MARK: - Rename

    private func startRenaming() {
        draftName = item.displayTitle
        renameState.itemID = item.id
    }

    private func cancelRename() {
        renameState.itemID = nil
        nameFieldFocused = false
    }

    private func commitRename() {
        guard isRenaming else { return }
        let newName = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newName.isEmpty && newName != item.displayTitle {
            tabs.rename(item.id, newName)
        }
        cancelRename()
    }
}
