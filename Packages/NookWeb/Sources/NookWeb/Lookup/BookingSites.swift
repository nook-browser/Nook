// Licensed under GPL-3.0. See LICENSE.
//
//  BookingSites.swift
//  NookWeb
//
//  The booking sites Look It Up can open on a person's party size and day, each by its own
//  address parameters. A site joins this table only after someone has checked its parameters
//  by hand in a visible tab. Foundation only, so `Checks/BookingSitesCheck.swift` can compile it.
//

import Foundation

public enum BookingSites {
    private struct Site {
        let hosts: [String]
        /// A venue page's path, one entry a component; "*" stands for any one component.
        let venuePath: [String]
        let seats: String?
        /// Takes `yyyy-MM-dd`.
        let date: String?
        /// Added to a place's search, it brings up the place's page on this site.
        let searchWord: String
        /// What a request for this site's kind of booking says.
        let requestWords: Set<String>
    }

    private static let sites = [
        // Checked 2026-11-15, signed out: the page opens on that party and day with its time slots.
        Site(hosts: ["resy.com", "www.resy.com"], venuePath: ["cities", "*", "venues", "*"], seats: "seats", date: "date", searchWord: "resy",
             requestWords: ["table", "dinner", "lunch", "brunch", "breakfast", "reservation", "reservations", "reserve", "restaurant"]),
    ]

    private static let maxParty = 20

    /// True for one venue's own page on a site in the table.
    public static func isVenuePage(_ url: URL) -> Bool {
        site(for: url) != nil
    }

    /// `url` with the party size and day in the site's own parameters, or nil when the page is
    /// not a venue's or there is nothing to fill in.
    public static func prefilled(_ url: URL, _ details: BookingDetails) -> URL? {
        guard let site = site(for: url), var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var added: [URLQueryItem] = []
        if let name = site.seats, let people = details.people, (1...maxParty).contains(people) {
            added.append(URLQueryItem(name: name, value: String(people)))
        }
        if let name = site.date, let date = details.date, isDay(date) {
            added.append(URLQueryItem(name: name, value: date))
        }
        guard !added.isEmpty else { return nil }
        let kept = (components.queryItems ?? []).filter { item in !added.contains { $0.name == item.name } }
        components.queryItems = kept + added
        return components.url
    }

    /// One word a site that books what `request` asks for, for a second search when a place's
    /// own search held no booking page.
    public static func searchWords(for request: String) -> [String] {
        let said = Set(words(request))
        return sites.filter { !$0.requestWords.isDisjoint(with: said) }.map(\.searchWord)
    }

    /// Words a venue's address can consist of without naming anything.
    private static let plainWords: Set<String> = ["table", "tables", "dinner", "lunch", "brunch", "bar", "restaurant", "reservation", "reservations"]

    /// Whether a venue page is a place the person named: the name in its address, up to three
    /// words of it, stands in `request` as written, and `search` was for that place.
    /// ponytail: word matching; a place the person called by another name gets an ordinary card.
    public static func isPlace(_ url: URL, request: String, search: String) -> Bool {
        guard site(for: url) != nil else { return false }
        let name = Array(words(url.lastPathComponent).prefix(3))
        guard let first = name.first, name.count > 1 || !plainWords.contains(first), words(search).contains(first) else { return false }
        let said = words(request)
        return said.indices.contains { said[$0...].starts(with: name) }
    }

    /// Lowercased words, with "joe's" as "joes", the way an address writes it.
    private static func words(_ text: String) -> [String] {
        text.lowercased().replacingOccurrences(of: "'", with: "").replacingOccurrences(of: "\u{2019}", with: "")
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
    }

