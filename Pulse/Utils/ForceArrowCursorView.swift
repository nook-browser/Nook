//
//  ForceArrowCursorView.swift
//  Pulse
//
//  Created by Codex on 2025-09-15.
//

import AppKit
import SwiftUI

private final class ForceArrowCursorNSView: NSView {
    private var trackingArea: NSTrackingArea?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let options: NSTrackingArea.Options = [
            .activeAlways,
            .mouseEnteredAndExited,
            .mouseMoved,
            .inVisibleRect
        ]
        trackingArea = NSTrackingArea(rect: bounds, options: options, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
        NSCursor.arrow.set()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.arrow.set()
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        NSCursor.arrow.set()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        // Do not change cursor here; let underlying views manage it.
    }
}

struct ForceArrowCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = ForceArrowCursorNSView(frame: .zero)
        v.wantsLayer = true
        v.layer?.backgroundColor = NSColor.clear.cgColor
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension View {
    /// Ensures the arrow cursor while hovering this view's visual bounds without affecting hit testing.
    func alwaysArrowCursor() -> some View {
        self.overlay(ForceArrowCursorView().allowsHitTesting(false))
    }
}
