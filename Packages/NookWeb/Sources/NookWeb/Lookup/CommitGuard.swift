// Licensed under GPL-3.0. See LICENSE.
//
//  CommitGuard.swift
//  NookWeb
//
//  The line Look It Up does not cross. It may press the time a person asked for; a control
//  that reserves, books, pays, buys, confirms, submits or signs in is left for the person,
//  whoever asks. Foundation only, so `Checks/CommitGuardCheck.swift` can compile it.
//

import Foundation

public enum CommitGuard {
    // Whole words, so "Reservations policy" and "Booking details" stay pressable.
    // ponytail: English only; a site in another language needs its own words before it joins.
    private static let words = [
        "reserve", "book", "pay", "buy", "purchase", "confirm", "complete", "submit", "order", "checkout",
        "check out", "sign in", "log in", "login", "sign up", "continue with",
        "make a reservation", "request reservation", "request a reservation", "payment", "register", "account", "waitlist",
        "cart", "tickets", "finish", "subscribe", "donate", "signin", "sign on", "log on", "logon",
        "agree", "accept", "authorize", "authorise", "hold", "card", "send", "apply", "join",
    ]
    /// A label made of these alone names no action, so it counts as committing, like a control with no name.
    private static let goAhead: Set<String> = ["continue", "next", "proceed", "next step", "save", "done", "ok", "okay", "yes"]

    /// True for a control whose label commits the person to something.
    public static func commits(_ label: String) -> Bool {
        let parts = label.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
        let text = " " + parts.joined(separator: " ") + " "
        return words.contains { text.contains(" " + $0 + " ") } || isGoAhead(parts)
    }

    /// True when every word is part of a go-ahead phrase. A control's label reaches the guard once
    /// for each attribute that holds it ("Continue Continue"), so a repeat counts.
    private static func isGoAhead(_ parts: [String]) -> Bool {
        var i = 0
        while i < parts.count {
            if i + 1 < parts.count, goAhead.contains(parts[i] + " " + parts[i + 1]) { i += 2 }
            else if goAhead.contains(parts[i]) { i += 1 }
            else { return false }
        }
        return !parts.isEmpty
    }

    /// The first button whose label starts with `display` ("7:00 PM") and does not commit.
    /// `labels` are a page's control labels, and the result indexes them.
    public static func timeControl(in labels: [String], for display: String) -> Int? {
        labels.firstIndex { LookupTimes.time(startingButton: $0) == display && !commits($0) }
    }
}

/// What the chat's tools may do on a tab that was opened from one of Look It Up's pages.
public enum GuardedTools {
    private static let refused = "Left for the person: this control signs in, pays or confirms."

    /// The reason a tool call is refused, nil when it may run. On a guarded tab a click or a fill
    /// needs a control with a name, one that does not commit, and no script runs at all.
    public static func refusal(tool: String, label: String?, guarded: Bool) -> String? {
        guard guarded else { return nil }
        switch tool {
        case "executeJavaScript": return refused
        case "clickElement", "fillField":
            guard let label, !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return refused }
            return CommitGuard.commits(label) ? refused : nil
        default: return nil
        }
    }
}
