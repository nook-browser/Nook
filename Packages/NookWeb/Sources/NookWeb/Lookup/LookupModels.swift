// Licensed under GPL-3.0. See LICENSE.
//
//  LookupModels.swift
//  NookWeb
//
//  The values Look It Up passes between its stages and saves beside the page it writes.
//  Foundation only, so the checks can compile it.
//

import Foundation

// MARK: - Plan and Search

public enum LookupKind: String, Codable, Equatable, Sendable {
    /// Wants to understand something.
    case explain
    /// Wants things to pick from.
    case choose
    /// Wants something done on a site.
    case act
}

public struct LookupPlan: Codable, Equatable, Sendable {
    public var searches: [String]
    public var kind: LookupKind

    public init(searches: [String], kind: LookupKind) {
        self.searches = searches
        self.kind = kind
    }
}

/// One row of a results page.
public struct LookupHit: Codable, Equatable, Sendable {
    public let url: URL
    public let title: String
    public let snippet: String

    public init(url: URL, title: String, snippet: String) {
        self.url = url
        self.title = title
        self.snippet = snippet
    }
}

/// What a booking request asked for. `date` is `yyyy-MM-dd`, `time` is `HH:mm`.
public struct BookingDetails: Codable, Equatable, Sendable {
    public var people: Int?
    public var date: String?
    public var time: String?

    public init(people: Int? = nil, date: String? = nil, time: String? = nil) {
        self.people = people
        self.date = date
        self.time = time
    }
}

// MARK: - Pages Read

/// One page Look It Up found, and what it got from it. File names are relative to the lookup's folder.
public struct LookupSource: Codable, Equatable, Sendable {
    public var hit: LookupHit
    /// Index of the search that found it.
    public var search: Int
    public var title: String
    public var text: String
    /// False when neither the fetch nor a reader page gave any text; `text` is then the snippet.
    public var wasRead: Bool
    public var usedReaderPage: Bool
    public var imageFile: String?
    public var iconFile: String?
    public var notes: String
    // Booking pages only.
    public var name: String
    public var about: String
    public var prefilledURL: URL?
    public var times: [String]
    public var shotFile: String?

    public init(hit: LookupHit, search: Int, title: String = "", text: String = "", wasRead: Bool = false, usedReaderPage: Bool = false,
                imageFile: String? = nil, iconFile: String? = nil, notes: String = "", name: String = "", about: String = "",
                prefilledURL: URL? = nil, times: [String] = [], shotFile: String? = nil) {
        self.hit = hit
        self.search = search
        self.title = title
        self.text = text
        self.wasRead = wasRead
        self.usedReaderPage = usedReaderPage
        self.imageFile = imageFile
        self.iconFile = iconFile
        self.notes = notes
        self.name = name
        self.about = about
        self.prefilledURL = prefilledURL
        self.times = times
        self.shotFile = shotFile
    }
}

// MARK: - The Answer

/// One labelled fact. `source` is the 1-based number of the page it came from.
public struct LookupPoint: Codable, Equatable, Sendable {
    public var label: String
    public var sentence: String
    public var source: Int

    public init(label: String, sentence: String, source: Int) {
        self.label = label
        self.sentence = sentence
        self.source = source
    }
}

public struct LookupSection: Codable, Equatable, Sendable {
    public var heading: String
    public var points: [LookupPoint]

    public init(heading: String, points: [LookupPoint]) {
        self.heading = heading
        self.points = points
    }
}

/// One thing the person could pick.
public struct LookupOption: Codable, Equatable, Sendable {
    public var name: String
    public var detail: String
    public var source: Int

    public init(name: String, detail: String, source: Int) {
        self.name = name
        self.detail = detail
        self.source = source
    }
}

/// What the model wrote. An explain answer fills `points` and `sections`; a choose answer fills
/// `intro` and `options`.
public struct LookupAnswer: Codable, Equatable, Sendable {
    public var title: String
    public var points: [LookupPoint]
    public var sections: [LookupSection]
    public var intro: String
    public var options: [LookupOption]

    public init(title: String, points: [LookupPoint] = [], sections: [LookupSection] = [], intro: String = "", options: [LookupOption] = []) {
        self.title = title
        self.points = points
        self.sections = sections
        self.intro = intro
        self.options = options
    }

    public var isEmpty: Bool { points.isEmpty && sections.isEmpty && options.isEmpty }
}

// MARK: - The Record

public enum LookupOutcome: String, Codable, Equatable, Sendable {
    case running, done, stopped, nothingFound, failed
}

/// Everything about one lookup, saved as `record.json` beside its `page.html`.
public struct LookupRecord: Codable, Equatable, Sendable {
    public var id: UUID
    public var request: String
    /// The same text as an ordinary search in the person's search engine.
    public var searchURL: URL?
    public var startedAt: Date
    public var plan: LookupPlan?
    public var booking: BookingDetails?
    public var sources: [LookupSource]
    public var answer: LookupAnswer?
    public var outcome: LookupOutcome
    public var seconds: Double
    /// The space's accent as `#rrggbb`.
    public var accentHex: String

    public static let defaultAccent = "#3a6df0"

    public init(id: UUID = UUID(), request: String, searchURL: URL? = nil, startedAt: Date = Date(), plan: LookupPlan? = nil,
                booking: BookingDetails? = nil, sources: [LookupSource] = [], answer: LookupAnswer? = nil,
                outcome: LookupOutcome = .running, seconds: Double = 0, accentHex: String = LookupRecord.defaultAccent) {
        self.id = id
        self.request = request
        self.searchURL = searchURL
        self.startedAt = startedAt
        self.plan = plan
        self.booking = booking
        self.sources = sources
        self.answer = answer
        self.outcome = outcome
        self.seconds = seconds
        self.accentHex = accentHex
    }
}

// MARK: - Forgiving Decoders

// A connected model writes these as JSON and gets details wrong: a list left out, a number sent
// as text, a kind in capitals. Decoding takes what is there.

private extension KeyedDecodingContainer {
    func text(_ key: Key) -> String { (try? decodeIfPresent(String.self, forKey: key)) ?? "" }

    func number(_ key: Key) -> Int {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        return (try? decodeIfPresent(String.self, forKey: key)).flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0
    }

    func list<T: Decodable>(_ key: Key) -> [T] { (try? decodeIfPresent([T].self, forKey: key)) ?? [] }
}

extension LookupPlan {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        searches = values.list(.searches)
        kind = LookupKind(rawValue: values.text(.kind).trimmingCharacters(in: .whitespaces).lowercased()) ?? .explain
    }
}

extension LookupPoint {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        label = values.text(.label)
        sentence = values.text(.sentence)
        source = values.number(.source)
    }
}

extension LookupSection {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        heading = values.text(.heading)
        points = values.list(.points)
    }
}

extension LookupOption {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = values.text(.name)
        detail = values.text(.detail)
        source = values.number(.source)
    }
}

extension LookupAnswer {
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        title = values.text(.title)
        points = values.list(.points)
        sections = values.list(.sections)
        intro = values.text(.intro)
        options = values.list(.options)
    }
}
