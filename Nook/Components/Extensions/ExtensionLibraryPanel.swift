//
//  ExtensionLibraryPanel.swift
//  Nook
//

import SwiftUI
import AppKit
import os

@available(macOS 15.5, *)
@MainActor
final class ExtensionLibraryPanelController {
    private var panel: NSPanel?
    private var localMonitor: Any?
    private var hostingView: NSHostingView<AnyView>?
    private var isShowingInProgress = false

    private let panelWidth: CGFloat = 300
    private static let logger = Logger(subsystem: "com.nook.browser", category: "ExtensionLibraryPanel")

    var isVisible: Bool {
        panel?.isVisible ?? false
    }

    func toggle(
        anchorFrame: CGRect,
        in window: NSWindow,
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        settings: NookSettingsService
    ) {
        if isVisible {
            dismiss()
        } else {
            show(anchorFrame: anchorFrame, in: window, browserManager: browserManager, windowState: windowState, settings: settings)
        }
    }

    func show(
        anchorFrame: CGRect,
        in window: NSWindow,
        browserManager: BrowserManager,
        windowState: BrowserWindowState,
        settings: NookSettingsService
    ) {
        let panel = self.panel ?? createPanel()
        self.panel = panel

        // Update SwiftUI content
        let content = ExtensionLibraryView(
            browserManager: browserManager,
            windowState: windowState,
            settings: settings,
            onDismiss: { [weak self] in self?.dismiss() }
        )

        if let hostingView = self.hostingView {
            hostingView.rootView = AnyView(content)
        } else {
            let hosting = NSHostingView(rootView: AnyView(content))
            hosting.translatesAutoresizingMaskIntoConstraints = false

            // Add vibrancy background
            let visualEffect = NSVisualEffectView()
            visualEffect.material = .hudWindow
            visualEffect.state = .active
            visualEffect.blendingMode = .behindWindow
            visualEffect.wantsLayer = true
            visualEffect.layer?.cornerRadius = 16
            visualEffect.layer?.masksToBounds = true
            visualEffect.translatesAutoresizingMaskIntoConstraints = false

            // Container with rounded corners and clipping
            let container = NSView()
            container.wantsLayer = true
            container.layer?.cornerRadius = 16
            container.layer?.masksToBounds = true
            container.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(visualEffect)
            container.addSubview(hosting)

            NSLayoutConstraint.activate([
                visualEffect.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                visualEffect.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                visualEffect.topAnchor.constraint(equalTo: container.topAnchor),
                visualEffect.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                hosting.topAnchor.constraint(equalTo: container.topAnchor),
                hosting.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])

            panel.contentView = container
            self.hostingView = hosting
        }

        // Size the panel — use a reasonable default if fittingSize is zero
        hostingView?.invalidateIntrinsicContentSize()
        let fittingSize = hostingView?.fittingSize ?? .zero
        let height = fittingSize.height > 10 ? min(fittingSize.height, 500) : 400
        let panelSize = CGSize(width: panelWidth, height: height)

        Self.logger.info("show() — anchorFrame=\(anchorFrame.debugDescription, privacy: .public), fittingSize=\(fittingSize.debugDescription, privacy: .public), panelSize=\(panelSize.debugDescription, privacy: .public)")

        // Position below the anchor, centered on the button's midpoint
        let anchorMidX = anchorFrame.midX
        let anchorScreenPoint = window.convertPoint(toScreen: CGPoint(
            x: anchorMidX,
            y: anchorFrame.minY
        ))
        var origin = CGPoint(
            x: anchorScreenPoint.x - panelWidth / 2,
            y: anchorScreenPoint.y - panelSize.height - 4
        )

        // Safety: ensure panel is on screen
        if let screen = window.screen ?? NSScreen.main {
            let visibleFrame = screen.visibleFrame
            origin.x = max(visibleFrame.minX, min(origin.x, visibleFrame.maxX - panelWidth))
            origin.y = max(visibleFrame.minY, min(origin.y, visibleFrame.maxY - panelSize.height))
        }

        Self.logger.info("show() — origin=\(origin.debugDescription, privacy: .public), window.frame=\(window.frame.debugDescription, privacy: .public)")

        panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)
        panel.orderFront(nil)
        panel.alphaValue = 1

        // Delay event monitor installation so the current click doesn't immediately dismiss
        isShowingInProgress = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.isShowingInProgress = false
            self?.installEventMonitor()
        }
    }

    func dismiss() {
        guard let panel = panel, panel.isVisible else { return }

        removeEventMonitor()
        panel.orderOut(nil)
        panel.alphaValue = 1
    }

    // MARK: - Private

    private func createPanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: CGSize(width: panelWidth, height: 400)),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        return panel
    }

    private func installEventMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self = self, let panel = self.panel, panel.isVisible else { return event }

            // Escape key dismisses
            if event.type == .keyDown && event.keyCode == 53 {
                self.dismiss()
                return event
            }

            // Check if click is inside the main panel
            if let eventWindow = event.window, eventWindow == panel {
                return event
            }

            // Also allow clicks inside any other floating non-activating NSPanel
            // (e.g. the more menu). These are our child panels.
            if let eventWindow = event.window,
               eventWindow is NSPanel,
               eventWindow.level == .floating,
               eventWindow.styleMask.contains(.nonactivatingPanel) {
                return event
            }

            // Click outside all our panels — dismiss
            self.dismiss()
            return event
        }
    }

    private func removeEventMonitor() {
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    deinit {
        let monitor = localMonitor
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
