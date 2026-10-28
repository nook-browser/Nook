// Licensed under GPL-3.0. See LICENSE.
// swiftc Packages/NookWeb/Sources/NookWeb/TabSwitcherState.swift Packages/NookWeb/Checks/TabSwitcherStateCheck.swift -o /tmp/ts && /tmp/ts

import Foundation

@main
struct TabSwitcherStateCheck {
    static func main() {
        let a = UUID(), b = UUID(), c = UUID()
        precondition(TabSwitcherState.start(items: [a], step: 1) == nil, "nothing to switch to")

        // Control-Tab once: the previous tab. Again: the one before. Then round to the current.
        var s = TabSwitcherState.start(items: [a, b, c], step: 1)!
        precondition(s.highlighted == b)
        s.advance(by: 1); precondition(s.highlighted == c)
        s.advance(by: 1); precondition(s.highlighted == a)
        // Shift-Control-Tab goes back, and wraps the other way.
        s.advance(by: -1); precondition(s.highlighted == c)

        // Opened backwards: the oldest.
        precondition(TabSwitcherState.start(items: [a, b, c], step: -1)!.highlighted == c)
        // The card waits 0.1 s; a quicker release switches with no card.
        precondition(!TabSwitcherState.shouldPresent(elapsed: 0.05))
        precondition(TabSwitcherState.shouldPresent(elapsed: 0.1))
        precondition(!TabSwitcherState.start(items: [a, b], step: 1)!.isPresented)
        print("TabSwitcherStateCheck passed")
    }
}
