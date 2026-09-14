//
//  TabContextMenu.swift
//  Nook
//
//  Created by Claude on 2026-09-14.
//

import AppKit
import SwiftUI

/// Where a tab row lives in the sidebar. Decides which items the shared tab
/// context menu shows.
enum TabMenuContext {
    case regular
    case spacePinned
    case folder
    case essential
    case split
}

/// The one context menu every sidebar tab row uses. Replaces the inline menus
/// that used to live in `SpaceTab`, `SpaceView`, `TabFolderView`, `PinnedGrid`
/// and `SplitTabRow`.
struct TabContextMenu: View {
    @ObservedObject var tab: Tab
    let context: TabMenuContext

    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var tabManager: TabManager
    @Environment(BrowserWindowState.self) private var windowState: BrowserWindowState?

    var body: some View {
        Group {
            placementSection
            Divider()
            editSection
            Divider()
            stateSection
            Divider()
            closeSection
        }
    }

    // MARK: - Section 1: Placement

    @ViewBuilder
    private var placementSection: some View {
        if context == .regular, let spaceId = tab.spaceId {
            Button {
                tabManager.pinTabToSpace(tab, spaceId: spaceId)
            } label: {
                Label("Pin to Space", systemImage: "pin")
            }
        }

        if context == .spacePinned {
            Button {
                tabManager.unpinTabFromSpace(tab)
            } label: {
                Label("Unpin from Space", systemImage: "pin.slash")
            }
        }

        if context == .essential {
            Button {
                tabManager.unpinTab(tab)
            } label: {
                Label("Remove from Favorites", systemImage: "star.slash")
            }
        } else if !tab.isPinned {
            Button {
                tabManager.pinTab(tab)
            } label: {
                Label("Add to Favorites", systemImage: "star")
            }
        }

        if context == .regular || context == .spacePinned || context == .folder {
            addToFolderMenu
        }

        if context != .essential {
            moveToSpaceMenu
        }
    }

    @ViewBuilder
    private var addToFolderMenu: some View {
        if let spaceId = tab.spaceId {
            let folders = tabManager.folders(for: spaceId)

            if !folders.isEmpty {
                Menu {
                    ForEach(folders, id: \.id) { folder in
                        Button {
                            tabManager.moveTabToRegularFolder(tab: tab, folderId: folder.id)
                        } label: {
                            Label(folder.name, systemImage: "folder.fill")
                        }
                    }
                } label: {
                    Label("Add to Folder", systemImage: "folder.badge.plus")
                }
            }
        }
    }

    @ViewBuilder
    private var moveToSpaceMenu: some View {
        let spaces = tabManager.spaces
        Menu {
            ForEach(spaces, id: \.id) { space in
                Button {
                    tabManager.moveTab(tab.id, to: space.id)
                } label: {
                    spaceLabel(for: space)
                }
                .disabled(space.id == tab.spaceId)
            }
        } label: {
            Label("Move to Space", systemImage: "arrow.right.square")
        }
    }

    @ViewBuilder
    private func spaceLabel(for space: Space) -> some View {
        if space.icon.isEmojiIcon {
            Label {
                Text(space.name)
            } icon: {
                Text(space.icon)
            }
        } else {
            Label(space.name, systemImage: space.icon)
        }
    }

    // MARK: - Section 2: Edit

    @ViewBuilder
    private var editSection: some View {
        // Rename needs the row's inline text field, which only the list-style
        // rows render.
        if context == .regular || context == .spacePinned || context == .folder {
            Button {
                tab.startRenaming()
            } label: {
                Label("Rename", systemImage: "pencil")
            }
        }

        if tab.displayNameOverride != nil {
            Button {
                tab.displayNameOverride = nil
            } label: {
                Label("Reset Tab Name", systemImage: "arrow.uturn.backward")
            }
        }

        Button {
            browserManager.duplicateCurrentTab()
        } label: {
            Label("Duplicate", systemImage: "plus.square.on.square")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tab.url.absoluteString, forType: .string)
        } label: {
            Label("Copy Link", systemImage: "link")
        }

