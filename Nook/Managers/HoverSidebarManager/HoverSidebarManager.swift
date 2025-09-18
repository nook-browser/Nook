//
//  HoverSidebarManager.swift
//  Nook
//
//  Created by Jonathan Caudill on 2025-09-13.
//

import SwiftUI
import AppKit

/// Manages reveal/hide of the overlay sidebar when the real sidebar is collapsed.
/// Uses a global mouse-move monitor to handle edge hover, including slight overshoot
/// beyond the window's left boundary.
final class HoverSidebarManager: ObservableObject {
    // MARK: - Published State
    @Published var isOverlayVisible: Bool = false

    // MARK: - Configuration
    /// Width inside the window that triggers reveal when hovered.
    var triggerWidth: CGFloat = 6
    /// Horizontal slack to the left of the window to catch slight overshoot.
    var overshootSlack: CGFloat = 12
    /// Extra horizontal margin past the overlay to keep it open while interacting.
    var keepOpenHysteresis: CGFloat = 16
    /// Vertical slack to allow small overshoot above/below the window frame.
    var verticalSlack: CGFloat = 24

    // MARK: - Dependencies
    weak var browserManager: BrowserManager?

    // MARK: - Monitors
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isActive: Bool = false

    // MARK: - Lifecycle
    func attach(browserManager: BrowserManager) {
        self.browserManager = browserManager
    }

    func start() {
        guard !isActive else { return }
        isActive = true

        // Local monitor for responsive updates while the app is active
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] event in
            self?.scheduleHandleMouseMovement()
            return event
        }

        // Global monitor to detect near-edge hovers even when cursor overshoots beyond window bounds
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged, .rightMouseDragged]) { [weak self] _ in
            self?.scheduleHandleMouseMovement()
        }
    }

    func stop() {
        isActive = false
        if let token = localMonitor { NSEvent.removeMonitor(token); localMonitor = nil }
        if let token = globalMonitor { NSEvent.removeMonitor(token); globalMonitor = nil }
        DispatchQueue.main.async { [weak self] in self?.isOverlayVisible = false }
    }

    deinit { stop() }

    // MARK: - Mouse Logic
    private func scheduleHandleMouseMovement() {
        // Ensure main-actor work since we touch NSApp/window and main-actor BrowserManager
        DispatchQueue.main.async { [weak self] in
            self?.handleMouseMovementOnMain()
        }
    }

    @MainActor
    private func handleMouseMovementOnMain() {
        guard let bm = browserManager, let activeState = bm.activeWindowState else { return }

        // Never show overlay while the real sidebar is visible
        if activeState.isSidebarVisible {
            if isOverlayVisible {
                isOverlayVisible = false
            }
            return
        }

        guard let window = NSApp.keyWindow else {
            if isOverlayVisible {
                isOverlayVisible = false
            }
            return
        }

        // Mouse and window frames are in screen coordinates
        let mouse = NSEvent.mouseLocation
        let frame = window.frame

        // Allow slight vertical overshoot
        let verticalOK = mouse.y >= frame.minY - verticalSlack && mouse.y <= frame.maxY + verticalSlack
        if !verticalOK {
            if isOverlayVisible {
                isOverlayVisible = false
            }
            return
        }

        // Use saved width when sidebar is collapsed to size the overlay and sticky zone
        let overlayWidth = max(activeState.sidebarWidth, activeState.savedSidebarWidth)

        // Edge zones in screen space
        let inTriggerZone = (mouse.x >= frame.minX - overshootSlack) && (mouse.x <= frame.minX + triggerWidth)
        let inKeepOpenZone = (mouse.x >= frame.minX) && (mouse.x <= frame.minX + overlayWidth + keepOpenHysteresis)

        let shouldShow = inTriggerZone || (isOverlayVisible && inKeepOpenZone)
        if shouldShow != isOverlayVisible {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOverlayVisible = shouldShow
            }
        }
    }
}
