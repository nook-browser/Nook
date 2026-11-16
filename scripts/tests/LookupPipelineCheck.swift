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

/// Shaped like the system model's errors: the case name is all the pipeline reads.
enum ModelSaid: Error {
    case refusal(String)
    case guardrailViolation(String)
}

/// What happened in what order, across the model and the reader.
final class Timeline: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []
    func add(_ event: String) { lock.withLock { events.append(event) } }
    var all: [String] { lock.withLock { events } }
    func index(_ event: String) -> Int { all.firstIndex(of: event) ?? .max }
}

final class StubModel: LookupModel, @unchecked Sendable {
    var budget = LookupBudget(pageCharacters: 40, pages: 3)
    var plan: LookupPlan? = LookupPlan(searches: ["q"], kind: .explain)
    var planDelay: Duration = .zero
    var answerFailures = 0
    var answerError: Error = Refused()
    var calls: [String] = []
    var noteTexts: [String] = []
    var noteTitles: [String] = []
    var notesFail = false
    var answerKinds: [LookupKind] = []
    var answerInputs: [(notes: [String], fromPages: Bool)] = []
    var timeline = Timeline()

    func plan(for request: String) async throws -> LookupPlan {
        calls.append("plan")
        try? await Task.sleep(for: planDelay)
        timeline.add("planned")
        guard let plan else { throw Refused() }
        return plan
    }

    func notes(on text: String, title: String, request: String, search: String) async throws -> String {
        calls.append("notes")
        timeline.add("notes \(title)")
        noteTexts.append(text)
        noteTitles.append(title)
        if notesFail { throw Refused() }
        return title == "Silent" ? "NONE" : "- Opened in 1956 says \(title)"
    }

