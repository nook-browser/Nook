// Licensed under GPL-3.0. See LICENSE.
//
//  LookupVerify.swift
//  NookWeb
//
//  What comes out of a written answer before anyone sees it. The model is not trusted with
//  figures: a number, time or date that no page Look It Up read contains takes its sentence
//  with it. Foundation only, so `Checks/LookupVerifyCheck.swift` can compile it.
//

import Foundation

public enum LookupVerify {
    /// `answer` without repeated sentences, without sources outside `1...sourceCount`, and
    /// without any sentence holding a figure that `corpus` (the notes and page texts) lacks.
    public static func cleaned(_ answer: LookupAnswer, sourceCount: Int, corpus: String) -> LookupAnswer {
        let known = Set(figures(in: corpus))
        var seen = Set<String>()
        func supported(_ text: String) -> Bool { figures(in: text).allSatisfy(known.contains) }
        func fresh(_ text: String) -> Bool { seen.insert(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted }
        func keep(_ point: LookupPoint) -> Bool {
            (1...max(sourceCount, 1)).contains(point.source) && sourceCount > 0
                && supported(point.label + " " + point.sentence) && fresh(point.sentence)
        }

        var out = answer
        out.points = answer.points.filter(keep)
        out.sections = answer.sections.compactMap { section in
            let points = section.points.filter(keep)
            return points.isEmpty ? nil : LookupSection(heading: section.heading, points: points)
        }
        out.intro = supported(answer.intro) ? answer.intro : ""
        var names = Set<String>()
        out.options = answer.options.filter { option in
            (1...max(sourceCount, 1)).contains(option.source) && sourceCount > 0
                && supported(option.name + " " + option.detail)
                && names.insert(option.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()).inserted
                && fresh(option.detail)
        }
        return out
    }

    private static let gapPhrases = [
        "not specified", "not provided", "not mentioned", "not given", "not stated", "not available", "not listed",
        "does not mention", "does not say", "does not give", "unspecified", "is unknown", "are unknown", "n/a",
    ]

    /// True for a line that reports what its page left out ("rating not specified"), which a
    /// small model writes where it should have written less. Whole words: not "Italian/American".
    public static func admitsGap(_ line: String) -> Bool {
        let spaced = " " + line.lowercased().map { $0.isLetter || $0.isNumber || $0 == "/" ? $0 : " " }.split(separator: " ").joined(separator: " ") + " "
        return gapPhrases.contains { spaced.contains(" " + $0 + " ") }
    }

    /// Every figure in `text`, commas removed: a run of digits with inner commas and an optional
    /// `.d` or `:mm` tail, holding at least two digits in all. Single digits are not checked.
    public static func figures(in text: String) -> [String] {
        guard let re = try? NSRegularExpression(pattern: #"\d[\d,]*(?:[.:]\d+)?"#) else { return [] }
        return re.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            let figure = text[range].filter { $0 != "," }
            return figure.filter(\.isNumber).count >= 2 ? String(figure) : nil
        }
    }
}
