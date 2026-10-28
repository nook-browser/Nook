// Licensed under GPL-3.0. See LICENSE.
// swiftc Packages/NookWeb/Sources/NookWeb/SidebarWidth.swift Packages/NookWeb/Checks/SidebarWidthCheck.swift -o /tmp/sw && /tmp/sw

import Foundation

@main
struct SidebarWidthCheck {
    static func main() {
        precondition(SidebarWidth.resolve(proposed: 80) == 0, "below 82 hides")
        precondition(SidebarWidth.resolve(proposed: 82) == 164)
        precondition(SidebarWidth.resolve(proposed: 100) == 164)
        precondition(SidebarWidth.resolve(proposed: 600) == 500)
        precondition(SidebarWidth.resolve(proposed: 240) == 228, "snaps within 14 of the default")
        precondition(SidebarWidth.resolve(proposed: 242) == 228)
        precondition(SidebarWidth.resolve(proposed: 214) == 228)
        precondition(SidebarWidth.resolve(proposed: 243) == 243)
        precondition(SidebarWidth.resolve(proposed: 200) == 200)
        precondition(SidebarWidth.snapped(proposed: 240) && !SidebarWidth.snapped(proposed: 243))

        precondition(SpaceSwitcher.itemSize(available: 160, count: 20) == 8, "floor")
        precondition(SpaceSwitcher.itemSize(available: 160, count: 3) == 34, "ceiling")
        precondition(SpaceSwitcher.itemSize(available: 160, count: 5) == 25.6)
        precondition(SpaceSwitcher.itemSize(available: 160, count: 0) == 34, "no spaces")
        precondition(SpaceSwitcher.isCompact(itemSize: 21))
        precondition(!SpaceSwitcher.isCompact(itemSize: 22))

        // Dragging in from the left: snaps at 228 with a haptic, holds, frees at speed.
        var d = SidebarDrag(startingWidth: 300)
        precondition(d.update(raw: 250, velocity: -100, now: 0) == .init(width: 250, haptic: false))
        precondition(d.update(raw: 235, velocity: -100, now: 0.1) == .init(width: 228, haptic: true))
        precondition(d.update(raw: 225, velocity: -20, now: 0.2) == .init(width: 228, haptic: false), "slow stays")
        precondition(d.update(raw: 220, velocity: -60, now: 0.3) == .init(width: 220, haptic: false), "fast frees, inside the debounce")
        precondition(d.update(raw: 226, velocity: 10, now: 0.4).width == 226, "no re-snap until out of the zone")
        precondition(d.update(raw: 190, velocity: -10, now: 0.5).width == 190)
        precondition(d.update(raw: 80, velocity: -10, now: 0.6).width == 0, "hides")
        var e = SidebarDrag(startingWidth: 228)
        precondition(e.update(raw: 232, velocity: 5, now: 0).width == 228, "starts snapped")
        precondition(e.update(raw: 233, velocity: 80, now: 1).width == 233)

        // Eight spaces in the default sidebar's switcher row (about 148 pt) fit without scrolling.
        let size = SpaceSwitcher.itemSize(available: 148, count: 8)
        let gap = SpaceSwitcher.gap(available: 148, count: 8, size: size)
        precondition(size * 8 + gap * 7 <= 148 && gap >= 0)
        precondition(SpaceSwitcher.gap(available: 400, count: 3, size: 34) == SpaceSwitcher.gap, "roomy rows keep the full gap")

        var v = DragVelocity(startTime: 0)
        _ = v.add(dx: 1, time: 0.01)
        _ = v.add(dx: 1, time: 0.02)
        _ = v.add(dx: 1, time: 0.03)
        precondition(abs(v.add(dx: 1, time: 0.04) - 100) < 0.001, "4 dx of 1 over 40 ms")
        precondition(abs(v.add(dx: 3, time: 0.05) - 150) < 0.001, "window drops the oldest sample")
        var w = DragVelocity(startTime: 0); precondition(w.add(dx: 1, time: 0) == 240, "dt floor")
        print("SidebarWidthCheck passed")
    }
}
