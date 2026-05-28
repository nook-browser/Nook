// HoverTrackingView.swift
// Nook
//
// Replaces SwiftUI's .onHover with NSTrackingArea-based hover detection.
// SwiftUI's .onHover causes expensive recursive view-tree hit-testing
// (MultiViewResponder.containsGlobalPoints) on every mouse move.
// NSTrackingArea delegates hover detection to AppKit, bypassing the traversal.

import SwiftUI
import AppKit

// MARK: - NSViewRepresentable

struct HoverTrackingView: NSViewRepresentable {
    let onHover: (Bool) -> Void

    func makeNSView(context: Context) -> HoverTrackingNSView {
        let view = HoverTrackingNSView()
        view.onHover = onHover
        return view
    }

    func updateNSView(_ nsView: HoverTrackingNSView, context: Context) {
        nsView.onHover = onHover
    }
}

final class HoverTrackingNSView: NSView {
    var onHover: ((Bool) -> Void)?
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }
}

// MARK: - View Modifier

struct HoverTrackingModifier: ViewModifier {
    let onHover: (Bool) -> Void

    func body(content: Content) -> some View {
        content.background(
            HoverTrackingView(onHover: onHover)
        )
    }
}

extension View {
    /// Drop-in replacement for `.onHover` that uses `NSTrackingArea` instead of
    /// SwiftUI's built-in hover hit-testing, avoiding expensive view-tree traversal.
    func onHoverTracking(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(HoverTrackingModifier(onHover: action))
    }
}
