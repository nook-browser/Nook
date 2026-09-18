// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  BrowserWindowState.swift
//  NookWeb
//
//  Created by Jonathan Caudill on 12/09/2024.
//

import Foundation
import NookTabsCore
import SwiftUI

/// The platform window behind a `BrowserWindowState`. AppKit's `NSWindow` conforms in the app.
@MainActor
public protocol WindowHandle: AnyObject {
    /// The frame as a string the same platform can parse back (`NSStringFromRect` on macOS).
    var frameString: String? { get }
    func applyFrame(_ rectString: String)
    func bringToFront()
}

/// Represents the state of a single browser window, allowing multiple windows
/// to have independent tab selections and UI states while sharing the same tab data.
@MainActor
@Observable
public class BrowserWindowState {
    /// Unique identifier for this window instance
    public let id: UUID

    /// Sidebar width for this window
    public var sidebarWidth: CGFloat = 250

    /// Last non-zero sidebar width so we can restore when toggling visibility
    public var savedSidebarWidth: CGFloat = 250

    /// Width for the AI assistant sidebar when visible
    public var aiSidebarWidth: CGFloat = 350

    /// Usable width for sidebar content (excludes padding)
    public var sidebarContentWidth: CGFloat = 234

    /// Whether the sidebar is visible in this window
    public var isSidebarVisible: Bool = true

    /// Whether the sidebar menu is visible in this window
    public var isSidebarMenuVisible: Bool = false

    /// The selected tab in the sidebar menu (history or downloads)
    public var sidebarMenuSelectedTab: SidebarMenuTab = .history

    /// Whether the AI chat panel is visible in this window
    public var isSidebarAIChatVisible: Bool = false

    /// Whether the command palette is visible in this window
    public var isCommandPaletteVisible: Bool = false

    /// Whether the extension library panel is visible in this window
    public var isExtensionLibraryVisible: Bool = false

    // MARK: - App-side objects
    //
    // Typed accessors live in the app (`BrowserWindowState+macOS.swift`); the storage is here so
    // one window state carries them. Observed storage keeps views that read the typed accessor
    // updating; `@ObservationIgnored` storage is for references nothing renders from.

    @ObservationIgnored public var extensionLibraryPanelStorage: Any?
    @ObservationIgnored public weak var commandPaletteStorage: AnyObject?
    /// Read inside the toast view body, so it stays observed.
    public var shortcutConflictStorage: Any?

    /// Frame of the URL bar within this window
    public var urlBarFrame: CGRect = .zero

    /// Toast info for this window
    var toastInfo: WindowToastInfo?

    /// Presentation flag for the copy URL toast
    public var isShowingCopyURLToast: Bool = false

    /// Presentation flag for the shortcut conflict toast
    public var isShowingShortcutConflictToast: Bool = false

    /// Compositor version counter for this window (incremented when tab ownership changes)
    public var compositorVersion: Int = 0

    /// The platform window, set by the app once it exists.
    @ObservationIgnored public weak var windowHandle: WindowHandle? {
        didSet { applyPendingFrame() }
    }

    /// Saved frame to apply once the platform window exists.
    @ObservationIgnored var pendingFrame: String?

    /// Applies `pendingFrame` after the window's own setup, which restores the autosaved frame
    /// asynchronously and would otherwise overwrite the saved one.
    func applyPendingFrame() {
        guard let frame = pendingFrame, let handle = windowHandle else { return }
        pendingFrame = nil
        handle.applyFrame(frame)
    }

    // MARK: - Incognito/Ephemeral State

    /// Whether this window is an incognito/private browsing window
    public var isIncognito: Bool = false

    /// The ephemeral, non-persistent data store this incognito window's pages use.
    /// Only set when isIncognito is true.
    public var ephemeralProfile: Profile?

    /// Whether the download warning has been shown in this incognito session
    var hasShownDownloadWarning: Bool = false

    // MARK: - Tab Model (TabsController)

    /// The space this window shows.
    public var spaceID: UUID?

    /// The selected item per space in this window.
    var selectedItemBySpace: [UUID: UUID] = [:]

    /// Items this window selected in each space, most recent last. Closing the selected item
    /// returns to the one before it. In memory only.
    var recentItemsBySpace: [UUID: [UUID]] = [:]

    /// Spaces whose last open tab was closed in this window. Returning to one shows the empty
    /// space instead of selecting its first tab. In memory only.
    var emptiedSpaces: Set<UUID> = []

    /// The selected item in the current space. There is no global current tab.
    public var selectedItemID: UUID? {
        spaceID.flatMap { selectedItemBySpace[$0] }
    }

    /// The split pair shown in this window, if any.
    public var split: SplitRecord?

    /// A private window's in-memory tree: one temporary space. Never saved. nil for regular windows.
    public var privateTree: TabTree?

    /// Live pages of a private window, by item id.
    var privateSessions: [UUID: PageSession] = [:]

    /// A private window's reopen-closed history, newest last. Memory only.
    var privateClosed: [ClosedEntry] = []

    public init(id: UUID = UUID()) {
        self.id = id
    }

    /// Increment the compositor version to trigger UI updates
    public func refreshCompositor() {
        compositorVersion += 1
    }
}

/// The sidebar menu's two tabs. The app aliases its own `Tabs` to this.
public enum SidebarMenuTab: Hashable, Sendable {
    case history
    case downloads
}

/// Toast information specific to a window
struct WindowToastInfo: Equatable {
    public let message: String
    public let timestamp: Date
    public let duration: TimeInterval

    public init(message: String, duration: TimeInterval = 2.0) {
        self.message = message
        self.timestamp = Date()
        self.duration = duration
    }
}
