// Licensed under GPL-3.0. See LICENSE.
//
// swiftc $(rg --files Nook/ThirdParty/BigUIPaging -g '*.swift') scripts/tests/SpaceSwitchCheck.swift -o /tmp/space-switch-check && /tmp/space-switch-check
//
// Real AppKit animations with deterministic gesture samples. This checks takeover,
// cancellation, and selection ordering; WebKit compositing still needs visual verification.

import AppKit
import SwiftUI

@main
struct SpaceSwitchCheck {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        var selection = 0
        let parent = PlatformPageView(
            selection: Binding(get: { selection }, set: { selection = $0 }),
            configuration: PlatformPageViewConfiguration(transition: .historyStack, orientation: .horizontal, spacing: 0),
            next: { $0 < 3 ? $0 + 1 : nil }, previous: { $0 > 0 ? $0 - 1 : nil },
            content: { Text("Space \($0)") })
        let coordinator = parent.makeCoordinator()
        let pager = PlatformPageView<Int, Text>.SwipePagerView(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        let window = NSWindow(contentRect: pager.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = pager
        window.setFrameOrigin(NSPoint(x: -2000, y: -2000))
        window.orderFront(nil)
        coordinator.pager = pager
        pager.coordinator = coordinator
        coordinator.show(0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))

        let outgoing = pager.subviews.first!
        var completed = false
        let started = CACurrentMediaTime()

        pager.animate(to: coordinator.view(for: 1), forward: true) {
            precondition(CACurrentMediaTime() - started >= 0.17, "Selection updates must not finish the 180 ms slide early")
            completed = true
            coordinator.show(coordinator.parent.selection)
        }
        coordinator.commit(1)
        precondition(selection == 1, "Selection must commit immediately")
        precondition(outgoing.superview === pager, "Commit must preserve the outgoing sidebar during motion")
        precondition(!completed, "Selection should precede animation completion")
        precondition(pager.isTracking)
        coordinator.refresh(to: 1, animated: false)
        RunLoop.current.run(until: Date().addingTimeInterval(0.08))
        precondition(!completed, "The sidebar must still be moving after a page switch")
        RunLoop.current.run(until: Date().addingTimeInterval(0.27))
        precondition(completed)
        precondition(selection == 1 && coordinator.current == 1)
        precondition(!pager.isTracking)
        precondition(pager.subviews.count == 1)
        precondition(pager.subviews[0].frame == pager.bounds)
        print("PASS: immediate commit, full slide duration, retained outgoing sidebar, settled geometry")

        func reset(_ value: Int = 0) {
            selection = value
            coordinator.show(value)
        }

        func move(_ amount: CGFloat, phase: NSEvent.Phase = .changed, time: TimeInterval = 1) {
            pager.updateGesture(amount: amount, phase: phase, time: time)
        }

        func swipe(_ amount: CGFloat) {
            precondition(pager.beginGesture(), "A new gesture must be accepted during settling")
            move(0, phase: .began, time: 0)
            move(amount, time: 1)
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            move(amount, phase: .ended, time: 1.1)
        }

        func finish(at value: Int) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            precondition(selection == value && coordinator.current == value)
            precondition(!pager.isTracking)
            precondition(pager.subviews.count == 1)
            precondition(pager.subviews[0].frame == pager.bounds)
        }

        func visibleFrames() -> [(NSView, NSRect)] {
            pager.subviews.map { ($0, $0.layer?.presentation()?.frame ?? $0.frame) }
        }

        func assertPositions(_ frames: [(NSView, NSRect)], shiftedBy delta: CGFloat = 0) {
            for (view, frame) in frames {
                precondition(view.superview === pager, "An interrupted swipe must retain the visible outgoing page")
                precondition(abs(view.frame.minX - frame.minX - delta) < 1,
                             "Takeover jumped from \(frame.minX) to \(view.frame.minX), expected delta \(delta)")
            }
        }

        // Begin the next swipe while the first slide still has visible distance left.
        // Keep fingers down beyond the old deadline to catch stale completion cleanup.
        reset()
        swipe(-0.45)
        precondition(selection == 1)
        RunLoop.current.run(until: Date().addingTimeInterval(0.04))

        let interruptedFrames = visibleFrames()

        precondition(interruptedFrames.contains { $0.1.minX > 0 && $0.1.minX < 300 })
        precondition(pager.beginGesture())
        assertPositions(interruptedFrames)
        precondition(!pager.beginGesture(), "An active finger gesture cannot be replaced by another begin")
        move(0, phase: .began)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        precondition(pager.isTracking && selection == 1)
        assertPositions(interruptedFrames)
        move(-0.35)
        assertPositions(interruptedFrames, shiftedBy: -105)
        move(-0.35, phase: .ended)
        precondition(selection == 2)
        finish(at: 2)
        print("PASS: consecutive swipe, no position jump, original completion cannot reset the new drag")

        // Reverse while settling. The previous space is already on screen; reuse it.
        reset()
        swipe(-0.45)
        RunLoop.current.run(until: Date().addingTimeInterval(0.04))

        let reversingFrames = visibleFrames()

        precondition(pager.beginGesture())
        assertPositions(reversingFrames)
        move(0.4)
        assertPositions(reversingFrames, shiftedBy: 120)
        precondition(pager.subviews.count == 2, "Reversal must reuse the outgoing page")
        move(0.4, phase: .ended)
        precondition(selection == 0)
        finish(at: 0)
        print("PASS: reverse takeover reuses visible pages and returns to the previous space")

        // Cancelling a takeover returns to the already selected space, not its predecessor.
        reset()
        swipe(-0.45)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        precondition(pager.beginGesture())
        move(-0.4)
        move(-0.4, phase: .cancelled)
        precondition(selection == 1)
        finish(at: 1)

        // A rollback is interruptible too.
        reset()
        swipe(-0.1)
        precondition(selection == 0)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        swipe(-0.4)
        finish(at: 1)
        print("PASS: cancelled takeover and interrupted rollback keep the correct selection")

        // Several quick commits may leave more than two pages visible or retained.
        reset()

        for target in 1...3 {
            swipe(-0.4)
            precondition(selection == target)
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }

        finish(at: 3)
        swipe(0.4)
        finish(at: 2)
        print("PASS: rapid forward chain, cleanup, and backward swipe at the final space")

        // Interrupt a programmatic slide: its completion must not run after takeover.
        reset()

        var obsoleteCompletion = false

        pager.animate(to: coordinator.view(for: 1), forward: true) { obsoleteCompletion = true }
        coordinator.commit(1)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        swipe(-0.4)
        finish(at: 2)
        precondition(!obsoleteCompletion)
        print("PASS: gesture supersedes programmatic animation without running its stale completion")


        // A keyboard/menu selection supersedes the old motion before the next swipe.
        reset()
        swipe(-0.45)
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        selection = 2
        coordinator.refresh(to: 2, animated: false)
        precondition(coordinator.current == 2 && !pager.isTracking)
        swipe(-0.4)
        precondition(selection == 3, "The new swipe must start from the keyboard-selected space")
        finish(at: 3)

        // Even an explicitly animated external selection must supersede an active drag.
        reset()
        precondition(pager.beginGesture())
        move(-0.4)
        selection = 2
        coordinator.refresh(to: 2, animated: true)
        move(-0.4, phase: .ended)
        precondition(selection == 2 && coordinator.current == 2 && !pager.isTracking)
        swipe(0.4)
        finish(at: 1)
        print("PASS: keyboard/menu selection supersedes motion and subsequent gestures use the latest space")
    }
}
