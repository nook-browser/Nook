#if canImport(AppKit)

import SwiftUI

// Nook: a trackpad pager of its own instead of NSPageController. The system pager eases each
// swipe out with its own momentum after the fingers lift; here the lift hands off to a short
// fixed animation.
extension PlatformPageView: NSViewRepresentable {

    func makeNSView(context: Context) -> SwipePagerView {
        let view = SwipePagerView()
        view.coordinator = context.coordinator
        context.coordinator.pager = view
        context.coordinator.show(selection)
        return view
    }

    func updateNSView(_ view: SwipePagerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.refresh(to: selection, animated: context.transaction.animation != nil)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator {
        var parent: PlatformPageView
        weak var pager: SwipePagerView?
        private(set) var current: SelectionValue?
        private var views: [SelectionValue: PageHostView] = [:]

        init(_ parent: PlatformPageView) {
            self.parent = parent
        }

        func view(for value: SelectionValue) -> PageHostView {
            if let view = views[value] {
                view.rootView = parent.content(value)
                return view
            }
            let view = PageHostView(rootView: parent.content(value))
            views[value] = view
            return view
        }

        /// Shows `value` with no animation and drops pages that are no longer neighbours.
        func show(_ value: SelectionValue) {
            current = value
            let keep = Set([value, parent.previous(value), parent.next(value)].compactMap { $0 })
            views = views.filter { keep.contains($0.key) }
            pager?.present(view(for: value))
        }

        func refresh(to value: SelectionValue, animated: Bool) {
            // Our own early commit must leave the moving views intact. A different
            // selection (keyboard or menu) supersedes the gesture immediately.
            if pager?.isTracking == true {
                if value != current { show(value) }

                return
            }

            guard value != current else {
                if let current { _ = view(for: current) }
                return
            }
            guard animated, let pager, let from = current else { return show(value) }

            let forward = parent.next(from) == value
            current = value

            pager.animate(to: view(for: value), forward: forward) { [weak self] in
                guard let self else { return }

                self.show(self.parent.selection)
            }
        }

        func neighbour(forward: Bool) -> SelectionValue? {
            guard let current else { return nil }
            return forward ? parent.next(current) : parent.previous(current)
        }

        func commit(_ value: SelectionValue) {
            // Commit browsing state now. The pager owns the remaining visual motion.
            current = value
            parent.selection = value
        }
    }

    // MARK: - Views

    final class SwipePagerView: NSView {
        weak var coordinator: Coordinator?
        private var page: PageHostView?
        // Slots are relative to the selected page. Keep outgoing pages until they
        // settle offscreen, including when another swipe begins before that happens.
        private var pages: [PageHostView: Int] = [:]
        private var motion: Motion = .idle
        private var motionID: UInt = 0

        private struct Drag {
            let previous: SelectionValue?
            let next: SelectionValue?
            let width: CGFloat
            let startOffset: CGFloat
            var target: (value: SelectionValue, view: PageHostView, forward: Bool)?
            var samples: [(amount: CGFloat, time: TimeInterval)] = []
            var playedHaptic = false
        }

        private enum Motion {
            case idle
            case dragging(Drag)
            case settling
        }

        var isTracking: Bool {
            if case .idle = motion { return false }

            return true
        }

        private static var settle: TimeInterval { 0.18 }
        private static var curve: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.16, 1, 0.3, 1) }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        func present(_ view: PageHostView) {
            stopSettling()
            motion = .idle

            for old in pages.keys where old !== view {
                old.removeFromSuperview()
            }

            pages = [view: 0]
            page = view
            view.frame = bounds
            view.autoresizingMask = [.width, .height]

            if view.superview !== self { addSubview(view) }
        }

        override func layout() {
            super.layout()

            if !isTracking { page?.frame = bounds }
        }

        /// A programmatic change uses the same settling motion as a swipe.
        func animate(to view: PageHostView, forward: Bool, completion: @escaping () -> Void) {
            guard let page, !isTracking else { return completion() }

            let slot = forward ? 1 : -1

            place(view, at: slot, offset: page.frame.minX - bounds.minX)
            select(view, at: slot)
            run(completion: completion)
        }

