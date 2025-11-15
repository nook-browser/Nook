//
//  WindowRegistry.swift
//  Nook
//
//  Tracks window states for cross-window coordination and command routing
//

import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
class WindowRegistry {
    /// All registered window states (ignored from observation to avoid actor isolation issues)
    @ObservationIgnored
    private var _windows: [UUID: BrowserWindowState] = [:]

    var windows: [UUID: BrowserWindowState] {
        get { _windows }
        set { _windows = newValue }
    }

    /// ID of the currently focused window (the only thing we actually observe)
    var activeWindowId: UUID?

    /// The currently focused window state (computed, not observed)
    var activeWindow: BrowserWindowState? {
        guard let id = activeWindowId else { return nil }
        return _windows[id]
    }

    /// Callback for window cleanup (set by whoever needs to clean up resources)
    @ObservationIgnored
    var onWindowClose: ((UUID) -> Void)?

    /// Callback for post-registration setup (e.g., setting TabManager reference)
    @ObservationIgnored
    var onWindowRegister: ((BrowserWindowState) -> Void)?

    /// Callback when active window changes
    @ObservationIgnored
    var onActiveWindowChange: ((BrowserWindowState) -> Void)?

    /// Register a new window
    func register(_ window: BrowserWindowState) {
        windows[window.id] = window
        onWindowRegister?(window)
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
        onActiveWindowChange?(window)
        print("🪟 [WindowRegistry] Active window: \(window.id)")
    }

    /// Get all windows as an array
    var allWindows: [BrowserWindowState] {
        Array(windows.values)
    }
}
