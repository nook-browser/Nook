// Licensed under GPL-3.0. See LICENSE.
//
//  LibrarySwipeDecision.swift
//  Nook
//
//  Where a released library swipe settles. Foundation only, so
//  `scripts/tests/LibrarySwipeDecisionCheck.swift` can compile and check it.
//

import Foundation

enum LibrarySwipeDecision {
    /// Faster than this (points a second) at lift, the direction alone decides, as in Arc.
    static let flick: Double = 150
    /// A slow drag commits this far past where it started.
    static let commit: Double = 40

    /// Whether the library ends open. `distance` is how far out it is (0 shut, `width` open);
    /// `velocity` is positive toward open; `wasOpen` is where the swipe started.
    static func opens(distance: Double, velocity: Double, width: Double, wasOpen: Bool) -> Bool {
        if abs(velocity) > flick { return velocity > 0 }
        return wasOpen ? distance > width - commit : distance > commit
    }
}
