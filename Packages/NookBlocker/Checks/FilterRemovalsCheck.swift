// Licensed under GPL-3.0. See LICENSE.
//
//  FilterRemovalsCheck.swift
//  Nook
//
//  A line in the removals list leaves every filter list, whole lines only, and nothing else does.
//
//    swiftc Packages/NookBlocker/Sources/NookBlocker/FilterLineSearch.swift \
//           Packages/NookBlocker/Sources/NookBlocker/FilterRemovals.swift \
//           Packages/NookBlocker/Checks/FilterRemovalsCheck.swift -o /tmp/filter-removals && /tmp/filter-removals
//

import Foundation

@main
struct FilterRemovalsCheck {
    static func main() {
        let file = """
        ! Title: Nook filter removals
        ! Expires: 6 hours

        ~vipbox.pl,vipbox.*,vipboxtv.*##.position-absolute
          ||t.co^
        """
        let removed = FilterRemovals.lines(in: file)
        precondition(removed == ["~vipbox.pl,vipbox.*,vipboxtv.*##.position-absolute", "||t.co^"], "\(removed)")

        let list = """
        ! a list
        ||ads.example^
        ~vipbox.pl,vipbox.*,vipboxtv.*##.position-absolute
        ||t.co^$third-party
          ||t.co^
        example.com##.ad
        """
        let kept = FilterRemovals.apply(list, removing: removed).split(separator: "\n").map(String.init)
        // A longer line that starts with a removed one stays.
        precondition(kept == ["! a list", "||ads.example^", "||t.co^$third-party", "example.com##.ad"], "\(kept)")

        // The usual case costs nothing: no removal present, the same text back.
        let untouched = "||ads.example^\n||t.co^$third-party\n"
        precondition(FilterRemovals.apply(untouched, removing: removed) == untouched)
        precondition(FilterRemovals.apply(list, removing: []) == list)

        // The file itself may arrive with CRLF line endings.
        precondition(FilterRemovals.lines(in: "! x\r\n||t.co^\r\n") == ["||t.co^"])

        // A comment or a blank line removes nothing.
        precondition(FilterRemovals.lines(in: "! ||ads.example^\n\n").isEmpty)
        print("ok")
    }
}
