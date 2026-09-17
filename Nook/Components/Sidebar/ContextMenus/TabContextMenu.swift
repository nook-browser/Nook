//
//  TabContextMenu.swift
//  Nook
//
//  Created by Claude on 2026-09-14.
//

import AppKit
import SwiftUI
import NookTabsCore
import NookWeb

/// Which view shows the tab. The item's section (favorites, pinned, tabs) comes from the tree.
enum TabMenuContext {
    /// A row in the sidebar outline.
    case sidebar
    /// A favorites tile.
    case favorite
    /// One half of the split row.
    case split
}

/// The one context menu every sidebar tab row and favorites tile uses.
struct TabContextMenu: View {
    let itemID: UUID
    let context: TabMenuContext

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState: BrowserWindowState?

    private var tabs: TabsController { browserManager.tabs }

    var body: some View {
        if let item = tabs.item(itemID) {
            let section = tabs.section(of: itemID)
            Group {
                placementSection(item, section: section)
                Divider()
                editSection(item, section: section)
                Divider()
                stateSection(item)
                Divider()
                closeSection(item, section: section)
            }
        }
    }

    private var spaceID: UUID? {
        tabs.spaceID(of: itemID) ?? windowState?.spaceID
    }

    // MARK: - Section 1: Placement

    @ViewBuilder
    private func placementSection(_ item: Item, section: Parent?) -> some View {
        if case .tabs = section, let spaceID {
            Button {
                tabs.pin(itemID, to: .pinned(spaceID: spaceID))
            } label: {
                Label("Pin to Space", systemImage: "pin")
            }
        }

        if case .pinned = section {
            Button {
                tabs.unpin(itemID)
            } label: {
                Label("Unpin from Space", systemImage: "pin.slash")
            }
        }

        if case .favorites = section {
            Button {
                tabs.unpin(itemID)
            } label: {
                Label("Remove from Favorites", systemImage: "star.slash")
            }
        } else if let spaceID = tabs.spaceID(of: itemID) {
            Button {
                tabs.pin(itemID, to: .favorites(spaceID: spaceID))
            } label: {
                Label("Add to Favorites", systemImage: "star")
            }
        }

        if context != .favorite, let spaceID {
            addToFolderMenu(item, spaceID: spaceID)

            Button {
                tabs.createFolderForRename(in: item.parent, after: itemID)
            } label: {
                Label("New Folder", systemImage: "folder.badge.plus")
            }
        }

        if context != .favorite {
            moveToSpaceMenu
        }
    }

    @ViewBuilder
    private func addToFolderMenu(_ item: Item, spaceID: UUID) -> some View {
        let folders = tabs.folders(inSpace: spaceID)
        if !folders.isEmpty {
            Menu {
                ForEach(folders, id: \.item.id) { folder in
                    Button {
                        tabs.move(itemID, to: .folder(itemID: folder.item.id), after: tabs.children(of: .folder(itemID: folder.item.id)).last?.id)
                    } label: {
                        Label(String(repeating: "   ", count: folder.depth) + folder.item.displayTitle, systemImage: "folder.fill")
                    }
                    .disabled(item.parent == .folder(itemID: folder.item.id))
                }
            } label: {
                Label("Add to Folder", systemImage: "folder.badge.plus")
            }
        }
    }

    @ViewBuilder
    private var moveToSpaceMenu: some View {
        let current = tabs.spaceID(of: itemID)
        let spaces = tabs.spaces(visibleIn: windowState)
        if spaces.count > 1 {
            Menu {
                ForEach(spaces) { space in
                    Button {
                        tabs.move(itemID, to: .tabs(spaceID: space.id), after: nil)
                    } label: {
                        Text(space.name)
                    }
                    .disabled(space.id == current)
                }
            } label: {
                Label("Move to Space", systemImage: "arrow.right.square")
            }
        }
    }

    // MARK: - Section 2: Edit

