// Licensed under GPL-3.0. See LICENSE.
// HoverTracking.swift
// NookUI
//
// Replaces SwiftUI's .onHover with NSTrackingArea-based hover detection.
// SwiftUI's .onHover causes expensive recursive view-tree hit-testing
// (MultiViewResponder.containsGlobalPoints) on every mouse move.
// NSTrackingArea delegates hover detection to AppKit, bypassing the traversal.

import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)

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
    private var isHovered = false

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
        // AppKit sends no mouseExited for an area removed while the pointer is inside it, so a
        // relayout under the cursor would leave the row hovered until it was entered again.
        resyncHover()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        resyncHover()
    }

    /// Derives hover from where the pointer actually is, for the cases no enter/exit arrives.
    private func resyncHover() {
        guard let window, window.isKeyWindow else {
            setHover(false, deferred: true)
            return
        }
        let point = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHover(bounds.contains(point), deferred: true)
    }

    /// `deferred` keeps a resync out of the layout pass that triggered it; real enter and exit
    /// events stay synchronous so hover never lags a frame behind the pointer.
    private func setHover(_ value: Bool, deferred: Bool = false) {
        guard value != isHovered else { return }
        isHovered = value
        guard deferred else {
            onHover?(value)
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isHovered == value else { return }
            self.onHover?(value)
        }
    }

    override func mouseEntered(with event: NSEvent) {
        setHover(true)
    }

    override func mouseExited(with event: NSEvent) {
        setHover(false)
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

#else

/// Hover is a pointer notion; on iOS SwiftUI's own `.onHover` is cheap and only fires
/// with a connected pointer.
private struct HoverTrackingModifier: ViewModifier {
    let onHover: (Bool) -> Void

    func body(content: Content) -> some View {
        content.onHover(perform: onHover)
    }
}

#endif

extension View {
    /// Drop-in replacement for `.onHover` that uses `NSTrackingArea` instead of
    /// SwiftUI's built-in hover hit-testing, avoiding expensive view-tree traversal.
    public func onHoverTracking(perform action: @escaping (Bool) -> Void) -> some View {
        modifier(HoverTrackingModifier(onHover: action))
    }
}
