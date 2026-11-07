// Licensed under GPL-3.0. See LICENSE.
//
//  TabSelectionCheck.swift
//
//    swiftc Packages/NookWeb/Sources/NookWeb/TabSelection.swift \
//           Packages/NookWeb/Checks/TabSelectionCheck.swift -o /tmp/tabselection-check && /tmp/tabselection-check
//

import Foundation

@main
struct TabSelectionCheck {
    static func main() {
        let r = (0..<6).map { _ in UUID() }

        // The first Cmd-click adds the shown tab; the next one toggles.
        var s = TabSelection()
        s.toggle(r[3], current: r[1])
        precondition(s.ids == [r[1], r[3]])
        s.toggle(r[4], current: r[1])
        precondition(s.ids == [r[1], r[3], r[4]])
        s.toggle(r[3], current: r[1])
        precondition(s.ids == [r[1], r[4]] && s.anchor == r[3])

        // Shift-click ranges from the anchor in either direction and replaces the set.
        s.toggle(r[2], current: r[1])
        s.extend(to: r[0], rows: r, current: r[1])
        precondition(s.ids == [r[0], r[1], r[2]] && s.anchor == r[2])
        s.extend(to: r[5], rows: r, current: r[1])
        precondition(s.ids == [r[2], r[3], r[4], r[5]])

        // With no anchor the shown tab starts the range.
        var t = TabSelection()
        t.extend(to: r[3], rows: r, current: r[1])
        precondition(t.ids == [r[1], r[2], r[3]])

        // A base outside the section's rows leaves just the clicked row.
        var u = TabSelection()
        u.extend(to: r[2], rows: Array(r[2...]), current: r[0])
        precondition(u.ids == [r[2]] && u.anchor == r[2])

        t.clear()
        precondition(t.isEmpty && t.anchor == nil)
        print("TabSelectionCheck passed")
    }
}
