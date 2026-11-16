// Licensed under GPL-3.0. See LICENSE.
//
//  LookupPipelineCheck.swift
//  Nook
//
//  Look It Up's pipeline against a stub model and a stub reader: what it writes and when, which
//  pages go to a reader page, and how it ends when the model fails, nothing is found or the
//  person stops it.
//
//    L=Packages/NookWeb/Sources/NookWeb/Lookup; M=Nook/Managers/LookupManager
//    swiftc $L/LookupModels.swift $L/LookupText.swift $L/LookupSearch.swift $L/LookupVerify.swift $L/LookupTimes.swift \
//           $L/BookingSites.swift $L/LookupPageRenderer.swift $L/LookupStore.swift $M/LookupModel.swift $M/LookupPipeline.swift \
//           scripts/tests/LookupPipelineCheck.swift -o /tmp/lookup-pipeline && /tmp/lookup-pipeline
//

import Foundation

struct Refused: Error {}

final class StubModel: LookupModel, @unchecked Sendable {
    var budget = LookupBudget(pageCharacters: 40, pages: 3)
    var plan: LookupPlan? = LookupPlan(searches: ["q"], kind: .explain)
    var answerFailures = 0
    var calls: [String] = []
    var noteTexts: [String] = []
    var noteTitles: [String] = []
    var notesFail = false
    var answerKinds: [LookupKind] = []

    func plan(for request: String) async throws -> LookupPlan {
        calls.append("plan")
        guard let plan else { throw Refused() }
        return plan
    }

    func notes(on text: String, title: String, request: String, search: String) async throws -> String {
        calls.append("notes")
        noteTexts.append(text)
        noteTitles.append(title)
        if notesFail { throw Refused() }
        return title == "Silent" ? "NONE" : "- Opened in 1956 says \(title)"
    }

    func answer(request: String, kind: LookupKind, notes: [String], smaller: Bool) async throws -> LookupAnswer {
        calls.append(smaller ? "answer-smaller" : "answer")
        answerKinds.append(kind)
        if answerFailures > 0 {
            answerFailures -= 1
            throw Refused()
        }
        let points = [LookupPoint(label: "When", sentence: "Opened in 1956.", source: 1), LookupPoint(label: "Made Up", sentence: "Closed in 1987.", source: 1)]
        return kind == .explain
            ? LookupAnswer(title: "The Answer", points: points)
            : LookupAnswer(title: "The Options", intro: "Two.", options: [LookupOption(name: "One", detail: "Opened in 1956.", source: 1)])
    }

    var bookingReply: BookingDetails?

    func booking(in request: String, today: Date) async throws -> BookingDetails {
        calls.append("booking")
        guard let bookingReply else { throw Refused() }
        return bookingReply
    }

    var aboutReply = "A fine place rated 4.7 by many."

    func about(_ text: String, title: String) async throws -> String {
        calls.append("about")
        return aboutReply
    }
}

@MainActor
final class StubReader: LookupReading {
    var hits: [String: [LookupHit]] = [:]
    var fetched: [URL: (title: String?, image: URL?, text: String)] = [:]
    var pages: [URL: LookupReadPage] = [:]
    var files: [URL: Data] = [:]
    var log: [String] = []
    var ended = 0
    var fetchDelay: Duration = .zero
    /// Addresses whose download never finishes on its own.
    var hanging: Set<URL> = []
    var onSearch: () -> Void = {}

    func search(_ query: String) async -> [LookupHit] {
        log.append("search \(query)")
        onSearch()
        return hits[query] ?? []
    }

    func fetch(_ url: URL) async -> (title: String?, image: URL?, text: String)? {
        log.append("fetch \(url.host ?? "")")
        try? await Task.sleep(for: fetchDelay)
        return fetched[url]
    }

    func readInPage(_ url: URL, booking: Bool) async -> LookupReadPage? {
        log.append("page \(url.host ?? "")\(booking ? " booking \(url.query ?? "")" : "")")
        return pages[url]
    }

