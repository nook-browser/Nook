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
import NookUI
import NookWeb

extension BrowserManager: TabActions {
    func enterSplit(with itemID: UUID, placeOnRight: Bool, in window: BrowserWindowState) {
        splitManager.enterSplit(with: itemID, placeOn: placeOnRight ? .right : .left, in: window)
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

    func presentSpaceCreation(onCreate: @escaping (String, String) -> Void) {
        dialogManager.showDialog(
            SpaceCreationDialog(
                onCreate: { [weak self] name, accentHex in
                    onCreate(name, accentHex)
                    self?.dialogManager.closeDialog()
                },
                onCancel: { [weak self] in self?.dialogManager.closeDialog() }
            )
        )
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
        SettingsNavigation.shared.currentSettingsTab = .spaces
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    var accentColor: Color {
        gradientColorManager.accentColor
    }

    var incognitoAccentColor: Color {
        SpaceGradient.incognito.primaryColor
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