        Button {
            let picker = NSSharingServicePicker(items: [tab.url as NSURL])
            if let window = NSApp.keyWindow {
                picker.show(relativeTo: .zero, of: window.contentView ?? NSView(), preferredEdge: .minY)
            }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }

        if context != .split {
            Menu {
                Button {
                    guard let windowState else { return }
                    browserManager.splitManager.enterSplit(with: tab, placeOn: .right, in: windowState)
                } label: {
                    Label("Right", systemImage: "rectangle.righthalf.filled")
                }

                Button {
                    guard let windowState else { return }
                    browserManager.splitManager.enterSplit(with: tab, placeOn: .left, in: windowState)
                } label: {
                    Label("Left", systemImage: "rectangle.lefthalf.filled")
                }
            } label: {
                Label("Open in Split View", systemImage: "rectangle.split.2x1")
            }
        }

        if context == .spacePinned || context == .essential {
            if tab.hasNavigatedAwayFromPinnedURL {
                Button {
                    tab.resetToPinnedURL()
                } label: {
                    Label("Reset to Pinned URL", systemImage: "arrow.counterclockwise")
                }
            }

            if tab.pinnedURL != nil {
                Button {
                    browserManager.dialogManager.showDialog(
                        EditPinnedURLDialog(
                            tab: tab,
                            onSave: { newURL in
                                tab.pinnedURL = newURL
                                tab.loadURL(newURL)
                                browserManager.dialogManager.closeDialog()
                                tabManager.debouncedPersistSnapshot()
                            },
                            onCancel: {
                                browserManager.dialogManager.closeDialog()
                            }
                        )
                    )
                } label: {
                    Label("Edit Pinned URL", systemImage: "link.badge.plus")
                }
            }
        }
    }

    // MARK: - Section 3: State

    @ViewBuilder
    private var stateSection: some View {
        if tab.hasAudioContent || tab.isAudioMuted {
            Button {
                tab.toggleMute()
            } label: {
                Label(
                    tab.isAudioMuted ? "Unmute" : "Mute",
                    systemImage: tab.isAudioMuted ? "speaker.wave.2" : "speaker.slash"
                )
            }
        }

        // TabManager refuses to unload essential tabs, so the item would be inert there.
        if context != .essential {
            Button {
                tabManager.unloadTab(tab)
            } label: {
                Label("Unload Tab", systemImage: "moon.zzz")
            }
            .disabled(tab.isUnloaded)
        }

        Button {
            tabManager.unloadAllInactiveTabs()
        } label: {
            Label("Unload All Inactive Tabs", systemImage: "moon.zzz.fill")
        }
    }

    // MARK: - Section 4: Close

    @ViewBuilder
    private var closeSection: some View {
        Button(role: .destructive) {
            // A space-pinned row is only removed by forceRemoveTab; removeTab just
            // deactivates it and leaves the row in place.
            if context == .spacePinned {
                tabManager.forceRemoveTab(tab.id)
            } else {
                tabManager.removeTab(tab.id)
            }
        } label: {
            Label("Close Tab", systemImage: "xmark")
        }
        .keyboardShortcut("w", modifiers: .command)

        if let spaceId = tab.spaceId {
            let hasOtherTabs = (tabManager.tabsBySpace[spaceId]?.filter { $0.id != tab.id }.isEmpty == false)
            if context == .regular || context == .spacePinned || context == .folder,
               hasOtherTabs, !tab.isPinned, !tab.isSpacePinned {
                Button {
                    tabManager.closeOtherTabs(tab)
                } label: {
                    Label("Close Other Tabs", systemImage: "xmark.circle")
                }
            }
        }

        if context == .regular || context == .folder,
           !tab.isPinned, !tab.isSpacePinned, tab.spaceId != nil {
            Button {
                tabManager.closeAllTabsBelow(tab)
            } label: {
                Label("Close All Below", systemImage: "arrow.down.to.line")
            }
        }
    }
}
