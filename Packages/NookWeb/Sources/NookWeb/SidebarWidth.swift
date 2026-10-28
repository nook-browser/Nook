// Licensed under GPL-3.0. See LICENSE.
//
//  SidebarWidth.swift
//  NookWeb
//
//  Sidebar drag rules and the space switcher's item size. Foundation only, checked by
//  `Checks/SidebarWidthCheck.swift`.
//

import Foundation

public enum SidebarWidth {
    public static let hide: CGFloat = 82
    public static let min: CGFloat = 164
    public static let max: CGFloat = 500
    public static let standard: CGFloat = 252   // four square favorite tiles: 8 + 8 + 4 * 53 + 3 * 8
    public static let snap: CGFloat = 14

    /// The width a drag to `proposed` ends up at: 0 (hidden) below `hide`, clamped to `min...max`,
    /// and `standard` when within `snap` of it.
    public static func resolve(proposed: CGFloat) -> CGFloat {
        if proposed < hide { return 0 }
        let clamped = Swift.min(Swift.max(proposed, min), max)
        return abs(clamped - standard) <= snap ? standard : clamped
    }

    public static func snapped(proposed: CGFloat) -> Bool {
        proposed >= hide && abs(proposed - standard) <= snap
    }
}

/// One resize drag: sticks at `standard` until the pointer leaves it fast enough, and rate-limits
/// the snap haptic.
public struct SidebarDrag {
    public static let leaveSpeed: CGFloat = 50      // pt/s needed to pull free of the snap
    public static let hapticInterval: TimeInterval = 0.5

    public struct Step: Equatable {
        public let width: CGFloat
        public let haptic: Bool
    }

    private var snapped: Bool
    private var released = false
    private var lastHaptic: TimeInterval = -.infinity

    public init(startingWidth: CGFloat) { snapped = startingWidth == SidebarWidth.standard }

    /// `raw` is the unclamped width under the pointer; `velocity` is in width points per second.
    public mutating func update(raw: CGFloat, velocity: CGFloat, now: TimeInterval) -> Step {
        if raw < SidebarWidth.hide { snapped = false; return Step(width: 0, haptic: false) }
        let free = Swift.min(Swift.max(raw, SidebarWidth.min), SidebarWidth.max)
        guard abs(raw - SidebarWidth.standard) <= SidebarWidth.snap else {
            snapped = false
            released = false
            return Step(width: free, haptic: false)
        }
        if snapped {
            let leaving = raw != SidebarWidth.standard && abs(velocity) >= Self.leaveSpeed
                && (raw > SidebarWidth.standard) == (velocity > 0)
            guard leaving else { return Step(width: SidebarWidth.standard, haptic: false) }
            snapped = false
            released = true
            return Step(width: free, haptic: buzz(now))
        }
        if released { return Step(width: free, haptic: false) }
        snapped = true
        return Step(width: SidebarWidth.standard, haptic: buzz(now))
    }

    private mutating func buzz(_ now: TimeInterval) -> Bool {
        guard now - lastHaptic > Self.hapticInterval else { return false }
        lastHaptic = now
        return true
    }
}

/// Pointer speed from the last few drag events' own deltas and timestamps (about 50 ms).
public struct DragVelocity {
    private var samples: [(dx: CGFloat, dt: TimeInterval)] = []
    private var lastTime: TimeInterval

    public init(startTime: TimeInterval) { lastTime = startTime }

    public mutating func add(dx: CGFloat, time: TimeInterval) -> CGFloat {
        samples.append((dx, max(time - lastTime, 0)))
        lastTime = time
        if samples.count > 4 { samples.removeFirst() }
        let total = samples.reduce(0) { $0 + $1.dt }
        return samples.reduce(0) { $0 + $1.dx } / CGFloat(Swift.max(total, 1.0 / 240))
    }
}

public enum SpaceSwitcher {
    public static let minItem: CGFloat = 8    // Arc's dock floor; past it the row scrolls
    public static let maxItem: CGFloat = 34
    public static let compactBelow: CGFloat = 22

    /// Space between items before the row has to squeeze them.
    public static let gap: CGFloat = 8

    /// Arc's dock: `(available - spacing) / count` clamped to 8...34, spacing being the gaps.
    public static func itemSize(available: CGFloat, count: Int) -> CGFloat {
        guard count > 0 else { return maxItem }
        let spacing = gap * CGFloat(count - 1)
        return Swift.min(Swift.max((available - spacing) / CGFloat(count), minItem), maxItem)
    }

    /// The gap that lets `count` items of `size` fit in `available`, at most `gap`, never negative.
    public static func gap(available: CGFloat, count: Int, size: CGFloat) -> CGFloat {
        guard count > 1 else { return 0 }
        return Swift.min(gap, Swift.max(0, (available - size * CGFloat(count)) / CGFloat(count - 1)))
    }

    /// Below this the switcher draws plain dots.
    public static func isCompact(itemSize: CGFloat) -> Bool { itemSize < compactBelow }
}
