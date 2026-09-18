//
//  TabActions.swift
//  NookUI
//
//  The app-side work the shared rows, menus and settings tabs trigger that is not a
//  TabsController intent: split view, the floating dialogs, the tab-closure toast, the
//  window's accent, and the two AppKit services (pasteboard, share sheet).
//  BrowserManager conforms on macOS.
//

import SwiftUI
import NookBlocker
import NookTweaks
import NookWeb

@MainActor public protocol TabActions: AnyObject {
    /// Shows `itemID` beside the window's selected tab.
    func enterSplit(with itemID: UUID, placeOnRight: Bool, in window: BrowserWindowState)
    /// The "Edit Pinned URL" dialog. `onSave` gets the edited URL; the app closes the dialog.
    func editPinnedURL(url: URL, title: String, onSave: @escaping (URL) -> Void)
    /// The "New Space" dialog. `onCreate` gets the name and the accent hex.
    func presentSpaceCreation(onCreate: @escaping (String, String) -> Void)
    /// The destructive confirmation before a space and its tabs go away.
    func confirmSpaceDeletion(spaceName: String, tabCount: Int, isLastSpace: Bool, onDelete: @escaping () -> Void)
    /// Opens Settings on the Spaces tab.
    func openSpaceSettings()
    func hideTabClosureToast()
    var tabClosureToastCount: Int { get }
    /// The active space's accent, already published for the window.
    var accentColor: Color { get }
    func copyToPasteboard(_ string: String)
    func share(_ url: URL)
}

// MARK: - Environment

public struct TabActionsKey: EnvironmentKey {
    public static let defaultValue: (any TabActions)? = nil
}

/// The content blocker and site routing managers are plain classes, not `@Observable`,
/// so they travel as environment keys rather than `.environment(_:)` values.
public struct ContentBlockerKey: EnvironmentKey {
    public static let defaultValue: ContentBlockerManager? = nil
}

public struct SiteRoutingKey: EnvironmentKey {
    public static let defaultValue: SiteRoutingManager? = nil
}

extension EnvironmentValues {
    public var tabActions: (any TabActions)? {
        get { self[TabActionsKey.self] }
        set { self[TabActionsKey.self] = newValue }
    }

    public var contentBlocker: ContentBlockerManager? {
        get { self[ContentBlockerKey.self] }
        set { self[ContentBlockerKey.self] = newValue }
    }

    public var siteRouting: SiteRoutingManager? {
        get { self[SiteRoutingKey.self] }
        set { self[SiteRoutingKey.self] = newValue }
    }
}
