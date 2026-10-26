#if canImport(AppKit)

import SwiftUI

// Nook: a trackpad pager modeled on Arc's. Pages sit on one strip; fingers move it at half
// speed with rubber-banded ends, lifting commits the selection at once, and a critically
// damped spring settles it on the render server so a new swipe can grab it mid-flight.
extension PlatformPageView: NSViewRepresentable {

    func makeNSView(context: Context) -> SwipePagerView {
        let view = SwipePagerView()
        view.coordinator = context.coordinator
        context.coordinator.pager = view
        context.coordinator.onSwipe = context.environment.pageSwipeAction
        context.coordinator.show(selection)
        return view
    }

    func updateNSView(_ view: SwipePagerView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.onSwipe = context.environment.pageSwipeAction
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
        var onSwipe: ((PageSwipePosition?) -> Void)?
        private var views: [SelectionValue: PageHostView] = [:]

        init(_ parent: PlatformPageView) {
            self.parent = parent
        }

        var current: SelectionValue? { pager?.selectedValue }

        func view(for value: SelectionValue) -> PageHostView {
            if let view = views[value] {
                view.rootView = parent.content(value)
                return view
            }
            let view = PageHostView(rootView: parent.content(value))
            views[value] = view
            return view
        }

        /// Every page in order, walked out from the selection.
        func order() -> [SelectionValue] {
            var before: [SelectionValue] = []
            var cursor = parent.selection
            while let previous = parent.previous(cursor), before.count < 256 {
                before.append(previous)
                cursor = previous
            }
            var after: [SelectionValue] = []
            cursor = parent.selection
            while let next = parent.next(cursor), after.count < 256 {
                after.append(next)
                cursor = next
            }
            return before.reversed() + [parent.selection] + after
        }

        func show(_ value: SelectionValue) {
            pager?.move(to: value, animated: false)
        }

        func refresh(to value: SelectionValue, animated: Bool) {
            pager?.move(to: value, animated: animated)
        }

        func commit(_ value: SelectionValue) {
            parent.selection = value
        }

        func evict(keeping keep: Set<SelectionValue>) {
            views = views.filter { keep.contains($0.key) }
        }
    }

    // MARK: - Pager

    final class SwipePagerView: NSView {
        weak var coordinator: Coordinator?

        private let strip = NSView()
        private var pages: [SelectionValue] = []
        private var selected = 0
        private var attached: [Int: PageHostView] = [:]
        // Strip offset in points; page i starts at i * width. Unclamped while dragging.
        private var raw: CGFloat = 0
        private var lastWidth: CGFloat = 0
        private var motion: Motion = .idle
        private var motionID: UInt = 0
        private var wheel = Wheel()

        private struct Drag {
            var samples: [(time: TimeInterval, position: CGFloat)] = []
            var detent: Int
            let adopted: Bool
        }

        private struct Settle {
            let target: CGFloat
        }

        private struct Wheel {
            var cumulative: CGFloat = 0
            var lastEvent: CFTimeInterval = 0
            var lastTrigger: CFTimeInterval = -1
        }

        private enum Motion {
            case idle
            case dragging(Drag)
            case settling(Settle)
        }

        var isTracking: Bool {
            if case .idle = motion { return false }

            return true
        }

        var selectedValue: SelectionValue? {
            pages.indices.contains(selected) ? pages[selected] : nil
        }

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            strip.wantsLayer = true
            addSubview(strip)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        private var width: CGFloat { bounds.width }
        private var maxPosition: CGFloat { CGFloat(max(pages.count - 1, 0)) * width }

        // MARK: Selection

        /// Shows `value`, sliding the strip there when `animated`.
        func move(to value: SelectionValue, animated: Bool) {
            guard let coordinator else { return }

            pages = coordinator.order()
            guard let index = pages.firstIndex(of: value) else { return }

            if case .dragging = motion {
                guard index != selected else { return }
                // A keyboard or menu switch ends the swipe in place.
                motion = .idle
                report(nil)
            }

            // Our own commit at lift lands here while the strip is still settling.
            if index == selected, isTracking || attached[index] != nil {
                attach(index, refresh: true)
                return
            }

            selected = index
            if animated, window != nil, width > 0 {
                settle(to: index, velocity: 0)
            } else {
                snap()
            }
        }

