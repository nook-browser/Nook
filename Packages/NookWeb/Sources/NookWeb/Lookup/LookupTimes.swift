// Licensed under GPL-3.0. See LICENSE.
//
//  LookupTimes.swift
//  NookWeb
//
//  The times a booking page offers, read off its own controls, and the one line Look It Up
//  says about them. Code decides this, never a model, and a page that shows no time says
//  nothing: sold out and refused look the same from here. Foundation only, so
//  `Checks/LookupTimesCheck.swift` can compile it.
//

import Foundation

public enum LookupTimes {
    private static let maxListed = 6

    /// The clock times a page's buttons start with, in page order, each once, as "7:00 PM".
    /// `labels` are a reader page's control labels: the kind, a space, then the visible text.
    public static func times(inLabels labels: [String]) -> [String] {
        var seen = Set<String>()
        return labels.compactMap(time(startingButton:)).filter { seen.insert($0).inserted }
    }

    /// The time a button's label starts with, nil for any other control.
    public static func time(startingButton label: String) -> String? {
        guard label.hasPrefix("button "),
              let re = try? NSRegularExpression(pattern: #"^button (1[0-2]|0?[1-9]):([0-5]\d)\s?([AaPp])\.?[Mm]\.?(?![A-Za-z])"#),
              let match = re.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)) else { return nil }
        func group(_ index: Int) -> String { Range(match.range(at: index), in: label).map { String(label[$0]) } ?? "" }
        return "\(Int(group(1)) ?? 0):\(group(2)) \(group(3).uppercased())M"
    }

    /// "19:00" as "7:00 PM"; nil for anything that is not `HH:mm`.
    public static func display(_ time24: String) -> String? {
        guard let minutes = minutes(of24: time24) else { return nil }
        let hour = minutes / 60
        return "\(hour % 12 == 0 ? 12 : hour % 12):" + String(format: "%02d", minutes % 60) + (hour < 12 ? " AM" : " PM")
    }

    /// Whether `asked` (`HH:mm`) is among the times a page offers.
    public static func offers(_ asked: String, in times: [String]) -> Bool {
        guard let shown = display(asked) else { return false }
        return times.contains(shown)
    }

    /// What a booking card says about times: that the place has the one asked for, or that it
    /// has not and which it has. Nil with no time asked, or no time on the page.
    public static func line(place: String, asked: String?, times: [String]) -> String? {
        guard let asked, let shown = display(asked), let wanted = minutes(of24: asked), !times.isEmpty else { return nil }
        if times.contains(shown) { return "\(place) has \(shown)." }
        let nearest = times.compactMap { time in minutes(ofShown: time).map { (time, $0) } }
            .sorted { abs($0.1 - wanted) < abs($1.1 - wanted) }.prefix(maxListed)
            .sorted { $0.1 < $1.1 }.map(\.0)
        return "\(place) has no \(shown). Open times: \(nearest.joined(separator: ", "))."
    }

    /// The booking as a task for the chat, said the way the person asked it. What they did not
    /// say is left out; with no time there is no task.
    public static func chatDraft(people: Int?, date: String?, time: String) -> String? {
        guard let shown = display(time) else { return nil }
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyy-MM-dd"
        let day = date.flatMap(format.date(from:))
        format.dateFormat = "EEEE, MMMM d"
        let party = people.map { " for \($0)" } ?? ""
        let on = day.map { " on " + format.string(from: $0) } ?? ""
        return "On this page, set up a table\(party)\(on) at \(shown). Stop before signing in, paying or confirming."
    }

    private static func minutes(of24 text: String) -> Int? {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, parts[0].count <= 2, parts[1].count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        return hour * 60 + minute
    }

    /// Minutes past midnight of a time written "7:00 PM".
    private static func minutes(ofShown text: String) -> Int? {
        let parts = text.split(whereSeparator: { $0 == ":" || $0 == " " })
        guard parts.count == 3, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return (hour % 12 + (parts[2] == "PM" ? 12 : 0)) * 60 + minute
    }
}