        override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
            axis == .horizontal
        }

        override func scrollWheel(with event: NSEvent) {
            guard event.phase == .began,
                  event.hasPreciseScrollingDeltas,
                  NSEvent.isSwipeTrackingFromScrollEventsEnabled,
                  abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY),
                  beginGesture(), case .dragging(let drag) = motion
            else { return super.scrollWheel(with: event) }

            let gestureID = motionID

            // Positive amounts drag the page right, toward the previous space.
            event.trackSwipeEvent(
                options: [.lockDirection, .clampGestureAmount],
                dampenAmountThresholdMin: drag.next == nil ? 0 : -1,
                max: drag.previous == nil ? 0 : 1
            ) { [weak self] amount, phase, _, stop in
                guard let self, self.motionID == gestureID else {
                    stop.pointee = true

                    return
                }

                if phase == .ended || phase == .cancelled { stop.pointee = true }

                self.updateGesture(amount: amount, phase: phase, time: ProcessInfo.processInfo.systemUptime)
            }
        }

        // A new gesture may replace settling, but never an active finger gesture.
        @discardableResult
        func beginGesture() -> Bool {
            if case .dragging = motion { return false }

            guard let coordinator, let page else { return false }

            let previous = coordinator.neighbour(forward: false)
            let next = coordinator.neighbour(forward: true)

            guard previous != nil || next != nil, bounds.width > 0 else { return false }

            stopSettling()
            motion = .dragging(Drag(
                previous: previous, next: next, width: bounds.width,
                startOffset: page.frame.minX - bounds.minX))

            for view in pages.keys {
                view.autoresizingMask = []
            }

            return true
        }

        func updateGesture(amount: CGFloat, phase: NSEvent.Phase, time: TimeInterval) {
            guard case .dragging(var drag) = motion, let coordinator else { return }

            let forward = amount < 0
            let offset = drag.startOffset + amount * drag.width

            if amount != 0, drag.target?.forward != forward,
               let value = forward ? drag.next : drag.previous {
                let view = coordinator.view(for: value)

                drag.target = (value, view, forward)
                place(view, at: forward ? 1 : -1, offset: offset)
            }

            switch phase {
            case .began, .changed:
                drag.samples.append((amount, time))

                if drag.samples.count > 4 { drag.samples.removeFirst() }

                setOffset(offset)

                if !drag.playedHaptic, abs(amount) > 0.15 {
                    drag.playedHaptic = true
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }

                motion = .dragging(drag)
            case .ended, .cancelled:
                let velocity = Self.velocity(drag.samples)
                let commits = phase == .ended && drag.target.map {
                    $0.forward == (amount < 0)
                        && (abs(amount) > 0.3 || ($0.forward ? velocity < -0.8 : velocity > 0.8))
                } == true

                if let target = drag.target, commits {
                    select(target.view, at: target.forward ? 1 : -1)
                    run { coordinator.show(coordinator.parent.selection) }
                    coordinator.commit(target.value)
                } else {
                    run { coordinator.show(coordinator.parent.selection) }
                }
            default:
                break
            }
        }

        private func place(_ view: PageHostView, at slot: Int, offset: CGFloat) {
            // Reversing can reuse a page already visible from the previous swipe.
            // Its frame is moved with the others by setOffset, never reset to bounds.
            guard pages[view] == nil else { return }

            pages[view] = slot
            view.autoresizingMask = []
            view.frame = bounds.offsetBy(dx: offset + CGFloat(slot) * bounds.width, dy: 0)
            addSubview(view)
        }

        private func select(_ view: PageHostView, at slot: Int) {
            pages = pages.mapValues { $0 - slot }
            page = view
        }

        private func setOffset(_ offset: CGFloat) {
            for (view, slot) in pages {
                view.frame = bounds.offsetBy(dx: offset + CGFloat(slot) * bounds.width, dy: 0)
            }
        }

        private func stopSettling() {
            // Invalidate before cancellation: AppKit may complete the superseded
            // animation while its replacement is being installed.
            motionID &+= 1

            guard case .settling = motion else { return }

            let frames = pages.keys.map { view in
                (view, view.layer?.presentation()?.frame ?? view.frame)
            }

            // Stop through AppKit so its view and layer geometry stay synchronized.
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0

                for (view, frame) in frames {
                    view.animator().frame = frame
                }
            }
        }

        private func run(completion: @escaping () -> Void) {
            motionID &+= 1
            motion = .settling

            let animationID = motionID
            let width = bounds.width

            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.settle
                context.timingFunction = Self.curve

                for (view, slot) in pages {
                    view.animator().frame = bounds.offsetBy(dx: CGFloat(slot) * width, dy: 0)
                }
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.motionID == animationID else { return }

                    self.motion = .idle
                    completion()
                }
            }
        }

        /// Gesture amount per second over the last few samples, so a quick flick commits.
        private static func velocity(_ samples: [(amount: CGFloat, time: TimeInterval)]) -> CGFloat {
            guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }

            return (last.amount - first.amount) / (last.time - first.time)
        }
    }

    // Own the frame outside SwiftUI so page-selection updates cannot end the
    // original AppKit slide. Timing, easing, and frame animation stay in run().
    final class PageHostView: NSView {
        private let hostingView: HostingView

        var rootView: Content {
            get { hostingView.rootView }
            set { hostingView.rootView = newValue }
        }

        init(rootView: Content) {
            hostingView = HostingView(rootView: rootView)
            super.init(frame: .zero)
            wantsLayer = true
            hostingView.autoresizingMask = [.width, .height]
            addSubview(hostingView)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func layout() {
            super.layout()
            hostingView.frame = bounds
        }

        override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
            axis == .horizontal
        }
    }

    final class HostingView: NSHostingView<Content> {
        // Scroll views inside forward horizontal swipes up to the pager.
        override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
            axis == .horizontal
        }
    }
}

struct PlatformPageView_Mac_Previews: PreviewProvider {

    static var previews: some View {
        PageViewBasicExample()
            .pageViewStyle(.scroll)
    }
}

#endif
