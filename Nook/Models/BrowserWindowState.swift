//
//  BrowserWindowState.swift
//  Nook
//
//  Created by Jonathan Caudill on 12/09/2024.
//

import Foundation
import NookTabsCore
import SwiftUI

/// Represents the state of a single browser window, allowing multiple windows
/// to have independent tab selections and UI states while sharing the same tab data.
@MainActor
@Observable
class BrowserWindowState {
    /// Unique identifier for this window instance
    let id: UUID

    /// Sidebar width for this window
    var sidebarWidth: CGFloat = 250

    /// Last non-zero sidebar width so we can restore when toggling visibility
    var savedSidebarWidth: CGFloat = 250

    /// Width for the AI assistant sidebar when visible
    var aiSidebarWidth: CGFloat = 350

    /// Usable width for sidebar content (excludes padding)
    var sidebarContentWidth: CGFloat = 234

    /// Whether the sidebar is visible in this window
    var isSidebarVisible: Bool = true

    /// Whether the sidebar menu is visible in this window
    var isSidebarMenuVisible: Bool = false

    /// The selected tab in the sidebar menu (history or downloads)
    var sidebarMenuSelectedTab: Tabs = .history

    /// Whether the AI chat panel is visible in this window
    var isSidebarAIChatVisible: Bool = false

    /// Whether the command palette is visible in this window
    var isCommandPaletteVisible: Bool = false

    /// Whether the extension library panel is visible in this window
    var isExtensionLibraryVisible: Bool = false

    // MARK: - Extension Library
    private var _extensionLibraryPanelController: Any?
    var extensionLibraryPanelController: ExtensionLibraryPanelController? {
        get { _extensionLibraryPanelController as? ExtensionLibraryPanelController }
        set { _extensionLibraryPanelController = newValue }
    }

    /// Frame of the URL bar within this window
    var urlBarFrame: CGRect = .zero

    /// Toast info for this window
    var toastInfo: WindowToastInfo?

    /// Profile switch toast payload for this window
    var profileSwitchToast: BrowserManager.ProfileSwitchToast?

    /// Presentation flag for the profile switch toast
    var isShowingProfileSwitchToast: Bool = false
    
    /// Presentation flag for the copy URL toast
    var isShowingCopyURLToast: Bool = false
    
    /// Presentation flag for the shortcut conflict toast
    var isShowingShortcutConflictToast: Bool = false
    
    /// Shortcut conflict info for this window's toast
    var shortcutConflictInfo: ShortcutConflictInfo?

    /// Compositor version counter for this window (incremented when tab ownership changes)
    var compositorVersion: Int = 0

    /// Reference to the actual NSWindow for this window state
    var window: NSWindow? {
        didSet { applyPendingFrame() }
    }

    /// Saved frame (`NSStringFromRect`) to apply once the NSWindow exists.
    @ObservationIgnored var pendingFrame: String?

    /// Applies `pendingFrame` after the window's own setup, which restores the autosaved frame
    /// asynchronously and would otherwise overwrite the saved one.
    func applyPendingFrame() {
        guard let frame = pendingFrame, let nsWindow = window else { return }
        pendingFrame = nil
        let rect = NSRectFromString(frame)
        guard rect.width > 0, rect.height > 0 else { return }
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                nsWindow.setFrame(rect, display: true)
            }
        }
    }

    /// Reference to this window's CommandPalette for global shortcuts
    weak var commandPalette: CommandPalette?

    // MARK: - Incognito/Ephemeral State
    
    /// Whether this window is an incognito/private browsing window
    var isIncognito: Bool = false
    
    /// The ephemeral profile associated with this incognito window
    /// Only set when isIncognito is true
    var ephemeralProfile: Profile?
    
    /// Whether the download warning has been shown in this incognito session
    var hasShownDownloadWarning: Bool = false
    
    // MARK: - Tab Model (TabsController)

    /// The space this window shows.
    var spaceID: UUID?

    /// The selected item per space in this window.
    var selectedItemBySpace: [UUID: UUID] = [:]

    /// Items this window selected in each space, most recent last. Closing the selected item
    /// returns to the one before it. In memory only.
    var recentItemsBySpace: [UUID: [UUID]] = [:]

    /// Spaces whose last open tab was closed in this window. Returning to one shows the empty
    /// space instead of selecting its first tab. In memory only.
    var emptiedSpaces: Set<UUID> = []

    /// The selected item in the current space. There is no global current tab.
    var selectedItemID: UUID? {
        spaceID.flatMap { selectedItemBySpace[$0] }
    }

    /// The split pair shown in this window, if any.
    var split: SplitRecord?

    /// The profile whose favorites and data store this window uses (its space's profile).
    var profileID: UUID?

    /// A private window's in-memory tree: one profile record for the ephemeral profile and one
    /// space. Never saved. nil for regular windows.
    var privateTree: TabTree?

    /// Live pages of a private window, by item id.
    var privateSessions: [UUID: PageSession] = [:]

    /// A private window's reopen-closed history, newest last. Memory only.
    var privateClosed: [ClosedEntry] = []

    init(id: UUID = UUID()) {
        self.id = id
    }
    
    /// Increment the compositor version to trigger UI updates
    func refreshCompositor() {
        compositorVersion += 1
    }
}

/// Toast information specific to a window
struct WindowToastInfo: Equatable {
    let message: String
    let timestamp: Date
    let duration: TimeInterval
    
    init(message: String, duration: TimeInterval = 2.0) {
        self.message = message
        self.timestamp = Date()
        self.duration = duration
    }
}