    private static func site(for url: URL) -> Site? {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return nil }
        let path = url.pathComponents.filter { $0 != "/" }
        return sites.first { site in
            site.hosts.contains(host) && path.count == site.venuePath.count
                && zip(path, site.venuePath).allSatisfy { $1 == "*" ? !$0.isEmpty : $0 == $1 }
        }
    }

    /// A real calendar day written `yyyy-MM-dd`.
    static func isDay(_ text: String) -> Bool {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyy-MM-dd"
        format.isLenient = false
        return text.count == 10 && format.date(from: text) != nil
    }
}

// MARK: - Reading a Request

/// The days a booking request can mean, written out so a model looks a date up instead of
/// working one out: it gets "tomorrow" right from a list and wrong by arithmetic.
public enum BookingCalendar {
    private static let days = 14

    public static func text(from today: Date, calendar: Calendar = .current) -> String {
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "EEEE yyyy-MM-dd"
        let listed = (0..<days).compactMap { calendar.date(byAdding: .day, value: $0, to: today).map(format.string) }
        guard listed.count == days else { return "" }
        return "Today is \(listed[0]). Tomorrow is \(listed[1]). The days after: \(listed.dropFirst(2).joined(separator: ", "))."
    }

    private static let weekdays = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
    private static let months: Set<String> = [
        "january", "february", "march", "april", "may", "june", "july", "august", "september", "october", "november", "december",
        "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "sept", "oct", "nov", "dec",
    ]
    /// Words that count a day from another ("the day after tomorrow", "friday in two weeks").
    private static let counting: Set<String> = ["after", "from", "following", "week", "weeks", "days", "fortnight", "month", "months"]

    /// `details` with its day settled by the request's words where they leave no doubt: today,
    /// tonight, tomorrow, or a weekday the model misplaced. Any other date stays as the model read it.
    public static func corrected(_ details: BookingDetails, request: String, today: Date, calendar: Calendar = .current) -> BookingDetails {
        let lowered = request.lowercased()
        let said = lowered.split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let words = Set(said)
        let figures = lowered.range(of: #"\b\d{1,2}(st|nd|rd|th)\b|\b\d{1,2}[/.-]\d{1,2}\b"#, options: .regularExpression) != nil
        guard !figures, words.isDisjoint(with: months), words.isDisjoint(with: counting) else { return details }
        let format = DateFormatter()
        format.calendar = calendar
        format.timeZone = calendar.timeZone
        format.locale = Locale(identifier: "en_US_POSIX")
        format.dateFormat = "yyyy-MM-dd"
        var ahead: Int?
        if words.contains("today") || words.contains("tonight") {
            ahead = 0
        } else if words.contains("tomorrow") {
            ahead = 1
        } else if let named = weekdays.firstIndex(where: words.contains), let given = details.date, let read = format.date(from: given) {
            // With no date from the model the word may be part of a name ("Sunday in Brooklyn").
            // Calendar weekdays run 1 (Sunday) to 7; a named day is never today.
            if calendar.component(.weekday, from: read) - 1 == named, given > format.string(from: today) { return details }
            let current = calendar.component(.weekday, from: today) - 1
            ahead = (named - current + 6) % 7 + 1
        }
        guard let ahead, let day = calendar.date(byAdding: .day, value: ahead, to: today) else { return details }
        var settled = details
        settled.date = format.string(from: day)
        return settled
    }
}

extension BookingDetails {
    /// A model's answer made safe to use: a party a table seats, a real day as `yyyy-MM-dd`, a
    /// real time as `HH:mm`. Anything else is left out.
    public static func cleaned(people: Int, date: String, time: String) -> BookingDetails {
        let day = date.trimmingCharacters(in: .whitespaces)
        let parts = time.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Int($0) }
        let clock = parts.count == 2 && (0...23).contains(parts[0]) && (0...59).contains(parts[1])
            ? String(format: "%02d:%02d", parts[0], parts[1]) : nil
        return BookingDetails(people: (1...20).contains(people) ? people : nil, date: BookingSites.isDay(day) ? day : nil, time: clock)
    }

    /// Whether there is anything a booking page can be opened on.
    public var hasDetails: Bool { people != nil || date != nil }
}