        private func snap() {
            stopSettling()
            motion = .idle
            raw = CGFloat(selected) * width
            attach(selected)
            detach(keeping: [selected])
            relayout()
            evict()
        }

        private func evict() {
            guard let coordinator, !pages.isEmpty else { return }

            let keep = Set([selected - 1, selected, selected + 1].filter(pages.indices.contains).map { pages[$0] })
            coordinator.evict(keeping: keep)
        }

        // MARK: Layout

        override func layout() {
            super.layout()

            if width != lastWidth {
                // A resize mid-motion lands on the selected page rather than at a stale offset.
                if case .dragging = motion { report(nil) }
                lastWidth = width
                snap()
                return
            }
            relayout()
        }

        private func relayout() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            strip.frame = NSRect(x: -Self.rubberBand(raw, max: maxPosition), y: 0,
                                 width: CGFloat(max(pages.count, 1)) * width, height: bounds.height)
            for (index, view) in attached {
                view.frame = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
            }
            CATransaction.commit()
        }

        // Content is set once per attach; only a SwiftUI update refreshes it, never a scroll event.
        private func attach(_ index: Int, refresh: Bool = false) {
            guard pages.indices.contains(index), let coordinator else { return }
            if !refresh, let view = attached[index], view.superview === strip { return }

            let view = coordinator.view(for: pages[index])
            attached[index] = view
            view.frame = NSRect(x: CGFloat(index) * width, y: 0, width: width, height: bounds.height)
            if view.superview !== strip { strip.addSubview(view) }
        }

        private func attach(range: ClosedRange<CGFloat>) {
            guard width > 0 else { return }

            let low = Int((range.lowerBound / width).rounded(.down))
            let high = Int((range.upperBound / width).rounded(.up))
            for index in max(low, 0)...max(min(high, pages.count - 1), 0) { attach(index) }
        }

        private func detach(keeping keep: Set<Int>) {
            for (index, view) in attached where !keep.contains(index) {
                if view.superview === strip { view.removeFromSuperview() }
                attached[index] = nil
            }
        }

        // MARK: Gestures