    func answer(request: String, kind: LookupKind, notes: [String], fromPages: Bool, smaller: Bool) async throws -> LookupAnswer {
        calls.append(smaller ? "answer-smaller" : "answer")
        answerKinds.append(kind)
        answerInputs.append((notes, fromPages))
        if answerFailures > 0 {
            answerFailures -= 1
            throw answerError
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
    var pageDelay: Duration = .zero
    /// Addresses whose download never finishes on its own.
    var hanging: Set<URL> = []
    var onSearch: () -> Void = {}
    var timeline = Timeline()

    func search(_ query: String) async -> [LookupHit] {
        log.append("search \(query)")
        onSearch()
        return hits[query] ?? []
    }

    func fetch(_ url: URL) async -> (title: String?, image: URL?, text: String)? {
        log.append("fetch \(url.host ?? "")")
        try? await Task.sleep(for: fetchDelay)
        timeline.add("fetched \(url.host ?? "")")
        return fetched[url]
    }

    func readInPage(_ url: URL, booking: Bool) async -> LookupReadPage? {
        log.append("page \(url.host ?? "")\(booking ? " booking \(url.query ?? "")" : "")")
        timeline.add("page \(url.host ?? "")")
        try? await Task.sleep(for: pageDelay)
        timeline.add("paged \(url.host ?? "")")
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
            let model = StubModel()
            model.timeline = reader.timeline
            return (model, reader)
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

        // MARK: the request's own search and its fetches start beside the plan
        (model, reader) = world()
        model.planDelay = .milliseconds(200)
        record = await run(model, reader, stages: &stages)
        var order = model.timeline
        precondition(order.index("fetched a.com") < order.index("planned"), "the plan call does not hold the reading: \(order.all)")
        precondition(reader.log.filter { $0.hasPrefix("search ") } == ["search when did it open"] && record.outcome == .done)
        precondition(stages == [.searching, .reading(hosts: ["a.com", "b.com", "c.com"]), .writing])
        // a reader page is the costly kind of reading: it waits for the plan
        precondition(order.index("page b.com") > order.index("planned") && record.sources[1].usedReaderPage)

        // an act plan runs its own search; what the early one fetched is dropped
        (model, reader) = world()
        model.plan = LookupPlan(searches: ["q"], kind: .act)
        reader.hits["q"] = [hit("e.com", "Echo")]
        reader.fetched[url("e.com")] = ("Echo Page", nil, long)
        record = await run(model, reader, stages: &stages)
        precondition(reader.log.filter { $0.hasPrefix("search ") } == ["search when did it open", "search q"])
        precondition(record.sources.map { $0.hit.url.host } == ["e.com"] && record.outcome == .done && stages[1] == .reading(hosts: ["e.com"]))

        // an act plan whose search is the request takes the early one: one search, each page fetched once
        (model, reader) = world()
        model.plan = LookupPlan(searches: ["When Did It Open"], kind: .act)
        record = await run(model, reader, stages: &stages)
        precondition(reader.log.filter { $0.hasPrefix("search ") } == ["search when did it open"], "\(reader.log)")
        precondition(reader.log.filter { $0 == "fetch a.com" }.count == 1 && record.outcome == .done && model.answerKinds == [.choose], "\(reader.log)")

        // a request that lists things is searched in the plan's words, so nothing starts early
        (model, reader) = world()
        model.planDelay = .milliseconds(100)
        model.plan = LookupPlan(searches: ["first", "second"], kind: .choose)
        reader.hits["first"] = [hit("a.com", "Alpha")]
        record = await run(model, reader, request: "the first, or the second", stages: &stages)
        precondition(model.timeline.all.first == "planned" && reader.log.filter { $0.hasPrefix("search ") } == ["search first", "search second"])

        // MARK: one answer call from the pages themselves, where the model has room for them
        (model, reader) = world()
        model.budget = LookupBudget(pageCharacters: 40, pages: 3, answerCharacters: 90)
        record = await run(model, reader, stages: &stages)
        precondition(model.calls == ["plan", "answer"] && record.outcome == .done && record.sources.allSatisfy { $0.notes.isEmpty }, "\(model.calls)")
        precondition(stages == [.searching, .reading(hosts: ["a.com", "b.com", "c.com"]), .writing])
        precondition(model.answerInputs.count == 1 && model.answerInputs[0].fromPages)
        // every page found is given, the unread one as its snippet, and they share the budget
        var given = model.answerInputs[0].notes
        precondition(given.count == 3 && given[0].hasPrefix("Alpha Page (a.com):\n") && given[1].hasPrefix("Beta Page (b.com):\n") && given[2].contains("Snippet of Gamma"))
        precondition(given.map { $0.split(separator: "\n", maxSplits: 1).last?.count ?? 0 } == [33, 33, 24], "\(given)")
        precondition(record.answer?.points.map(\.sentence) == ["Opened in 1956."], "the answer is verified against the pages")

        // the one call fails: notes on each page and the answer from them, as where there is no room
        (model, reader) = world()
        model.budget = LookupBudget(pageCharacters: 40, pages: 3, answerCharacters: 90)
        model.answerFailures = 1
        model.answerError = ModelSaid.refusal("no")
        record = await run(model, reader, stages: &stages)
        precondition(model.calls == ["plan", "answer", "notes", "notes", "answer"] && record.outcome == .done, "\(model.calls)")
        precondition(model.answerInputs.map(\.fromPages) == [true, false] && record.sources[0].notes.contains("1956"))
        precondition(stages == [.searching, .reading(hosts: ["a.com", "b.com", "c.com"]), .writing], "the cover never steps back")

        // four pages read by fetch fill the one call: the thin ones get no reader page
        (model, reader) = world()
        model.budget = LookupBudget(pageCharacters: 40, pages: 6, answerCharacters: 160)
        reader.hits["when did it open"]! += [hit("e.com", "Echo"), hit("f.com", "Foxtrot")]
        for host in ["c.com", "d.com", "e.com"] { reader.fetched[url(host)] = ("\(host) Page", nil, long) }
        record = await run(model, reader, stages: &stages)
        precondition(!reader.log.contains { $0.hasPrefix("page ") }, "\(reader.log)")
        // and are left off the page: nobody tried them, so they are not listed as pages that would not load
        precondition(record.sources.map { $0.hit.url.host } == ["a.com", "c.com", "d.com", "e.com"] && record.sources.allSatisfy(\.wasRead) && record.outcome == .done,
                     "\(record.sources.map { ($0.hit.url.host ?? "", $0.wasRead) })")
        given = model.answerInputs[0].notes
        precondition(given.count == 4 && !given.contains { $0.contains("Snippet of") })
        let filledPage = (try? String(contentsOf: LookupStore.pageURL(for: record.id, in: support), encoding: .utf8)) ?? ""
        precondition(!filledPage.isEmpty && !filledPage.contains("would not load"))
        // three are not enough: the thin pages are read in reader pages first
        (model, reader) = world()
        model.budget = LookupBudget(pageCharacters: 40, pages: 6, answerCharacters: 120)
        for host in ["c.com", "d.com"] { reader.fetched[url(host)] = ("\(host) Page", nil, long) }
        record = await run(model, reader, stages: &stages)
        precondition(reader.log.contains("page b.com") && record.sources[1].usedReaderPage && model.calls == ["plan", "answer"])

        // no page could be read: the snippets are the notes, as before, and nothing is called pages
        (model, reader) = world()
        model.budget = LookupBudget(pageCharacters: 40, pages: 3, answerCharacters: 90)
        reader.fetched = [:]
        reader.pages = [:]
        record = await run(model, reader, stages: &stages)
        precondition(model.calls == ["plan", "answer"] && model.answerInputs.map(\.fromPages) == [false], "\(model.calls)")
        precondition(record.sources.allSatisfy { !$0.wasRead && $0.notes.hasPrefix("Snippet of") } && stages.last == .writing)

        // MARK: where the answer is written from notes, they start while reader pages still load
        (model, reader) = world()
        reader.pageDelay = .milliseconds(300)
        record = await run(model, reader, stages: &stages)
        order = model.timeline
        precondition(order.index("notes Alpha Page") < order.index("paged b.com"), "a slow reader page does not leave the model idle: \(order.all)")
        precondition(record.outcome == .done && record.sources[1].notes.contains("Beta Page") && model.calls == ["plan", "notes", "notes", "answer"])

        // MARK: a refusal gets no second try
        for refusal in [ModelSaid.refusal("no"), ModelSaid.guardrailViolation("no")] {
            (model, reader) = world()
            model.answerFailures = 2
            model.answerError = refusal
            record = await run(model, reader, stages: &stages)
            precondition(record.outcome == .failed && model.calls == ["plan", "notes", "notes", "answer"], "\(model.calls)")
        }

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
        precondition(record.outcome == .done && reader.log.filter { $0.hasPrefix("search ") } == ["search when did it open"] && record.plan?.kind == .explain)

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
        precondition(reader.log.filter { $0.hasPrefix("search ") } == ["search buy 2 tickets for the lion king next saturday", "search lion king tickets"], "\(reader.log)")

        // details but no booking page in the results: laid out as choices, like any other act request
        (model, reader) = world()
        model.plan = LookupPlan(searches: ["x"], kind: .act)
        model.bookingReply = BookingDetails(people: 2, date: "2026-11-16")
        reader.hits["x"] = reader.hits["when did it open"]
        record = await run(model, reader, stages: &stages)
        precondition(record.outcome == .done && model.answerKinds == [.choose] && record.sources.allSatisfy { $0.prefilledURL == nil })

        // MARK: a streamed answer keeps what it held when its stream failed or went quiet
        typealias Report = @Sendable (Int) -> Void
        var kept = try? await LookupStream.last(stall: .seconds(5)) { (report: @escaping Report) in report(1); report(2); throw Refused() }
        precondition(kept?.value == 2 && kept?.failure is Refused && kept?.wentQuiet == false)
        kept = try? await LookupStream.last(stall: .milliseconds(100)) { (report: @escaping Report) in report(7); try await Task.sleep(for: .seconds(30)) }
        precondition(kept?.value == 7 && kept?.failure == nil && kept?.wentQuiet == true)
        // the same value again is not progress: blank tokens do not keep a stream alive
        kept = try? await LookupStream.last(stall: .milliseconds(100)) { (report: @escaping Report) in
            for _ in 0..<100 { report(7); try await Task.sleep(for: .milliseconds(20)) }
        }
        precondition(kept?.value == 7 && kept?.wentQuiet == true)
        // before its first value a stream is waiting on the model, however long
        kept = try? await LookupStream.last(stall: .milliseconds(50)) { (report: @escaping Report) in try await Task.sleep(for: .milliseconds(400)); report(3) }
        precondition(kept?.value == 3 && kept?.wentQuiet == false)
        // a refusal and a stop are thrown, whatever was written
        do {
            _ = try await LookupStream.last(stall: .seconds(5), fatal: LookupModelError.isRefusal) { (report: @escaping Report) in report(1); throw ModelSaid.refusal("no") }
            preconditionFailure("a refusal is not an answer")
        } catch {
            precondition(error is ModelSaid)
        }
        let streaming = Task { try await LookupStream.last(stall: .seconds(5)) { (report: @escaping Report) in report(1); try await Task.sleep(for: .seconds(30)) } }
        try? await Task.sleep(for: .milliseconds(50))
        streaming.cancel()
        let stopped = try? await streaming.value
        precondition(stopped == nil, "a stopped lookup keeps nothing")

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
