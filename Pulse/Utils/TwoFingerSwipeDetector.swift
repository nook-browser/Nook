//
//  TwoFingerSwipeDetector.swift
//  Pulse
//
//  Detects Arc-like two-finger horizontal swipes by accumulating
//  precise horizontal scroll deltas and firing once per gesture.
//
//  It uses a local NSEvent monitor so vertical scrolling is passed
//  through to underlying views, and horizontal scroll can be swallowed
//  selectively while the pointer hovers the detector's area.
//

import AppKit
import SwiftUI

struct TwoFingerSwipeDetector: NSViewRepresentable {
    enum Direction { case left, right }

    var threshold: CGFloat = 80
    var onSwipe: (Direction) -> Void
    var onDelta: ((CGFloat) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> TrackingView {
        let view = TrackingView(frame: .zero)
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        view.coordinator = context.coordinator
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.coordinator = context.coordinator
        context.coordinator.detector = self
    }

    static func dismantleNSView(_ nsView: TrackingView, coordinator: Coordinator) {
        coordinator.detach()
    }

    final class Coordinator: NSObject {
        var detector: TwoFingerSwipeDetector
        private weak var view: TrackingView?
        private var monitor: Any?

        private var accumulated: CGFloat = 0
        private var didTrigger = false

        init(_ detector: TwoFingerSwipeDetector) {
            self.detector = detector
        }

        func attach(to view: TrackingView) {
            self.view = view
            // Tracking area handled by TrackingView
            addMonitor()
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
            view = nil
        }

        private func addMonitor() {
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self, let v = self.view else { return event }

                // Only consider when pointer is within our area and same window
                guard v.isPointerInside, event.window === v.window else { return event }

                let dx = event.scrollingDeltaX
                let dy = event.scrollingDeltaY

                self.detector.onDelta?(dx)

                // Treat primarily horizontal scroll as a swipe candidate
                let isHorizontal = abs(dx) > abs(dy)

                if !isHorizontal {
                    // Let vertical/diagonal events pass through
                    return event
                }

                // Gesture lifecycle gating
                if event.phase == .began || event.phase == .mayBegin {
                    accumulated = 0
                    didTrigger = false
                }
                if event.phase == .ended || event.phase == .cancelled || event.momentumPhase == .ended {
                    accumulated = 0
                    didTrigger = false
                    return nil // swallow end for cleanliness
                }

                if !didTrigger {
                    accumulated += dx
                    if abs(accumulated) >= detector.threshold {
                        didTrigger = true
                        detector.onSwipe(dx > 0 ? .right : .left)
                    }
                }

                // Swallow horizontal scroll while over the detector area
                return nil
            }
        }
    }

    final class TrackingView: NSView {
        weak var coordinator: Coordinator?
        private var trackingArea: NSTrackingArea?
        fileprivate var isPointerInside: Bool = false

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let ta = trackingArea { removeTrackingArea(ta) }
            let options: NSTrackingArea.Options = [
                .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect
            ]
            let ta = NSTrackingArea(rect: self.bounds, options: options, owner: self, userInfo: nil)
            addTrackingArea(ta)
            trackingArea = ta
        }

        override func mouseEntered(with event: NSEvent) {
            isPointerInside = true
        }

        override func mouseExited(with event: NSEvent) {
            isPointerInside = false
        }

        // Do not intercept pointer-based hit testing; allow underlying views to receive clicks
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
