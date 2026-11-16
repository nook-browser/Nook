// Licensed under GPL-3.0. See LICENSE.
//
//  LookupTimesCheck.swift
//  Nook
//
//  What Look It Up says about the times a booking page offers. It reads them off the page's
//  own controls in code, and says nothing when the page shows none.
//
//    swiftc Packages/NookWeb/Sources/NookWeb/Lookup/LookupTimes.swift \
//           Packages/NookWeb/Checks/LookupTimesCheck.swift -o /tmp/lookup-times && /tmp/lookup-times
//

import Foundation

@main
struct LookupTimesCheck {
    static func main() {
        let labels = ["button 2 Guests", "button Date Picker", "button 5:00 PM Bar", "button 9:15 PM Bar", "button 9:30 PM Bar",
                      "button 9:30 PM Indoor", "link Get Directions", "button Notify"]
        precondition(LookupTimes.times(inLabels: labels) == ["5:00 PM", "9:15 PM", "9:30 PM"])
        // written other ways
        precondition(LookupTimes.times(inLabels: ["button 7:00pm", "button 07:30 p.m. Patio", "button 11:45 AM"]) == ["7:00 PM", "7:30 PM", "11:45 AM"])
        // only a button that starts with a clock time counts
        precondition(LookupTimes.times(inLabels: ["button Open 24 hours", "button 1:1 chat", "link 10:30 PM", "button 10:30", "button Notify me at 5:00 PM",
                                                  "field 7:00 PM", "button 13:00 PM", "button 7:75 PM"]).isEmpty)

        precondition(LookupTimes.display("19:00") == "7:00 PM" && LookupTimes.display("00:05") == "12:05 AM")
        precondition(LookupTimes.display("12:30") == "12:30 PM" && LookupTimes.display("09:15") == "9:15 AM")
        for bad in ["7pm", "24:00", "7:60", "", "19:00:00", "ab:cd"] { precondition(LookupTimes.display(bad) == nil, bad) }

        precondition(LookupTimes.line(place: "Lilia", asked: "19:00", times: ["5:00 PM", "9:15 PM", "9:30 PM"]) == "Lilia has no 7:00 PM. Open times: 5:00 PM, 9:15 PM, 9:30 PM.")
        precondition(LookupTimes.line(place: "Kings Co Imperial", asked: "19:00", times: ["6:30 PM", "7:00 PM"]) == "Kings Co Imperial has 7:00 PM.")
        // no time controls at all: no statement, whatever was asked
        precondition(LookupTimes.line(place: "Lilia", asked: "19:00", times: []) == nil)
        // no time asked, or one that is not a time: no statement
        precondition(LookupTimes.line(place: "Lilia", asked: nil, times: ["5:00 PM"]) == nil)
        precondition(LookupTimes.line(place: "Lilia", asked: "evening", times: ["5:00 PM"]) == nil)
        // a long list is cut to the six times nearest the one asked for, in clock order
        let many = ["5:30 PM", "5:45 PM", "6:00 PM", "6:15 PM", "6:30 PM", "7:15 PM", "7:30 PM", "7:45 PM", "8:00 PM", "9:00 PM"]
        precondition(LookupTimes.line(place: "A", asked: "19:00", times: many) == "A has no 7:00 PM. Open times: 6:00 PM, 6:15 PM, 6:30 PM, 7:15 PM, 7:30 PM, 7:45 PM.")
        precondition(LookupTimes.offers("19:00", in: many) == false && LookupTimes.offers("19:15", in: many) == true)
        precondition(LookupTimes.offers("19:15", in: []) == false && LookupTimes.offers("soon", in: many) == false)

        // the task handed to the chat when the page no longer shows that time: the person's own terms
        let stop = " Stop before signing in, paying or confirming."
        precondition(LookupTimes.chatDraft(people: 2, date: "2026-11-16", time: "19:00") == "On this page, set up a table for 2 on Monday, November 16 at 7:00 PM." + stop)
        precondition(LookupTimes.chatDraft(people: nil, date: "2026-12-03", time: "12:30") == "On this page, set up a table on Thursday, December 3 at 12:30 PM." + stop)
        precondition(LookupTimes.chatDraft(people: 6, date: nil, time: "19:00") == "On this page, set up a table for 6 at 7:00 PM." + stop)
        precondition(LookupTimes.chatDraft(people: 6, date: "next week", time: "19:00") == "On this page, set up a table for 6 at 7:00 PM." + stop)
        precondition(LookupTimes.chatDraft(people: 2, date: "2026-11-16", time: "7pm") == nil, "no time, no task")
    }
}