    func data(_ url: URL, limit: Int) async -> Data? {
        log.append("data \(url.lastPathComponent)")
        if hanging.contains(url) { try? await Task.sleep(for: .seconds(60)) }
        guard let data = files[url], data.count <= limit else { return nil }
        return data
    }

    func icon(for url: URL) async -> Data? { nil }

    func endAll() { ended += 1 }
}

@main
struct LookupPipelineCheck {
    @MainActor
    static func main() async {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("lookup-pipeline-\(UUID().uuidString)").standardizedFileURL
        defer { try? FileManager.default.removeItem(at: support) }
        func hit(_ host: String, _ title: String) -> LookupHit { LookupHit(url: URL(string: "https://\(host)/p")!, title: title, snippet: "Snippet of \(title).") }
        let long = String(repeating: "Opened in 1956 and still going. ", count: 40)
        func url(_ host: String) -> URL { URL(string: "https://\(host)/p")! }

        func world() -> (StubModel, StubReader) {
            let reader = StubReader()
            // A short request is its own search, whatever the model planned.
            reader.hits["when did it open"] = [hit("a.com", "Alpha"), hit("b.com", "Beta"), hit("c.com", "Gamma"), hit("d.com", "Delta")]
            reader.fetched[url("a.com")] = ("Alpha Page", URL(string: "https://a.com/photo.jpg"), long)
            reader.fetched[url("b.com")] = ("Beta", URL(string: "https://b.com/huge.png"), "thin")
            reader.pages[url("b.com")] = LookupReadPage(title: "Beta Page", text: long)
            reader.files[URL(string: "https://a.com/photo.jpg")!] = Data(repeating: 1, count: 10)
            reader.files[URL(string: "https://b.com/huge.png")!] = Data(repeating: 1, count: 3_000_001)
            return (StubModel(), reader)
        }
        func run(_ model: StubModel, _ reader: StubReader, request: String = "when did it open", stages: inout [LookupStage]) async -> LookupRecord {
            var seen: [LookupStage] = []
            let record = await LookupPipeline(model: model, reader: reader, support: support, notesTogether: false)
                .run(LookupRecord(request: request)) { seen.append($0) }
            stages = seen
            return record
        }
        var stages: [LookupStage] = []

        // MARK: a normal run
        var (model, reader) = world()
        var placeholder: LookupOutcome?
        var started: LookupRecord?
        reader.onSearch = { placeholder = started.flatMap { LookupStore.record(for: $0.id, in: support)?.outcome } }
        var seen: [LookupStage] = []
        let first = LookupRecord(request: "when did it open")
        started = first
        var record = await LookupPipeline(model: model, reader: reader, support: support, notesTogether: false).run(first) { seen.append($0) }
        precondition(placeholder == .running, "the placeholder is on disk before the first search")
        precondition(record.id == first.id && record.outcome == .done && record.seconds >= 0)
        precondition(seen == [.searching, .reading(hosts: ["a.com", "b.com", "c.com"]), .writing])
        precondition(LookupStore.record(for: record.id, in: support) == record)
        precondition((try? String(contentsOf: LookupStore.pageURL(for: record.id, in: support), encoding: .utf8))?.contains("The Answer") == true)
        precondition(record.plan == LookupPlan(searches: ["when did it open"], kind: .explain))
        // budget: three pages, never the fourth; forty characters of each
        precondition(record.sources.count == 3 && !reader.log.contains("fetch d.com"))
        precondition(model.noteTexts.allSatisfy { $0.count <= 40 })
        // a.com read by fetch; b.com thin, read in a reader page; c.com unread, snippet kept
        precondition(record.sources[0].wasRead && !record.sources[0].usedReaderPage && record.sources[0].title == "Alpha Page")
        precondition(!reader.log.contains("page a.com") && reader.log.contains("page b.com") && reader.log.contains("page c.com"))
        precondition(record.sources[1].wasRead && record.sources[1].usedReaderPage && record.sources[1].title == "Beta Page")
        precondition(!record.sources[2].wasRead && record.sources[2].text.contains("Snippet of Gamma") && record.sources[2].title == "Gamma")
        // the unsupported figure went, the supported one stayed
        precondition(record.answer?.points.map(\.sentence) == ["Opened in 1956."])
        // one photo saved, the oversized one refused
        precondition(record.sources[0].imageFile == "photo1.jpg" && record.sources[1].imageFile == nil)
        precondition(FileManager.default.fileExists(atPath: LookupStore.folder(for: record.id, in: support).appendingPathComponent("photo1.jpg").path))
        precondition(reader.ended == 1)
        precondition(model.calls == ["plan", "notes", "notes", "answer"], "an unread page's snippet is its note: \(model.calls)")

        // MARK: the answer fails once, then twice
        (model, reader) = world()
        model.answerFailures = 1
        record = await run(model, reader, stages: &stages)
        precondition(record.outcome == .done && model.calls.suffix(2) == ["answer", "answer-smaller"])
        (model, reader) = world()
        model.answerFailures = 2
        record = await run(model, reader, stages: &stages)
        precondition(record.outcome == .failed && record.answer == nil && record.sources[0].notes.contains("1956"))
        precondition((try? String(contentsOf: LookupStore.pageURL(for: record.id, in: support), encoding: .utf8))?.contains("What Each Page Says") == true)

        // MARK: an answer left with nothing after verification
        (model, reader) = world()
        reader.fetched[url("a.com")] = ("Silent", nil, String(repeating: "Nothing with a year in it. ", count: 40))
        reader.pages[url("b.com")] = nil
        record = await run(model, reader, stages: &stages)
        precondition(record.outcome == .failed, "every point needed 1956 and no page had it")

        // MARK: nothing found
        (model, reader) = world()
        reader.hits = [:]
        record = await run(model, reader, stages: &stages)
        precondition(record.outcome == .nothingFound && model.calls == ["plan"] && reader.ended == 1 && stages == [.searching])
        precondition((try? String(contentsOf: LookupStore.pageURL(for: record.id, in: support), encoding: .utf8))?.contains("Nothing came back for this.") == true)

        // MARK: the plan is refused: the request itself is the search
        (model, reader) = world()
        model.plan = nil
        record = await run(model, reader, stages: &stages)
        precondition(record.outcome == .done && reader.log.first == "search when did it open" && record.plan?.kind == .explain)

        // MARK: an act request is written as choices
        (model, reader) = world()
        model.plan = LookupPlan(searches: ["q", "q", " "], kind: .act)
        reader.hits["q"] = reader.hits["when did it open"]
        record = await run(model, reader, stages: &stages)
        precondition(model.answerKinds == [.choose] && record.answer?.options.count == 1)
        precondition(record.plan?.searches == ["q"], "something to get done is searched in the model's words")

        // MARK: a listed request runs the model's searches, each once
        (model, reader) = world()
        model.plan = LookupPlan(searches: ["first", "second", "First"], kind: .choose)
        reader.hits["first"] = [hit("a.com", "Alpha")]
        reader.hits["second"] = [hit("b.com", "Beta"), hit("a.com", "Alpha")]
        record = await run(model, reader, request: "the first, or the second", stages: &stages)
        precondition(record.plan?.searches == ["first", "second"] && reader.log.filter { $0.hasPrefix("search") }.sorted() == ["search first", "search second"])
        precondition(record.sources.map(\.search) == [0, 1] && record.sources.map { $0.hit.url.host } == ["a.com", "b.com"])

        // MARK: a 50,000 character title, and a request as long
        (model, reader) = world()
        reader.fetched[url("a.com")] = (String(repeating: "T", count: 50_000), nil, long)
        record = await run(model, reader, stages: &stages)
        precondition(record.sources[0].title.count == 200 && model.noteTitles.allSatisfy { $0.count <= 200 })
        record = await run(model, reader, request: "  when did it open " + String(repeating: "x", count: 5_000), stages: &stages)
        precondition(record.request.count == 500 && record.request.hasPrefix("when"), "the request is cut once, where the lookup starts")
        (model, reader) = world()
        reader.fetched[url("a.com")] = (String(repeating: "T", count: 50_000), nil, long)
        record = await run(model, reader, stages: &stages)

        // MARK: what a record keeps of each page is what the model was given
        precondition(record.sources[0].text.count <= model.budget.pageCharacters)

        // MARK: every notes call fails: the pages found are still listed
        (model, reader) = world()
        model.notesFail = true
        reader.fetched[url("b.com")] = ("Beta Page", nil, long)
        reader.fetched[url("c.com")] = ("Gamma Page", nil, long)
        var logged: [String] = []
        record = await LookupPipeline(model: model, reader: reader, support: support, notesTogether: false, log: { logged.append($0) })
            .run(LookupRecord(request: "when did it open")) { _ in }
        precondition(record.outcome == .failed && !model.calls.contains("answer"))
        let failedPage = (try? String(contentsOf: LookupStore.pageURL(for: record.id, in: support), encoding: .utf8)) ?? ""
        precondition(failedPage.contains("Nothing came back for this.") && failedPage.contains("Pages Read") && failedPage.contains("Gamma Page"))
        precondition(logged.contains { $0.contains("notes") }, "a failed model call is logged: \(logged)")

        // MARK: a photo that never arrives does not hold the page
        (model, reader) = world()
        reader.fetched[url("b.com")] = ("Beta Page", URL(string: "https://b.com/slow.png"), long)
        reader.hanging = [URL(string: "https://b.com/slow.png")!]
        let waited = Date()
        record = await LookupPipeline(model: model, reader: reader, support: support, notesTogether: false, imageWait: .milliseconds(300))
            .run(LookupRecord(request: "when did it open")) { _ in }
        precondition(record.outcome == .done && Date().timeIntervalSince(waited) < 5)
        precondition(record.sources[0].imageFile == "photo1.jpg" && record.sources[1].imageFile == nil, "what arrived in time is kept")

        // MARK: a booking: each place's own page, opened on the party and the day
        (model, reader) = world()
        let sunday = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 15, hour: 12))!
        model.plan = LookupPlan(searches: ["lilia", "kings", "llama"], kind: .act)
        model.bookingReply = BookingDetails(people: 2, date: "2026-11-19", time: "19:00")
        func resy(_ slug: String) -> URL { URL(string: "https://resy.com/cities/new-york-ny/venues/\(slug)")! }
        func set(_ slug: String) -> URL { URL(string: resy(slug).absoluteString + "?seats=2&date=2026-11-16")! }
        reader.hits["lilia"] = [hit("blog.example", "How to Get In"), LookupHit(url: resy("lilia"), title: "Book Lilia", snippet: "")]
        reader.hits["kings"] = [LookupHit(url: resy("kings-co-imperial"), title: "Book Kings", snippet: ""), hit("other.example", "Other")]
        reader.hits["llama"] = [hit("llama.example", "Llama Inn"), hit("more.example", "More")]
        reader.hits["llama resy"] = [LookupHit(url: resy("lilia"), title: "Book Lilia", snippet: ""), hit("more.example", "More")]
        reader.pages[set("lilia")] = LookupReadPage(title: "Book Your Lilia Reservation", text: "Rated 4.7. " + long, labels: ["button 2 Guests", "button 5:00 PM Bar", "button 9:15 PM Bar"],
                                                    heading: "Lilia", shot: Data(repeating: 7, count: 20))
        reader.fetched[URL(string: "https://llama.example/p")!] = ("Llama Inn", nil, "Rated 4.7. " + long)
        record = await LookupPipeline(model: model, reader: reader, support: support, notesTogether: false, today: sunday)
            .run(LookupRecord(request: "table for 2 tomorrow at 7pm at lilia, kings co imperial or llama inn")) { _ in }
        precondition(record.outcome == .done && record.answer == nil)
        precondition(record.booking == BookingDetails(people: 2, date: "2026-11-16", time: "19:00"), "tomorrow is settled in code: \(String(describing: record.booking))")
        precondition(record.sources.map { $0.hit.url.host } == ["resy.com", "resy.com", "llama.example"], "one page a place, its booking page first")
        precondition(!reader.log.contains("fetch resy.com") && reader.log.contains("page resy.com booking seats=2&date=2026-11-16"))
        precondition(record.sources[0].prefilledURL == set("lilia") && record.sources[0].times == ["5:00 PM", "9:15 PM"] && record.sources[0].name == "Lilia")
        precondition(record.sources[0].shotFile == "shot1.jpg" && record.sources[0].about == "A fine place rated 4.7 by many.")
        precondition(FileManager.default.fileExists(atPath: LookupStore.folder(for: record.id, in: support).appendingPathComponent("shot1.jpg").path))
        // a venue page that would not load keeps its card and says nothing about times
        precondition(record.sources[1].prefilledURL == set("kings-co-imperial") && !record.sources[1].wasRead && record.sources[1].times.isEmpty && record.sources[1].name == "kings")
        // a place whose search held no booking page gets one more, aimed at the booking site;
        // a page it brings back for some other place is not taken
        precondition(reader.log.filter { $0.hasPrefix("search ") } == ["search lilia", "search kings", "search llama", "search llama resy"])
        // a place with no booking page is an ordinary card
        precondition(record.sources[2].prefilledURL == nil && record.sources[2].wasRead && record.sources[2].about.contains("4.7"))
        precondition(!model.calls.contains("notes") && !model.calls.contains("answer") && model.calls.filter { $0 == "about" }.count == 2)
        let booked = (try? String(contentsOf: LookupStore.pageURL(for: record.id, in: support), encoding: .utf8)) ?? ""
        precondition(booked.contains("Lilia has no 7:00 PM. Open times: 5:00 PM, 9:15 PM.") && booked.contains("Open on resy.com"))
        precondition(booked.contains("seats=2&amp;date=2026-11-16") && booked.contains("This site would not load in the background.") && booked.contains("shot1.jpg"))

        // a line about a place whose figure its page does not hold is dropped
        (model, reader) = world()
        model.plan = LookupPlan(searches: ["lilia"], kind: .act)
        model.bookingReply = BookingDetails(people: 2)
        reader.hits["lilia"] = [LookupHit(url: resy("lilia"), title: "Book Lilia", snippet: "")]
        reader.pages[URL(string: resy("lilia").absoluteString + "?seats=2")!] = LookupReadPage(title: "Lilia", text: long, labels: ["button 7:00 PM Bar"], heading: "Lilia")
        record = await LookupPipeline(model: model, reader: reader, support: support, notesTogether: false, today: sunday)
            .run(LookupRecord(request: "book a table for 2 at lilia some evening this month if they have room")) { _ in }
        precondition(record.sources.count == 1 && record.sources[0].about.isEmpty && record.sources[0].times == ["7:00 PM"])
        precondition(record.booking == BookingDetails(people: 2))

        // nor is a line that says what the page left out
        model.calls = []
        model.aboutReply = "Lilia is a restaurant with a rating not specified and price level not specified."
        record = await LookupPipeline(model: model, reader: reader, support: support, notesTogether: false, today: sunday)
            .run(LookupRecord(request: "book a table for 2 at lilia some evening this month if they have room")) { _ in }
        precondition(model.calls.contains("about") && record.sources[0].about.isEmpty && record.sources[0].times == ["7:00 PM"])

        // the place's own page, found by the second search, is its card
        (model, reader) = world()
        model.plan = LookupPlan(searches: ["momofuku noodle bar nyc"], kind: .act)
        model.bookingReply = BookingDetails(people: 2)
        reader.hits["momofuku noodle bar nyc"] = [hit("momofuku.example", "Momofuku")]
        reader.hits["momofuku noodle bar nyc resy"] = [
            LookupHit(url: resy("momofuku-ko"), title: "Book Ko", snippet: ""), hit("momofuku.example", "Momofuku"),
            LookupHit(url: resy("momofuku-noodle-bar"), title: "Book Noodle Bar", snippet: ""),
        ]
        record = await LookupPipeline(model: model, reader: reader, support: support, notesTogether: false, today: sunday)
            .run(LookupRecord(request: "book a table for 2 at momofuku noodle bar some evening this month if they have room")) { _ in }
        precondition(record.sources.count == 1 && record.sources[0].prefilledURL == URL(string: resy("momofuku-noodle-bar").absoluteString + "?seats=2"))

        // a venue page the search brought back for some other place is no card of this one
        (model, reader) = world()
        model.plan = LookupPlan(searches: ["lilia brooklyn"], kind: .act)
        model.bookingReply = BookingDetails(people: 2)
        reader.hits["lilia brooklyn"] = [hit("review.example", "Review"), LookupHit(url: resy("misi"), title: "Book Misi", snippet: ""),
                                         LookupHit(url: resy("lilia"), title: "Book Lilia", snippet: "")]
        reader.pages[URL(string: resy("lilia").absoluteString + "?seats=2")!] = LookupReadPage(title: "Lilia", text: long, labels: ["button 7:00 PM Bar"], heading: "Lilia")
        record = await LookupPipeline(model: model, reader: reader, support: support, notesTogether: false, today: sunday)
            .run(LookupRecord(request: "book a table for 2 at lilia some evening this month if they have room")) { _ in }
        precondition(record.sources.filter { $0.prefilledURL != nil }.map(\.hit.url) == [resy("lilia")], "\(record.sources.map(\.hit.url))")
        precondition(!reader.log.contains { $0.hasSuffix(" resy") }, "its page was in the first results")

        // four searches at most, the second kind included; and none of that kind for tickets
        (model, reader) = world()
        model.plan = LookupPlan(searches: ["aa", "bb", "cc"], kind: .act)
        model.bookingReply = BookingDetails(people: 2)
        for search in ["aa", "bb", "cc"] { reader.hits[search] = [hit("\(search).example", search)] }
        record = await LookupPipeline(model: model, reader: reader, support: support, notesTogether: false, today: sunday)
            .run(LookupRecord(request: "a table for 2 at aa, bb or cc")) { _ in }
        precondition(reader.log.filter { $0.hasPrefix("search ") } == ["search aa", "search bb", "search cc", "search aa resy"], "\(reader.log)")
        (model, reader) = world()
        model.plan = LookupPlan(searches: ["lion king tickets"], kind: .act)
        model.bookingReply = BookingDetails(people: 2, date: "2026-11-21")
        reader.hits["lion king tickets"] = reader.hits["when did it open"]
        record = await LookupPipeline(model: model, reader: reader, support: support, notesTogether: false, today: sunday)
            .run(LookupRecord(request: "buy 2 tickets for the lion king next saturday")) { _ in }
        precondition(reader.log.filter { $0.hasPrefix("search ") } == ["search lion king tickets"], "\(reader.log)")

        // details but no booking page in the results: laid out as choices, like any other act request
        (model, reader) = world()
        model.plan = LookupPlan(searches: ["x"], kind: .act)
        model.bookingReply = BookingDetails(people: 2, date: "2026-11-16")
        reader.hits["x"] = reader.hits["when did it open"]
        record = await run(model, reader, stages: &stages)
        precondition(record.outcome == .done && model.answerKinds == [.choose] && record.sources.allSatisfy { $0.prefilledURL == nil })

        // MARK: stopped mid-read
        (model, reader) = world()
        reader.fetchDelay = .milliseconds(400)
        let pipeline = LookupPipeline(model: model, reader: reader, support: support, notesTogether: true)
        let task = Task { @MainActor in await pipeline.run(LookupRecord(request: "when did it open")) { _ in } }
        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()
        record = await task.value
        precondition(record.outcome == .stopped && reader.ended == 1 && !model.calls.contains("answer"))
        precondition(LookupStore.record(for: record.id, in: support)?.outcome == .stopped)
        precondition((try? String(contentsOf: LookupStore.pageURL(for: record.id, in: support), encoding: .utf8))?.contains("Search the Web Instead") == false,
                     "no ordinary search was given, so none is offered")
    }
}