    @ViewBuilder
    private func editSection(_ item: Item, section: Parent?) -> some View {
        // Rename needs the row's inline text field, which only outline rows render.
        if context == .sidebar {
            Button {
                SidebarRenameState.shared.itemID = itemID
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }

        if let custom = item.customTitle, !custom.isEmpty {
            Button {
                tabs.rename(itemID, nil)
            } label: {
                Label("Reset Tab Name", systemImage: "arrow.uturn.backward")
            }
        }

        Button {
            guard let windowState else { return }
            tabs.duplicate(itemID, in: windowState)
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        if let url = tabs.currentURL(for: item) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
            } label: {
                Label("Copy Link", systemImage: "link")
            }

            Button {
                let picker = NSSharingServicePicker(items: [url as NSURL])
                if let window = NSApp.keyWindow {
                    picker.show(relativeTo: .zero, of: window.contentView ?? NSView(), preferredEdge: .minY)
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }

        if context != .split, let windowState, let selected = tabs.selectedItemID(in: windowState), selected != itemID {
            Menu {
                Button {
                    browserManager.splitManager.enterSplit(with: itemID, placeOn: .right, in: windowState)
                } label: {
                    Label("Right", systemImage: "rectangle.righthalf.filled")
                }

                Button {
                    browserManager.splitManager.enterSplit(with: itemID, placeOn: .left, in: windowState)
                } label: {
                    Label("Left", systemImage: "rectangle.lefthalf.filled")
                }
            } label: {
                Label("Open in Split View", systemImage: "rectangle.split.2x1")
            }
        }

        if tabs.isSynced(itemID) {
            if tabs.hasLeftHome(itemID) {
                Button {
                    tabs.resetToHome(itemID)
                } label: {
                    Label("Reset to Pinned URL", systemImage: "arrow.counterclockwise")
                }

                Button {
                    tabs.setHomeToCurrent(itemID)
                } label: {
                    Label("Replace Pinned URL with Current", systemImage: "pin")
                }
            }

            Button {
                editHomeURL(item)
            } label: {
                Label("Edit Pinned URL", systemImage: "link.badge.plus")
            }
        }
    }

    private func editHomeURL(_ item: Item) {
        guard let home = item.url else { return }
        let dialogs = browserManager.dialogManager
        dialogs.showDialog(
            EditPinnedURLDialog(
                url: home,
                title: tabs.title(for: item),
                onSave: { newURL in
                    tabs.setHome(itemID, url: newURL)
                    tabs.resetToHome(itemID)
                    dialogs.closeDialog()
                },
                onCancel: { dialogs.closeDialog() }
            )
        )
    }

    // MARK: - Section 3: State

    @ViewBuilder
    private func stateSection(_ item: Item) -> some View {
        let session = tabs.session(for: itemID)
        if let session, session.hasAudioContent || session.isAudioMuted {
            Button {
                session.toggleMute()
            } label: {
                Label(
                    session.isAudioMuted ? "Unmute" : "Mute",
                    systemImage: session.isAudioMuted ? "speaker.wave.2" : "speaker.slash"
                )
            }
        }

        Button {
            tabs.unload(itemID)
        } label: {
            Label("Unload Tab", systemImage: "moon.zzz")
        }
        .disabled(session?.isUnloaded ?? true)

        Button {
            tabs.unloadAllHidden()
        } label: {
            Label("Unload All Inactive Tabs", systemImage: "moon.zzz.fill")
        }
    }

    // MARK: - Section 4: Close

    @ViewBuilder
    private func closeSection(_ item: Item, section: Parent?) -> some View {
        Button(role: .destructive) {
            tabs.close(itemID)
        } label: {
            Label("Close Tab", systemImage: "xmark")
        }
        .keyboardShortcut("w", modifiers: .command)

        if case .pinned = section {
            Button(role: .destructive) {
                tabs.remove(itemID)
            } label: {
                Label("Remove from Space", systemImage: "trash")
            }
        }

        // Close others / below apply to the tabs section, where closing removes items.
        if context == .sidebar, case .tabs = section {
            let siblings = tabs.children(of: item.parent).filter { !$0.isFolder }
            if siblings.contains(where: { $0.id != itemID }) {
                Button {
                    tabs.close(siblings.map(\.id).filter { $0 != itemID })
                } label: {
                    Label("Close Other Tabs", systemImage: "xmark.circle")
                }
            }

            if let position = siblings.firstIndex(where: { $0.id == itemID }), position + 1 < siblings.count {
                Button {
                    tabs.close(siblings[(position + 1)...].map(\.id))
                } label: {
                    Label("Close All Below", systemImage: "arrow.down.to.line")
                }
            }
        }
    }
}
