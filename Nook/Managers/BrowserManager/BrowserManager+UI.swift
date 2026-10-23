// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserManager+UI.swift
//  Nook
//
//  Created by Claude on 17/09/2026.
//
//  The app side of NookUI's seam: the split view, the floating dialogs, the tab-closure
//  toast, the window accent, and the two AppKit services the shared menus need.
//

import AppKit
import SwiftUI
import NookTabsCore
import NookUI
import NookDesign
import NookWeb

extension BrowserManager: TabActions {
    func enterSplit(with itemID: UUID, placeOnRight: Bool, in window: BrowserWindowState) {
        splitManager.enterSplit(with: itemID, placeOn: placeOnRight ? .right : .left, in: window)
    }

    func separateSplit(in window: BrowserWindowState) {
        splitManager.separate(in: window)
    }

    func editPinnedURL(url: URL, title: String, onSave: @escaping (URL) -> Void) {
        dialogManager.showDialog(
            EditPinnedURLDialog(
                url: url,
                title: title,
                onSave: { [weak self] newURL in
                    onSave(newURL)
                    self?.dialogManager.closeDialog()
                },
                onCancel: { [weak self] in self?.dialogManager.closeDialog() }
            )
        )
    }

    /// Asks for a feed URL and adds a live feed folder to the space's pinned section.
    func presentFeedFolderPrompt(in spaceID: UUID) {
        dialogManager.showDialog(
            FeedFolderDialog(
                onAdd: { [weak self] url in
                    self?.tabs.createLiveFolder(.feed(url), in: spaceID)
                    self?.dialogManager.closeDialog()
                },
                onCancel: { [weak self] in self?.dialogManager.closeDialog() }
            )
        )
    }

    func presentSpaceCreation() {
        guard let registry = windowRegistry else { return }
        let target = registry.activeWindow.flatMap { $0.isIncognito ? nil : $0 }
            ?? registry.allWindows.first(where: { !$0.isIncognito })
        if let target {
            beginSpaceCreation(in: target)
            target.window?.deminiaturize(nil)
            target.window?.makeKeyAndOrderFront(nil)
        } else {
            let state = BrowserWindowState()
            state.isCreatingSpace = true
            createNewWindow(windowState: state)
        }
    }

    /// All macOS entry points use the same sidebar form and preserve an existing draft.
    func beginSpaceCreation(in window: BrowserWindowState) {
        guard !window.isIncognito else { return }
        withAnimation(NookDesign.Motion.standard) {
            window.isSidebarVisible = true
            window.isSidebarMenuVisible = false
            if !window.isCreatingSpace {
                window.spaceCreationAppearance = window.spaceID
                    .flatMap { tabs.space($0)?.resolvedAppearance }
                    ?? SpaceAppearance(accentHex: SpaceAccent.defaultHex)
                window.isCreatingSpace = true
            }
        }
    }

    func confirmSpaceDeletion(spaceName: String, tabCount: Int, isLastSpace: Bool, onDelete: @escaping () -> Void) {
        dialogManager.showDialog(
            SpaceDeleteConfirmationDialog(
                spaceName: spaceName,
                tabsCount: tabCount,
                isLastSpace: isLastSpace,
                onDelete: { [weak self] in
                    onDelete()
                    self?.dialogManager.closeDialog()
                },
                onCancel: { [weak self] in self?.dialogManager.closeDialog() }
            )
        )
    }

    func openSpaceSettings() {
        openSettings(tab: .spaces)
    }

    var accentColor: Color {
        gradientColorManager.accentColor
    }

    func copyToPasteboard(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    func share(_ url: URL) {
        let picker = NSSharingServicePicker(items: [url as NSURL])
        guard let window = NSApp.keyWindow else { return }
        picker.show(relativeTo: .zero, of: window.contentView ?? NSView(), preferredEdge: .minY)
    }
}
