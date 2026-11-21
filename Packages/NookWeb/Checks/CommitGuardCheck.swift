// Licensed under GPL-3.0. See LICENSE.
//
//  CommitGuardCheck.swift
//  Nook
//
//  The line Look It Up does not cross: it may pick the time a person asked for, and it never
//  presses a control that reserves, pays, confirms or signs in.
//
//    L=Packages/NookWeb/Sources/NookWeb/Lookup
//    swiftc $L/LookupTimes.swift $L/CommitGuard.swift Packages/NookWeb/Checks/CommitGuardCheck.swift \
//           -o /tmp/commit-guard && /tmp/commit-guard
//

import Foundation

@main
struct CommitGuardCheck {
    static func main() {
        for label in ["Reserve Now", "Book now", "Pay $40", "Buy tickets", "Confirm", "Complete reservation", "Submit", "Place Order", "Checkout",
                      "Check out", "Sign in", "Log In", "Sign up", "Continue with Google", "RESERVE", "button Reserve Now", "Purchase", "  confirm booking  ", "Login", "Log-in"] {
            precondition(CommitGuard.commits(label), label)
        }
        for label in ["7:00 PM Dining Room", "2 Guests", "Date Picker", "Notify", "Get Directions", "Share", "Read more", "Reservations policy",
                      "Booking details", "Buyer's guide", "PayPal info", "Autocomplete", "", "Signature dishes", "Logins and security help"] {
            precondition(!CommitGuard.commits(label), label)
        }

        let labels = ["button 2 Guests", "button 6:30 PM Dining Room", "button 7:00 PM Dining Room", "button 7:00 PM Bar", "button Reserve Now 7:00 PM"]
        precondition(CommitGuard.timeControl(in: labels, for: "7:00 PM") == 2, "the first match")
        precondition(CommitGuard.timeControl(in: labels, for: "8:00 PM") == nil)
        precondition(CommitGuard.timeControl(in: ["button 17:00 PM x", "link 7:00 PM", "button Book 7:00 PM"], for: "7:00 PM") == nil)
        precondition(CommitGuard.timeControl(in: ["button 7:00 PM Reserve Now", "button 7:00pm Patio"], for: "7:00 PM") == 1, "never a control that commits")
        precondition(CommitGuard.timeControl(in: [], for: "7:00 PM") == nil)

        // the same line in the other words sites use for it
        for label in ["Make a Reservation", "Request Reservation", "Proceed to Payment", "Payment", "Register", "Create Account", "Join Waitlist",
                      "Add to Cart", "Get Tickets", "Finish", "Subscribe", "Donate", "Signin", "Log on"] {
            precondition(CommitGuard.commits(label), label)
        }
        precondition(CommitGuard.timeControl(in: ["button 7:00 PM · Make a Reservation", "button 7:00 PM Patio"], for: "7:00 PM") == 1)

        // the steps between a time and the charge: a go-ahead that names no action commits
        for label in ["Continue", "Next", "Proceed", "Agree and continue", "Accept", "Send", "Apply", "Authorize", "Authorise", "Place hold", "Hold table",
                      "Add card", "Credit card", "Join", "Save", "Next step", "Done", "OK", "Okay", "Yes", "I agree", "  next  step ", "Save!"] {
            precondition(CommitGuard.commits(label), label)
        }
        // a button's label reaches the guard once for each attribute that holds it
        for label in ["Continue Continue", "Next step Next step", "Save Save Save Save", "Next Next step"] {
            precondition(CommitGuard.commits(label), label)
        }
        for label in ["Next month", "Next available", "Continue reading", "Save for later", "Done reading", "Yesterday", "Okay then", "Cardinal rules",
                      "Holdings", "Application notes", "Joint venture info", "7:00 PM", "button 7:00 PM Bar"] {
            precondition(!CommitGuard.commits(label), label)
        }
        precondition(CommitGuard.timeControl(in: ["button 7:00 PM", "button 7:00 PM Dining Room"], for: "7:00 PM") == 0)
        precondition(CommitGuard.timeControl(in: ["button 7:00 PM Hold table", "button 7:00 PM Dining Room"], for: "7:00 PM") == 1)

        // what the chat's tools may do on a tab opened from an answer page
        let refused = "Left for the person: this control signs in, pays or confirms."
        precondition(GuardedTools.refusal(tool: "clickElement", label: "Reserve Now", guarded: true) == refused)
        precondition(GuardedTools.refusal(tool: "fillField", label: "Confirm email", guarded: true) == refused)
        precondition(GuardedTools.refusal(tool: "executeJavaScript", label: nil, guarded: true) == refused)
        precondition(GuardedTools.refusal(tool: "clickElement", label: nil, guarded: true) == refused, "a control it cannot name is not pressed")
        precondition(GuardedTools.refusal(tool: "clickElement", label: "", guarded: true) == refused && GuardedTools.refusal(tool: "fillField", label: " \n", guarded: true) == refused,
                     "nor is one with no name at all: an icon alone says nothing about what it does")
        precondition(GuardedTools.refusal(tool: "clickElement", label: "7:00 PM Dining Room", guarded: true) == nil)
        precondition(GuardedTools.refusal(tool: "clickElement", label: "Continue Continue", guarded: true) == refused)
        precondition(GuardedTools.refusal(tool: "clickElement", label: "Next month", guarded: true) == nil)
        precondition(GuardedTools.refusal(tool: "fillField", label: "Special requests", guarded: true) == nil)
        precondition(GuardedTools.refusal(tool: "readPageContent", label: nil, guarded: true) == nil)
        for tool in ["clickElement", "fillField", "executeJavaScript", "navigateToURL"] {
            precondition(GuardedTools.refusal(tool: tool, label: "Reserve Now", guarded: false) == nil, tool)
        }
    }
}
