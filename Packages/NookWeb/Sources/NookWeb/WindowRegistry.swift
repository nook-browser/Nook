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
public class WindowRegistry {
    /// All registered window states (ignored from observation to avoid actor isolation issues)
    @ObservationIgnored
    private var _windows: [UUID: BrowserWindowState] = [:]

    public var windows: [UUID: BrowserWindowState] {
        get { _windows }
        set { _windows = newValue }
    }

    public init() {}

    /// ID of the currently focused window (the only thing we actually observe)
    public var activeWindowId: UUID?

    /// The currently focused window state (computed, not observed)
    public var activeWindow: BrowserWindowState? {
        guard let id = activeWindowId else { return nil }
        return _windows[id]
    }

    /// Callback for window cleanup (set by whoever needs to clean up resources)
    @ObservationIgnored
    public var onWindowClose: ((UUID) -> Void)?

    /// Callback for post-registration setup (BrowserManager.setupWindowState)
    @ObservationIgnored
    public var onWindowRegister: ((BrowserWindowState) -> Void)?

    /// Callback when active window changes
    @ObservationIgnored
    public var onActiveWindowChange: ((BrowserWindowState) -> Void)?

    /// Register a new window
    public func register(_ window: BrowserWindowState) {
        windows[window.id] = window
        onWindowRegister?(window)
    }

    /// Unregister a window when it closes
    public func unregister(_ id: UUID) {
        // Both the window's close notification and SwiftUI's onDisappear call this.
        guard windows[id] != nil else { return }
        // Call cleanup callback if set
        onWindowClose?(id)

        windows.removeValue(forKey: id)

        // If this was the active window, switch to another
        if activeWindowId == id {
            activeWindowId = windows.keys.first
        }

    }

    /// Set the active (focused) window
    public func setActive(_ window: BrowserWindowState) {
        activeWindowId = window.id
        onActiveWindowChange?(window)
    }

    /// Get all windows as an array
    public var allWindows: [BrowserWindowState] {
        Array(windows.values)
    }
}
