// Licensed under GPL-3.0. See LICENSE.
//
// swiftc $(rg --files Nook/ThirdParty/BigUIPaging -g '*.swift') scripts/tests/SpaceSwitchCheck.swift -o /tmp/space-switch-check && /tmp/space-switch-check
//
// The space pager against the Arc behavior in docs/research/arc-teardown/10-sidebar-spaces-paging.md:
// the pure math, then real AppKit motion with deterministic gesture input. Feel still needs a trackpad.

import AppKit
import SwiftUI

typealias Pager = PlatformPageView<Int, Text>.SwipePagerView

@main
struct SpaceSwitchCheck {
    @MainActor
    static func main() {
        checkMath()
        checkView()
    }

    @MainActor
    static func checkMath() {
        func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.01) -> Bool { abs(a - b) <= tolerance }

        // Rubber band: identity inside, 255 * (1 - 1/(x * 0.15/255 + 1)) past an end, invertible.
        precondition(Pager.rubberBand(120, max: 600) == 120)
        precondition(near(Pager.rubberBand(-100, max: 600), -255 * (1 - 1 / (100 * 0.15 / 255 + 1))))
        precondition(near(Pager.rubberBand(700, max: 600), 600 + 255 * (1 - 1 / (100 * 0.15 / 255 + 1))))
        precondition(Pager.rubberBand(-1_000_000, max: 600) > -255)
        precondition(near(Pager.inverseRubberBand(Pager.rubberBand(-140, max: 600), max: 600), -140))

        // Page choice at lift. Width 300, four pages.
        func target(_ position: CGFloat, _ velocity: CGFloat, adopted: Bool = false) -> Int {
            Pager.target(position: position, velocity: velocity, width: 300, count: 4, adopted: adopted)
        }
        precondition(target(140, 0) == 0 && target(160, 0) == 1, "Slow release goes to the nearest page")
        precondition(target(30, 5) == 1, "Any flick of 5 pt/s moves one page its way")
        precondition(target(270, -5) == 0, "A backward flick returns to the floor page")
        precondition(target(30, 4.9) == 0)
        precondition(target(420, -50, adopted: true) == 0, "A flick during a settle moves on past the page in flight")
        precondition(target(-80, -50) == 0 && target(980, 50) == 3, "Never past either end")

        // Velocity only from the last 100 ms.
        precondition(near(Pager.velocity([(1.00, 0), (1.05, 50)]), 1000, 0.5))
        precondition(Pager.velocity([(1.00, 0), (1.20, 50)]) == 0)

        // Critically damped spring: starts at the offset, never overshoots from rest, ends at 0.
        let offsets = Pager.springOffsets(from: -300, velocity: 0)
        precondition(offsets.first == -300 && offsets.last == 0)
        precondition(zip(offsets, offsets.dropFirst()).allSatisfy { $0 <= $1 }, "No overshoot from rest")
        let duration = Double(offsets.count - 1) * Pager.sampleStep
        precondition(duration > 0.2 && duration < 0.6, "Response 0.25 s settles in roughly 0.3 to 0.5 s, got \(duration)")
        print("PASS: rubber band, page choice, velocity window, spring")
    }

    @MainActor
    static func checkView() {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)

        var selection = 0
        let parent = PlatformPageView(
            selection: Binding(get: { selection }, set: { selection = $0 }),
            configuration: PlatformPageViewConfiguration(transition: .historyStack, orientation: .horizontal, spacing: 0),
            next: { $0 < 3 ? $0 + 1 : nil }, previous: { $0 > 0 ? $0 - 1 : nil },
            content: { Text("Space \($0)") })
        let coordinator = parent.makeCoordinator()
        let pager = Pager(frame: NSRect(x: 0, y: 0, width: 300, height: 400))
        let window = NSWindow(contentRect: pager.bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = pager
        window.setFrameOrigin(NSPoint(x: -2000, y: -2000))
        window.orderFront(nil)
        coordinator.pager = pager
        pager.coordinator = coordinator
        var swipes: [PageSwipePosition?] = []
        coordinator.onSwipe = { swipes.append($0) }

        let strip = pager.subviews[0]
        func shown() -> CGFloat {
            guard let layer = strip.layer else { return -strip.frame.minX }
            return -((layer.presentation() ?? layer).position.x - layer.anchorPoint.x * layer.bounds.width)
        }
        func wait(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }

        coordinator.show(0)
        pager.layout()
        wait(0.05)
        precondition(strip.subviews.count == 1 && strip.frame.minX == 0)

        // Swipe left: fingers move the strip at half speed.
        precondition(pager.beginDrag())
        for step in 1...6 { pager.drag(.changed, delta: -40, time: 1 + Double(step) * 0.01) }
        precondition(strip.frame.minX == -120, "Six -40 pt deltas move the strip 120 pt")
        precondition(swipes.last??.to == AnyHashable(1) && abs((swipes.last??.progress ?? 0) - 0.4) < 0.001)
        pager.drag(.ended, delta: 0, time: 1.07)
        precondition(selection == 1, "The selection commits at lift, before the slide")
        precondition(pager.isTracking)
        precondition(swipes.last! == nil)
        wait(0.08)
        let midway = shown()
        precondition(midway > 120 && midway < 300, "Still sliding toward page 1, at \(midway)")
        wait(0.6)
        precondition(!pager.isTracking && strip.frame.minX == -300)
        precondition(strip.subviews.count == 1, "Only the selected page stays attached at rest")
        print("PASS: half-speed drag, commit at lift, spring settle, detached pages")

        // A far programmatic jump slides right through the pages between.
        selection = 3
        coordinator.parent = parent
        coordinator.refresh(to: 3, animated: true)
        precondition(strip.subviews.count == 3, "Pages 1 to 3 are on the strip during the jump")
        wait(0.06)
        let early = shown()
        precondition(early > 300 && early < 900, "Moves forward from page 1 toward page 3, at \(early)")
        wait(0.7)
        precondition(strip.frame.minX == -900 && !pager.isTracking)
        print("PASS: far jump moves by position, forward, through every page")

        // A swipe grabs the strip in flight at its on-screen position.
        coordinator.refresh(to: 0, animated: true)
        selection = 0
        wait(0.08)
        let inFlight = shown()
        precondition(pager.beginDrag())
        precondition(abs(-strip.frame.minX - inFlight) < 30, "Adopted near \(inFlight), got \(-strip.frame.minX)")
        pager.drag(.cancelled, delta: 0, time: 3)
        wait(0.7)
        precondition(strip.frame.minX == 0 && selection == 0, "A cancelled swipe returns to the selected page")
        print("PASS: interruption adopts the moving strip, cancel returns")

        // A resize mid-settle lands on the selected page at the new width.
        coordinator.refresh(to: 2, animated: true)
        selection = 2
        wait(0.05)
        pager.setFrameSize(NSSize(width: 250, height: 400))
        pager.layout()
        precondition(strip.frame.minX == -500 && !pager.isTracking)
        precondition(strip.subviews.allSatisfy { $0.frame.width == 250 })
        print("PASS: resize mid-settle")
    }
}
