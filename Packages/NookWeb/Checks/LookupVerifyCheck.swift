// Licensed under GPL-3.0. See LICENSE.
//
//  LookupVerifyCheck.swift
//  Nook
//
//  What Look It Up removes from a written answer before it is shown: repeats, source numbers
//  that point nowhere, and any sentence with a figure no page it read supports.
//
//    swiftc Packages/NookWeb/Sources/NookWeb/Lookup/LookupModels.swift \
//           Packages/NookWeb/Sources/NookWeb/Lookup/LookupVerify.swift \
//           Packages/NookWeb/Checks/LookupVerifyCheck.swift -o /tmp/lookup-verify && /tmp/lookup-verify
//

import Foundation

@main
struct LookupVerifyCheck {
    static func main() {
        let corpus = "Built in 1956. Closed in 2000. Rated 4.7 by 49,000 people. Dinner at 7:00 PM."
        func p(_ s: String, _ n: Int = 1) -> LookupPoint { LookupPoint(label: "L", sentence: s, source: n) }
        func answer(points: [LookupPoint] = [], sections: [LookupSection] = [], intro: String = "", options: [LookupOption] = []) -> LookupAnswer {
            LookupAnswer(title: "T", points: points, sections: sections, intro: intro, options: options)
        }

        var a = answer(
            points: [p("Built in 1956."), p("Built in 1956."), p("Opened in 1961."), p("No figures here."), p("Rated 4.7 by 49000 people."), p("Out of range.", 9), p("Source zero.", 0)],
            sections: [LookupSection(heading: "H", points: [p(" built in 1956. "), p("Dinner at 7:00 PM.")])])
        a = LookupVerify.cleaned(a, sourceCount: 2, corpus: corpus)
        precondition(a.points.map(\.sentence) == ["Built in 1956.", "No figures here.", "Rated 4.7 by 49000 people."])
        precondition(a.sections.count == 1 && a.sections[0].points.map(\.sentence) == ["Dinner at 7:00 PM."])
        precondition(a.title == "T")

        precondition(LookupVerify.figures(in: "In 1956, 2 of 49,000 at 7:00 PM") == ["1956", "49000", "7:00"])
        precondition(LookupVerify.figures(in: "4.7 stars, 25% off, on 2026-11-16.") == ["4.7", "25", "2026", "11", "16"])
        precondition(LookupVerify.figures(in: "No numbers, or just 1 and 2.").isEmpty)

        // a figure in the label counts too
        let labelled = LookupVerify.cleaned(answer(points: [LookupPoint(label: "Since 1999", sentence: "It is old.", source: 1)]), sourceCount: 1, corpus: corpus)
        precondition(labelled.points.isEmpty)

        // a section left with no points goes; an answer left with nothing is empty
        let gone = LookupVerify.cleaned(answer(points: [p("In 1999.")], sections: [LookupSection(heading: "H", points: [p("In 1998.")])]), sourceCount: 1, corpus: corpus)
        precondition(gone.isEmpty && gone.sections.isEmpty)
        precondition(!a.isEmpty)

        // options obey the same rules, and a name appears once
        let o = LookupVerify.cleaned(answer(intro: "There are 12 of them.", options: [
            LookupOption(name: "A", detail: "Costs $12.", source: 1), LookupOption(name: "B", detail: "Rated 4.7.", source: 1),
            LookupOption(name: "B", detail: "Rated 4.7.", source: 1), LookupOption(name: "b", detail: "Closed in 2000.", source: 1),
            LookupOption(name: "C", detail: "Closed in 2000.", source: 3),
        ]), sourceCount: 1, corpus: corpus)
        precondition(o.options.map(\.name) == ["B"])
        precondition(o.intro.isEmpty, "an intro with an unsupported figure is dropped")
        precondition(LookupVerify.cleaned(answer(intro: "Two places fit.", options: [LookupOption(name: "B", detail: "Fine.", source: 1)]), sourceCount: 1, corpus: corpus).intro == "Two places fit.")
    }
}
