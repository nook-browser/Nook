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
    @State private var startingWidth: CGFloat = 0
    @State private var sessionID = UUID().uuidString

    var body: some View {
        SidebarResizeHandle(
            color: NSColor(browserManager.accentColor).withAlphaComponent(0.8),
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
        view.needsDisplay = true
    }

    final class Handle: NSView {
        var callbacks: SidebarResizeHandle?
        private var tracking: NSTrackingArea?
        private var hovered = false
        private var dragging = false
        private var startX: CGFloat = 0
        override var mouseDownCanMoveWindow: Bool { false }
        override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .cursorUpdate, .activeInKeyWindow, .inVisibleRect], owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }
        override func cursorUpdate(with event: NSEvent) { NSCursor.resizeLeftRight.set() }
        override func mouseEntered(with event: NSEvent) {
            hovered = true
            callbacks?.onHover(true)
            NSCursor.resizeLeftRight.set()
            needsDisplay = true
        }
        override func mouseExited(with event: NSEvent) {
            hovered = false
            callbacks?.onHover(dragging)
            if !dragging { NSCursor.arrow.set() }
            needsDisplay = true
        }
        override func mouseDown(with event: NSEvent) {
            if event.clickCount == 2 { callbacks?.onReset(); return }
            dragging = callbacks?.onStart() ?? false
            startX = NSEvent.mouseLocation.x
            needsDisplay = true
        }
        override func mouseDragged(with event: NSEvent) {
            guard dragging else { return }
            NSCursor.resizeLeftRight.set()
            callbacks?.onDrag(NSEvent.mouseLocation.x - startX)
        }
        override func mouseUp(with event: NSEvent) {
            guard dragging else { return }
            dragging = false
            callbacks?.onEnd()
            callbacks?.onHover(hovered)
            if !hovered { NSCursor.arrow.set() }
            needsDisplay = true
        }
        override func draw(_ dirtyRect: NSRect) {
            guard hovered || dragging else { return }
            callbacks?.color.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 2, dy: 0), xRadius: 2, yRadius: 2).fill()
        }
    }
}
