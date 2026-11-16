// Licensed under GPL-3.0. See LICENSE.
//
//  LookupJSONCheck.swift
//  Nook
//
//  A connected model answers Look It Up in JSON, with whatever it wraps around it. This reads
//  the object out of the reply and forgives what a model gets wrong: missing lists, extra
//  keys, a number sent as text.
//
//    L=Packages/NookWeb/Sources/NookWeb/Lookup
//    swiftc $L/LookupModels.swift $L/LookupJSON.swift Packages/NookWeb/Checks/LookupJSONCheck.swift \
//           -o /tmp/lookup-json && /tmp/lookup-json
//

import Foundation

@main
struct LookupJSONCheck {
    static func main() {
        let bare = #"{"title":"T","points":[{"label":"L","sentence":"<script>alert(1)</script>","source":1}]}"#
        let expected = LookupAnswer(title: "T", points: [LookupPoint(label: "L", sentence: "<script>alert(1)</script>", source: 1)])
        precondition(try! LookupJSON.decoded(LookupAnswer.self, from: bare) == expected)
        precondition(try! LookupJSON.decoded(LookupAnswer.self, from: "Here you go:\n```json\n\(bare)\n```\nHope that helps {not json}") == expected)
        precondition(try! LookupJSON.decoded(LookupAnswer.self, from: "  \n\(bare) trailing words") == expected)

        // braces and quotes inside strings do not end the object
        let tricky = #"{"title":"a } b { \" c","points":[]}"#
        precondition(try! LookupJSON.decoded(LookupAnswer.self, from: "x " + tricky + " y").title == "a } b { \" c")

        // no object, or a broken one, is an error and never a crash
        for reply in ["I cannot help with that.", "", "{ \"title\": ", "[1, 2, 3]", "}{"] {
            precondition((try? LookupJSON.decoded(LookupAnswer.self, from: reply)) == nil, reply)
        }

        // unknown keys are ignored, missing lists are empty, a number may arrive as text
        let loose = try! LookupJSON.decoded(LookupAnswer.self, from: #"{"title":"T","extra":{"a":1},"options":[{"name":"N","detail":"D","source":"2","why":"x"}]}"#)
        precondition(loose.points.isEmpty && loose.sections.isEmpty && loose.intro.isEmpty)
        precondition(loose.options == [LookupOption(name: "N", detail: "D", source: 2)])
        let sectioned = try! LookupJSON.decoded(LookupAnswer.self, from: #"{"sections":[{"heading":"H"},{"heading":"I","points":[{"sentence":"S"}]}]}"#)
        precondition(sectioned.title.isEmpty && sectioned.sections.count == 2 && sectioned.sections[0].points.isEmpty)
        precondition(sectioned.sections[1].points == [LookupPoint(label: "", sentence: "S", source: 0)])

        // the plan
        precondition(try! LookupJSON.decoded(LookupPlan.self, from: #"{"searches":["a","b"],"kind":" Choose "}"#) == LookupPlan(searches: ["a", "b"], kind: .choose))
        precondition(try! LookupJSON.decoded(LookupPlan.self, from: #"{"kind":"something else"}"#) == LookupPlan(searches: [], kind: .explain))

        // booking details
        precondition(try! LookupJSON.decoded(BookingDetails.self, from: #"{"people":2,"date":"2026-11-16","time":"19:00"}"#) == BookingDetails(people: 2, date: "2026-11-16", time: "19:00"))
        precondition(try! LookupJSON.decoded(BookingDetails.self, from: #"{"people":null}"#) == BookingDetails())

        // a saved record still round-trips through the forgiving decoders
        var record = LookupRecord(request: "r")
        record.answer = expected
        record.plan = LookupPlan(searches: ["s"], kind: .act)
        precondition(try! JSONDecoder().decode(LookupRecord.self, from: JSONEncoder().encode(record)) == record)
    }
}
