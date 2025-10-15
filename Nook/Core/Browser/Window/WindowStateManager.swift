//
//  NookWindowState.swift
//  Nook
//
//  Extracted from BrowserManager.swift
//  Manages window state registry and lifecycle
//

import Foundation
import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class NookWindowState {
    /// Registry of all active window states
    private(set) var windowStates: [UUID: BrowserWindowState] = [:]

    /// The currently focused/active window state
    private(set) var activeWindowState: BrowserWindowState?

    /// Weak wrapper for NSView references stored per window
    private final class WeakNSView {
        weak var view: NSView?
        init(view: NSView?) { self.view = view }
    }

    /// Container views per window so the compositor can manage multiple windows safely
    private var compositorContainerViews: [UUID: WeakNSView] = [:]

    // MARK: - Window Registry

    /// Register a new window state
    func register(_ windowState: BrowserWindowState) {
        windowStates[windowState.id] = windowState
        print("🪟 [NookWindowState] Registered window state: \(windowState.id)")
    }

    /// Unregister a window state
    func unregister(_ windowId: UUID) {
        guard let windowState = windowStates[windowId] else { return }

        print("🧹 [NookWindowState] Unregistering window: \(windowId)")

        // Remove compositor container
        compositorContainerViews.removeValue(forKey: windowId)

        // Remove from registry
        windowStates.removeValue(forKey: windowId)

        // If this was the active window, clear it (caller should set new active)
        if activeWindowState?.id == windowId {
            activeWindowState = nil
        }

        print("✅ [NookWindowState] Unregistered window: \(windowId)")
    }

    /// Set the active window state
    func setActive(_ windowState: BrowserWindowState) {
        activeWindowState = windowState
    }

    /// Get window state by ID
    func getWindowState(_ windowId: UUID) -> BrowserWindowState? {
        return windowStates[windowId]
    }

    /// Get all window states
    func getAllWindowStates() -> [BrowserWindowState] {
        return Array(windowStates.values)
    }

    // MARK: - Compositor Container Management

    /// Set compositor container view for a window
    func setCompositorContainer(_ view: NSView?, for windowId: UUID) {
        if let view {
            compositorContainerViews[windowId] = WeakNSView(view: view)
        } else {
            compositorContainerViews.removeValue(forKey: windowId)
        }
    }

    /// Get compositor container view for a window
    func getCompositorContainer(for windowId: UUID) -> NSView? {
        if let view = compositorContainerViews[windowId]?.view {
            return view
        }
        // Clean up stale reference
        compositorContainerViews.removeValue(forKey: windowId)
        return nil
    }

    /// Get all compositor containers (cleaning up stale references)
    func getAllCompositorContainers() -> [(UUID, NSView)] {
        var result: [(UUID, NSView)] = []
        var staleIdentifiers: [UUID] = []

        for (windowId, entry) in compositorContainerViews {
            if let view = entry.view {
                result.append((windowId, view))
            } else {
                staleIdentifiers.append(windowId)
            }
        }

        // Clean up stale references
        for id in staleIdentifiers {
            compositorContainerViews.removeValue(forKey: id)
        }

        return result
    }

    /// Remove compositor container for a window
    func removeCompositorContainer(for windowId: UUID) {
        compositorContainerViews.removeValue(forKey: windowId)
    }

    /// Clear all state (useful for cleanup)
    func clearAll() {
        windowStates.removeAll()
        compositorContainerViews.removeAll()
        activeWindowState = nil
    }
    
    // MARK: - Active State Helpers
    var activeWindow: BrowserWindowState? {
        activeWindowState
    }

    func isActive(_ windowState: BrowserWindowState) -> Bool {
        activeWindowState?.id == windowState.id
    }

}

@MainActor
private struct NookWindowStateKey: EnvironmentKey {
    static let defaultValue: NookWindowState = NookWindowState()
}

extension EnvironmentValues {
    @MainActor var nookWindowState: NookWindowState {
        get { self[NookWindowStateKey.self] }
        set { self[NookWindowStateKey.self] = newValue }
    }
}
