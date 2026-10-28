// Licensed under GPL-3.0. See LICENSE.
// swiftc Nook/Components/Sidebar/Menu/LibrarySwipeDecision.swift scripts/tests/LibrarySwipeDecisionCheck.swift -o /tmp/ls && /tmp/ls

@main
struct LibrarySwipeDecisionCheck {
    static func main() {
        let w = 840.0
        // Opening: a little flick opens; a slow short pull opens past 40 pt; a nudge does not.
        precondition(LibrarySwipeDecision.opens(distance: 25, velocity: 600, width: w, wasOpen: false))
        precondition(LibrarySwipeDecision.opens(distance: 60, velocity: 0, width: w, wasOpen: false))
        precondition(!LibrarySwipeDecision.opens(distance: 20, velocity: 0, width: w, wasOpen: false))
        // Pulled out, then thrown back: shut, whatever the distance.
        precondition(!LibrarySwipeDecision.opens(distance: 500, velocity: -400, width: w, wasOpen: false))
        // Closing: a little flick shuts; a slow 60 pt drag shuts; a nudge stays open.
        precondition(!LibrarySwipeDecision.opens(distance: w - 20, velocity: -600, width: w, wasOpen: true))
        precondition(!LibrarySwipeDecision.opens(distance: w - 60, velocity: 0, width: w, wasOpen: true))
        precondition(LibrarySwipeDecision.opens(distance: w - 20, velocity: 0, width: w, wasOpen: true))
        // Width: the preferred width, held back 56 pt from the window's far edge, never under 417.
        precondition(LibrarySwipeDecision.width(preferred: 840, windowWidth: 1600) == 840)
        precondition(LibrarySwipeDecision.width(preferred: 840, windowWidth: 800) == 744)
        precondition(LibrarySwipeDecision.width(preferred: 420, windowWidth: 800) == 420)
        precondition(LibrarySwipeDecision.width(preferred: 420, windowWidth: 440) == 417, "floor")
        precondition(LibrarySwipeDecision.width(preferred: 840, windowWidth: 300) == 417, "floor in a tiny window")
        print("LibrarySwipeDecisionCheck passed")
    }
}
