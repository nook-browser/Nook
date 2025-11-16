//
//  BrowserWindowState.swift
//  Nook
//
//  Created by Jonathan Caudill on 12/09/2024.
//

import SwiftUI
import Foundation

/// Represents the state of a single browser window, allowing multiple windows
/// to have independent tab selections and UI states while sharing the same tab data.
@MainActor
@Observable
class BrowserWindowState {
    /// Unique identifier for this window instance
    let id: UUID

    /// Currently active tab in this window
    var currentTabId: UUID?

    /// Currently active space in this window
    var currentSpaceId: UUID?

    /// Currently active profile in this window
    var currentProfileId: UUID?

    /// Active tab for each space in this window (spaceId -> tabId)
    var activeTabForSpace: [UUID: UUID] = [:]

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

    /// Whether the AI chat panel is visible in this window
    var isSidebarAIChatVisible: Bool = false

    /// Whether the command palette is visible in this window
    var isCommandPaletteVisible: Bool = false

    /// Whether the URL was recently copied (for toast feedback)
    var didCopyURL: Bool = false

    /// Frame of the URL bar within this window
    var urlBarFrame: CGRect = .zero

    /// Toast info for this window
    var toastInfo: WindowToastInfo?

    /// Profile switch toast payload for this window
    var profileSwitchToast: BrowserManager.ProfileSwitchToast?

    /// Presentation flag for the profile switch toast
    var isShowingProfileSwitchToast: Bool = false

    /// Compositor version counter for this window (incremented when tab ownership changes)
    var compositorVersion: Int = 0

    /// Reference to the actual NSWindow for this window state
    var window: NSWindow?

    /// Reference to TabManager for computed properties
    /// Set by BrowserManager during window registration
    weak var tabManager: TabManager?

    /// Reference to this window's CommandPalette for global shortcuts
    weak var commandPalette: CommandPalette?

    /// Computed property: the actual Space object for this window's current space
    var currentSpace: Space? {
        guard let tabManager = tabManager,
              let spaceId = currentSpaceId else { return nil }
        return tabManager.spaces.first(where: { $0.id == spaceId })
    }

    /// Computed property: gradient for the current space
    var gradient: SpaceGradient {
        currentSpace?.gradient ?? .default
    }

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
