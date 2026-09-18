// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  BrowserModel+TabActions.swift
//  NookiOS
//
//  The app-side work the shared rows and menus trigger. Split view and extra
//  windows do not exist on the phone, so those members are inert and
//  `supportsMultipleWindows` hides the menu items that would reach them.
//

import SwiftUI
import UIKit
import NookUI
import NookWeb

extension BrowserModel: TabActions {
    var supportsMultipleWindows: Bool { false }

    func enterSplit(with itemID: UUID, placeOnRight: Bool, in window: BrowserWindowState) {
        // No split view on iOS. The menu item that would call this is hidden.
    }

    func editPinnedURL(url: URL, title: String, onSave: @escaping (URL) -> Void) {
        present(.editPinnedURL(url: url, title: title, onSave: onSave))
    }

    func presentSpaceCreation(onCreate: @escaping (String, String) -> Void) {
        present(.createSpace(onCreate: onCreate))
    }

    func confirmSpaceDeletion(
        spaceName: String,
        tabCount: Int,
        isLastSpace: Bool,
        onDelete: @escaping () -> Void
    ) {
        present(.deleteSpace(name: spaceName, tabCount: tabCount, isLast: isLastSpace, onDelete: onDelete))
    }

    func openSpaceSettings() {
        settingsRoute = .spaces
        present(.settings)
    }

    /// There is no toast host on the phone, so there is nothing to hide.
    func hideTabClosureToast() {}

    var tabClosureToastCount: Int { 0 }

    var accentColor: Color {
        guard let spaceID = window.spaceID, let space = tabs.space(spaceID) else {
            return .accentColor
        }
        return space.accentColor
    }

    func copyToPasteboard(_ string: String) {
        UIPasteboard.general.string = string
    }

    func share(_ url: URL) {
        guard let root = Self.presentingViewController() else { return }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // iPad raises without a source for the popover.
        activity.popoverPresentationController?.sourceView = root.view
        activity.popoverPresentationController?.sourceRect = CGRect(
            x: root.view.bounds.midX,
            y: root.view.bounds.maxY,
            width: 0,
            height: 0
        )
        root.present(activity, animated: true)
    }

    /// The topmost presented controller, so the share sheet does not try to come
    /// up underneath the tab sheet.
    private static func presentingViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.keyWindow?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}
