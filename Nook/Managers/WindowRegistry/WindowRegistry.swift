//
//  WindowRegistry.swift
//  Nook
//
//  Tracks window states for cross-window coordination and command routing
//

import Foundation
import SwiftUI

@MainActor
@Observable
class WindowRegistry {
    /// All registered window states
    private(set) var windows: [UUID: BrowserWindowState] = [:]

    /// ID of the currently focused window
    private(set) var activeWindowId: UUID?

    /// The currently focused window state
    var activeWindow: BrowserWindowState? {
        guard let id = activeWindowId else { return nil }
        return windows[id]
    }

    /// Callback for window cleanup (set by whoever needs to clean up resources)
    var onWindowClose: ((UUID) -> Void)?

    /// Register a new window
    func register(_ window: BrowserWindowState) {
        windows[window.id] = window
        print("🪟 [WindowRegistry] Registered window: \(window.id)")
    }

    /// Unregister a window when it closes
    func unregister(_ id: UUID) {
        // Call cleanup callback if set
        onWindowClose?(id)

        windows.removeValue(forKey: id)

        // If this was the active window, switch to another
        if activeWindowId == id {
            activeWindowId = windows.keys.first
        }

        print("🪟 [WindowRegistry] Unregistered window: \(id)")
    }

    /// Set the active (focused) window
    func setActive(_ window: BrowserWindowState) {
        activeWindowId = window.id
        print("🪟 [WindowRegistry] Active window: \(window.id)")
    }

    /// Get all windows as an array
    var allWindows: [BrowserWindowState] {
        Array(windows.values)
    }
}
