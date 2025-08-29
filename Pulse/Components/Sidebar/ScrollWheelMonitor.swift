import SwiftUI
import AppKit

// Captures horizontal trackpad scroll deltas within its bounds without blocking default scrolling.
struct ScrollWheelMonitor: NSViewRepresentable {
    var onBegin: (() -> Void)? = nil
    var onDelta: ((CGFloat) -> Void)? = nil
    var onEnd: (() -> Void)? = nil

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onBegin = onBegin
        view.onDelta = onDelta
        view.onEnd = onEnd
        return view
    }

    func updateNSView(_ nsView: MonitorView, context: Context) {
        nsView.onBegin = onBegin
        nsView.onDelta = onDelta
        nsView.onEnd = onEnd
    }

    final class MonitorView: NSView {
        var onBegin: (() -> Void)?
        var onDelta: ((CGFloat) -> Void)?
        var onEnd: (() -> Void)?
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            startMonitoring()
        }

        override func removeFromSuperview() {
            super.removeFromSuperview()
            stopMonitoring()
        }

        deinit { stopMonitoring() }

        private func startMonitoring() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self else { return event }
                guard event.window == self.window else { return event }
                // Restrict to this view's bounds in window space
                let localPoint = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(localPoint) else { return event }

                // Ignore momentum for determining threshold; treat only active finger scroll
                let isMomentum = !event.momentumPhase.isEmpty
                let phase = event.phase

                // Only consider mostly-horizontal gestures
                let dx = event.scrollingDeltaX
                let dy = event.scrollingDeltaY
                let isMostlyHorizontal = abs(dx) >= abs(dy)

                if (phase.contains(.mayBegin) || phase.contains(.began)) && isMostlyHorizontal {
                    onBegin?()
                }

                if !isMomentum && isMostlyHorizontal {
                    onDelta?(dx)
                }

                if phase.contains(.ended) && isMostlyHorizontal {
                    onEnd?()
                }

                // Always return the event so normal scrolling proceeds.
                return event
            }
        }

        private func stopMonitoring() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}