        override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
            axis == .horizontal
        }

        override func scrollWheel(with event: NSEvent) {
            let horizontal = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)

            if !event.hasPreciseScrollingDeltas || (event.phase == [] && event.momentumPhase == []) {
                if !(horizontal && wheelPage(event)) { super.scrollWheel(with: event) }
                return
            }

            guard event.phase == .began, horizontal,
                  NSEvent.isSwipeTrackingFromScrollEventsEnabled,
                  beginDrag()
            else {
                // The momentum that follows a swipe belongs to the swipe.
                if horizontal, event.momentumPhase != [] { return }
                return super.scrollWheel(with: event)
            }

            track()
        }

        func beginDrag() -> Bool {
            if case .dragging = motion { return false }

            guard let coordinator, width > 0 else { return false }

            pages = coordinator.order()
            guard pages.count > 1 else { return false }

            let adopted = adoptSettle()
            let nearest = Self.nearest(raw, width: width, count: pages.count)
            motion = .dragging(Drag(detent: nearest, adopted: adopted))
            let shown = Self.rubberBand(raw, max: maxPosition)
            attach(range: (shown - width)...(shown + 2 * width))
            relayout()

            return true
        }

        // Arc's pager runs its own loop while fingers are down, so every event of the swipe
        // reaches it whichever view is under the pointer.
        private func track() {
            guard let window else {
                motion = .idle
                return
            }

            let mask: NSEvent.EventTypeMask = [.scrollWheel, .swipe, .mouseMoved, .mouseExited, .keyDown, .keyUp]
            while case .dragging = motion,
                  let event = window.nextEvent(matching: mask, until: .distantFuture, inMode: .eventTracking, dequeue: true) {
                if event.type == .scrollWheel {
                    drag(event.phase, delta: event.scrollingDeltaX, time: event.timestamp)
                } else {
                    NSApp.sendEvent(event)
                }
            }
        }

        func drag(_ phase: NSEvent.Phase, delta: CGFloat, time: TimeInterval) {
            guard case .dragging(var drag) = motion else { return }

            switch phase {
            case .changed:
                raw += delta * -0.5
                drag.samples.append((time, raw))
                drag.samples.removeAll { time - $0.time > Self.velocityWindow }

                let nearest = Self.nearest(raw, width: width, count: pages.count)
                // Arc plays .alignment; .levelChange is the firmest pattern AppKit offers.
                if nearest != drag.detent {
                    drag.detent = nearest
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
                }

                motion = .dragging(drag)
                let shown = Self.rubberBand(raw, max: maxPosition)
                attach(range: shown...(shown + width))
                relayout()
                reportPosition(shown)
            case .ended:
                var velocity = Self.velocity(drag.samples)
                let target = Self.target(position: raw, velocity: velocity, width: width,
                                         count: pages.count, adopted: drag.adopted)
                // Carry the flick into the spring only when it heads for the target.
                if (velocity >= 0) == (CGFloat(target) * width < raw) { velocity = 0 }

                let changed = target != selected
                selected = target
                settle(to: target, velocity: velocity)
                if changed { commitAfterSlideStarts(pages[target]) }
            case .cancelled, []:
                settle(to: selected, velocity: 0)
            default:
                break
            }
        }

        /// Wheel paging: a burst of horizontal wheel movement flips one page, with a cooldown.
        private func wheelPage(_ event: NSEvent) -> Bool {
            guard let coordinator else { return false }
            if case .dragging = motion { return true }

            let now = CACurrentMediaTime()
            guard now - wheel.lastTrigger > 0.25 else { return true }

            if now - wheel.lastEvent > 0.05 { wheel.cumulative = 0 }
            wheel.lastEvent = now
            wheel.cumulative += event.scrollingDeltaX
            guard abs(wheel.cumulative) > 1 else { return true }

            var forward = wheel.cumulative < 0
            if event.isDirectionInvertedFromDevice { forward.toggle() }
            wheel.cumulative = 0
            wheel.lastTrigger = now

            pages = coordinator.order()
            let target = selected + (forward ? 1 : -1)
            guard pages.indices.contains(target) else { return true }

            selected = target
            settle(to: target, velocity: 0)
            commitAfterSlideStarts(pages[target])
            return true
        }

        /// Hands the slide to the render server before the switch's main-thread work, which
        /// otherwise held the strip still for its length. The page still changes as it starts.
        private func commitAfterSlideStarts(_ value: SelectionValue) {
            CATransaction.flush()
            coordinator?.commit(value)
        }

        // MARK: Settling

        private func settle(to index: Int, velocity: CGFloat) {
            guard width > 0 else { return snap() }

            adoptSettle()
            motionID &+= 1
            let id = motionID
            let target = CGFloat(index) * width
            let offsets = Self.springOffsets(from: raw - target, velocity: velocity)
            let shownNow = Self.rubberBand(raw, max: maxPosition)

            attach(range: min(shownNow, target)...(max(shownNow, target) + width))
            raw = target
            motion = .settling(Settle(target: target))
            report(nil)

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.motionID == id else { return }
                    self.motion = .idle
                    self.detach(keeping: [self.selected])
                    self.evict()
                }
            }
            relayout()
            if offsets.count > 1 {
                // Additive keyframes of the strip's x, sampled at 240 Hz as Arc does.
                let animation = CAKeyframeAnimation(keyPath: "position.x")
                animation.isAdditive = true
                animation.values = offsets.map { target - Self.rubberBand(target + $0, max: maxPosition) }
                animation.keyTimes = offsets.indices.map { NSNumber(value: Double($0) / Double(offsets.count - 1)) }
                animation.duration = Double(offsets.count - 1) * Self.sampleStep
                animation.calculationMode = .linear
                strip.layer?.add(animation, forKey: "settle")
            }
            CATransaction.commit()
        }

        /// Takes over a settle in flight at its on-screen position. Returns whether one was running.
        @discardableResult
        private func adoptSettle() -> Bool {
            guard case .settling(let settle) = motion else { return false }

            motionID &+= 1
            if let layer = strip.layer, let presented = layer.presentation() {
                let shown = settle.target - (presented.position.x - layer.position.x)
                raw = Self.inverseRubberBand(shown, max: maxPosition)
            }
            stopSettling()
            motion = .idle
            relayout()

            return true
        }

        private func stopSettling() {
            strip.layer?.removeAnimation(forKey: "settle")
        }

        // MARK: Reporting

        private func reportPosition(_ shown: CGFloat) {
            guard width > 0, !pages.isEmpty else { return }

            let fraction = min(max(shown / width, 0), CGFloat(pages.count - 1))
            let floor = Int(fraction.rounded(.down))
            let ceil = min(floor + 1, pages.count - 1)
            report(PageSwipePosition(from: AnyHashable(pages[floor]), to: AnyHashable(pages[ceil]),
                                     progress: Double(fraction - CGFloat(floor))))
        }

        private func report(_ position: PageSwipePosition?) {
            coordinator?.onSwipe?(position)
        }

        // MARK: Arc's constants

        static var velocityWindow: TimeInterval { 0.1 }
        static var flingVelocity: CGFloat { 5 }
        static var springResponse: Double { 0.25 }
        static var sampleStep: Double { 1.0 / 240 }

        /// Arc's end resistance: 255 points at most past either end.
        static func rubberBand(_ raw: CGFloat, max upper: CGFloat) -> CGFloat {
            let clamped = min(max(raw, 0), upper)
            let over = abs(raw - clamped)
            guard over > 0 else { return raw }

            return clamped + (raw < clamped ? -1 : 1) * 255 * (1 - 1 / (over * 0.15 / 255 + 1))
        }

        static func inverseRubberBand(_ shown: CGFloat, max upper: CGFloat) -> CGFloat {
            let clamped = min(max(shown, 0), upper)
            let over = min(abs(shown - clamped), 254.9)
            guard over > 0 else { return shown }

            return clamped + (shown < clamped ? -1 : 1) * over * 255 / ((255 - over) * 0.15)
        }

        static func nearest(_ position: CGFloat, width: CGFloat, count: Int) -> Int {
            min(max(Int((position / width).rounded()), 0), count - 1)
        }

        /// Points per second over the last 100 ms of samples.
        static func velocity(_ samples: [(time: TimeInterval, position: CGFloat)]) -> CGFloat {
            guard let first = samples.first, let last = samples.last else { return 0 }

            let elapsed = last.time - first.time
            guard elapsed > 0, elapsed < velocityWindow else { return 0 }

            return (last.position - first.position) / elapsed
        }

        /// Arc's page choice at lift: any flick moves one page its way, otherwise the nearest page.
        static func target(position: CGFloat, velocity: CGFloat, width: CGFloat, count: Int, adopted: Bool) -> Int {
            guard count > 0, width > 0 else { return 0 }
            guard position >= 0 else { return 0 }

            let floor = min(Int((position / width).rounded(.down)), count - 1)
            let pick: Int
            if abs(velocity) >= flingVelocity {
                pick = adopted ? floor + (velocity > 0 ? 1 : -1) : (velocity > 0 ? floor + 1 : floor)
            } else {
                pick = Int((position / width).rounded())
            }

            return min(max(pick, floor - 1, 0), floor + 1, count - 1)
        }

        /// A critically damped spring from `offset` toward 0, sampled at 240 Hz until it rests.
        static func springOffsets(from offset: CGFloat, velocity: CGFloat) -> [CGFloat] {
            let omega = 2 * Double.pi / springResponse
            let x0 = Double(offset), v0 = Double(velocity)
            var offsets: [CGFloat] = []
            var t = 0.0
            while t < 2 {
                let decay = exp(-omega * t)
                let x = (x0 + (v0 + omega * x0) * t) * decay
                let v = (v0 - omega * (v0 + omega * x0) * t) * decay
                offsets.append(CGFloat(x))
                if t > 0, abs(x) < 0.1, abs(v) < 1 { break }
                t += sampleStep
            }
            offsets[offsets.count - 1] = 0

            return offsets
        }
    }

    // Owns its frame outside SwiftUI so selection updates cannot interrupt the strip.
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
