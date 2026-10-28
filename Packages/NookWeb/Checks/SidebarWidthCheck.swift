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
        precondition(SidebarWidth.resolve(proposed: 264) == 252, "snaps within 14 of the default")
        precondition(SidebarWidth.resolve(proposed: 266) == 252)
        precondition(SidebarWidth.resolve(proposed: 238) == 252)
        precondition(SidebarWidth.resolve(proposed: 267) == 267)
        precondition(SidebarWidth.resolve(proposed: 200) == 200)
        precondition(SidebarWidth.snapped(proposed: 264) && !SidebarWidth.snapped(proposed: 267))

        precondition(SpaceSwitcher.itemSize(available: 160, count: 20) == 8, "floor")
        precondition(SpaceSwitcher.itemSize(available: 160, count: 3) == 34, "ceiling")
        precondition(SpaceSwitcher.itemSize(available: 160, count: 5) == 25.6)
        precondition(SpaceSwitcher.itemSize(available: 160, count: 0) == 34, "no spaces")
        precondition(SpaceSwitcher.isCompact(itemSize: 21))
        precondition(!SpaceSwitcher.isCompact(itemSize: 22))

        // Dragging in from the left: snaps at 252 with a haptic, holds, frees at speed.
        var d = SidebarDrag(startingWidth: 300)
        precondition(d.update(raw: 274, velocity: -100, now: 0) == .init(width: 274, haptic: false))
        precondition(d.update(raw: 259, velocity: -100, now: 0.1) == .init(width: 252, haptic: true))
        precondition(d.update(raw: 249, velocity: -20, now: 0.2) == .init(width: 252, haptic: false), "slow stays")
        precondition(d.update(raw: 244, velocity: -60, now: 0.3) == .init(width: 244, haptic: false), "fast frees, inside the debounce")
        precondition(d.update(raw: 250, velocity: 10, now: 0.4).width == 250, "no re-snap until out of the zone")
        precondition(d.update(raw: 190, velocity: -10, now: 0.5).width == 190)
        precondition(d.update(raw: 80, velocity: -10, now: 0.6).width == 0, "hides")
        var e = SidebarDrag(startingWidth: 252)
        precondition(e.update(raw: 256, velocity: 5, now: 0).width == 252, "starts snapped")
        precondition(e.update(raw: 257, velocity: 80, now: 1).width == 257)

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
