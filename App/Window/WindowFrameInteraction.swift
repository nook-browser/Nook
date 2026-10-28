// Licensed under GPL-3.0. See LICENSE.
import AppKit

/// An event surface placed only over decorative window chrome, behind the browser's controls.
/// It owns no event monitor, so page and control events never travel through this handler.
@MainActor
final class WindowFrameInteractionView: NSView {
    var beginDrag: (() -> String?)?
    var endDrag: ((String) -> Void)?
    var clickAction: (() -> Void)?
    private var press: NSEvent?
    private var didDrag = false
    var doubleClickActionProvider: () -> String = { WindowFrameInteractionView.doubleClickAction() }
    private static let framesBeforeFill = NSMapTable<NSWindow, NSValue>.weakToStrongObjects()

    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        press = event
        didDrag = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let press, let window, event.window === window, !didDrag,
              hypot(event.locationInWindow.x - press.locationInWindow.x,
                    event.locationInWindow.y - press.locationInWindow.y) >= 3 else { return }
        // Once movement exceeds the threshold this press is no longer a click, even if
        // another drag owns the lock and prevents us from moving the window.
        didDrag = true
        let owner: String?
        if let beginDrag {
            guard let acquired = beginDrag() else { return }
            owner = acquired
        } else { owner = nil }
        defer { if let owner { endDrag?(owner) } }
        window.performDrag(with: press)
    }

    override func mouseUp(with event: NSEvent) {
        defer { press = nil; didDrag = false }
        guard press != nil, !didDrag,
              let window, event.window === window else { return }
        if event.clickCount == 2 {
            performDoubleClick(in: window, action: doubleClickActionProvider())
        } else {
            clickAction?()
        }
    }

    static func doubleClickAction(defaults: UserDefaults = .standard) -> String {
        if let action = defaults.string(forKey: "AppleActionOnDoubleClick") { return action }
        return defaults.bool(forKey: "AppleMiniaturizeOnDoubleClick") ? "Minimize" : "Zoom"
    }

    func performDoubleClick(in window: NSWindow, action: String) {
        guard !window.styleMask.contains(.fullScreen) else { return }
        switch action.lowercased() {
        case "minimize", "miniaturize": window.performMiniaturize(nil)
        case "none": break
        case "fill":
            guard window.styleMask.contains(.resizable), let screen = window.screen else { return }
            if let previous = Self.framesBeforeFill.object(forKey: window), window.frame == screen.visibleFrame {
                window.setFrame(previous.rectValue, display: true, animate: true)
                Self.framesBeforeFill.removeObject(forKey: window)
            } else {
                Self.framesBeforeFill.setObject(NSValue(rect: window.frame), forKey: window)
                window.setFrame(screen.visibleFrame, display: true, animate: true)
            }
        case "zoom", "maximize": window.performZoom(nil)
        default: break
        }
    }
}
