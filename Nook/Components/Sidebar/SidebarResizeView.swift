// Licensed under GPL-3.0. See LICENSE.
import AppKit
import SwiftUI
import NookDesign
import NookWeb
import NookUI

/// Native cursor ownership keeps the resize cursor stable over the sidebar edge.
struct SidebarResizeView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookSettings) private var settings
    @Environment(\.nookUsesDefaultSpaceTheme) private var usesDefaultTheme
    @Environment(\.colorScheme) private var colorScheme
    @State private var startingWidth: CGFloat = 0
    @State private var sessionID = UUID().uuidString

    private var indicatorColor: NSColor {
        if usesDefaultTheme {
            return NSColor(colorScheme == .dark
                ? NookDesign.SidebarChrome.defaultResizeDark
                : NookDesign.SidebarChrome.defaultResizeLight)
        }
        return NSColor(browserManager.accentColor).withAlphaComponent(0.8)
    }

    var body: some View {
        SidebarResizeHandle(
            color: indicatorColor,
            onHover: { windowState.isSidebarResizeHovered = $0 },
            onStart: {
                guard windowState.isSidebarVisible,
                      DragLockManager.shared.startDrag(ownerID: sessionID) else { return false }
                startingWidth = windowState.sidebarWidth
                return true
            },
            onDrag: { delta in
                let direction: CGFloat = settings.sidebarPosition == .right ? -1 : 1
                let width = min(520, max(NookDesign.Size.sidebarMin, startingWidth + delta * direction))
                guard width != windowState.sidebarWidth else { return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    // Do not broadcast BrowserManager.objectWillChange on every mouse event.
                    windowState.sidebarWidth = width
                    windowState.sidebarContentWidth = max(width - 16, 0)
                }
            },
            onEnd: {
                browserManager.updateSidebarWidth(windowState.sidebarWidth, for: windowState)
                browserManager.saveSidebarWidthToDefaults()
                DragLockManager.shared.endDrag(ownerID: sessionID)
            },
            onReset: {
                browserManager.updateSidebarWidth(250, for: windowState)
                browserManager.saveSidebarWidthToDefaults()
            }
        )
        .frame(width: 8)
        .padding(.vertical, 10)
        .onDisappear {
            windowState.isSidebarResizeHovered = false
            DragLockManager.shared.endDrag(ownerID: sessionID)
        }
    }
}

private struct SidebarResizeHandle: NSViewRepresentable {
    var color: NSColor
    var onHover: (Bool) -> Void
    var onStart: () -> Bool
    var onDrag: (CGFloat) -> Void
    var onEnd: () -> Void
    var onReset: () -> Void

    func makeNSView(context: Context) -> Handle { Handle() }
    func updateNSView(_ view: Handle, context: Context) {
        view.callbacks = self
        view.updateIndicator()
    }

    final class Handle: NSView {
        var callbacks: SidebarResizeHandle?
        private var tracking: NSTrackingArea?
        private var hovered = false
        private var dragging = false
        private var startX: CGFloat = 0
        private var mouseMonitor: Any?
        private var waitsForPointerMovement = false
        private var pendingAppearance: DispatchWorkItem?
        private let indicator = CALayer()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            indicator.cornerRadius = 2
            indicator.opacity = 0
            layer?.addSublayer(indicator)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            updateIndicator()
        }

        func updateIndicator() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            indicator.frame = bounds.insetBy(dx: 2, dy: 0)
            indicator.backgroundColor = callbacks?.color.cgColor
            CATransaction.commit()
        }

        override var mouseDownCanMoveWindow: Bool { false }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
            mouseMonitor = nil
            guard let window else { return }
            // Receive movement outside the handle too. Tracking-area exit events can
            // be lost when SwiftUI moves the handle during a drag.
            window.acceptsMouseMovedEvents = true
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
                guard let self else { return event }
                if !self.dragging {
                    self.waitsForPointerMovement = false
                    self.setHovered(self.containsPointer(event))
                }
                return event
            }
        }

        private func containsPointer(_ event: NSEvent) -> Bool {
            guard let window, event.window === window, window.isKeyWindow else { return false }
            return bounds.intersection(visibleRect).contains(convert(event.locationInWindow, from: nil))
        }

        private func setHovered(_ inside: Bool) {
            guard inside != hovered else { return }
            hovered = inside
            callbacks?.onHover(inside || dragging)
            (inside || dragging ? NSCursor.resizeLeftRight : NSCursor.arrow).set()
            pendingAppearance?.cancel()
            pendingAppearance = nil
            if dragging {
                setIndicatorVisible(true, duration: 0)
            } else if inside {
                let work = DispatchWorkItem { [weak self] in
                    guard let self, self.hovered, !self.dragging else { return }
                    self.setIndicatorVisible(true, duration: 0.20)
                }
                pendingAppearance = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.20, execute: work)
            } else {
                setIndicatorVisible(false, duration: 0.18)
            }
        }

        private func setIndicatorVisible(_ visible: Bool, duration: CFTimeInterval) {
            let target: Float = visible ? 1 : 0
            let current = indicator.presentation()?.opacity ?? indicator.opacity
            indicator.removeAnimation(forKey: "hoverFade")
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            indicator.opacity = target
            CATransaction.commit()
            if duration > 0, current != target {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = current
                fade.toValue = target
                fade.duration = duration
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                indicator.add(fade, forKey: "hoverFade")
            }
        }

        deinit {
            pendingAppearance?.cancel()
            if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        }

        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect, .enabledDuringMouseDrag], owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }
        override func cursorUpdate(with event: NSEvent) {
            if dragging || containsPointer(event) { NSCursor.resizeLeftRight.set() }
        }
        override func mouseEntered(with event: NSEvent) {
            guard !dragging, !waitsForPointerMovement else { return }
            setHovered(containsPointer(event))
        }
        override func mouseExited(with event: NSEvent) { setHovered(false) }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { callbacks?.onReset(); return }
            dragging = callbacks?.onStart() ?? false
            startX = NSEvent.mouseLocation.x
            if dragging {
                pendingAppearance?.cancel()
                pendingAppearance = nil
                callbacks?.onHover(true)
                setIndicatorVisible(true, duration: 0)
            }
            updateIndicator()
        }
        override func mouseDragged(with event: NSEvent) {
            guard dragging else { return }
            NSCursor.resizeLeftRight.set()
            callbacks?.onDrag(NSEvent.mouseLocation.x - startX)
        }
        override func mouseUp(with event: NSEvent) {
            guard dragging else { return }
            dragging = false
            waitsForPointerMovement = true
            hovered = false
            pendingAppearance?.cancel()
            pendingAppearance = nil
            callbacks?.onHover(false)
            NSCursor.arrow.set()
            setIndicatorVisible(false, duration: 0.18)
            updateIndicator()
            callbacks?.onEnd()
            // Layout and tracking-area updates cannot re-show the handle after release.
            // Only a subsequent physical mouse movement may activate hover again.
        }

    }
}
