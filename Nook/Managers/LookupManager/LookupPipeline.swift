// Licensed under GPL-3.0. See LICENSE.
//
//  LookupPipeline.swift
//  Nook
//
//  One lookup from request to page: plan, search, read, take notes, write, verify, save. It
//  talks to the web through `LookupReading` and to a model through `LookupModel`, so
//  `scripts/tests/LookupPipelineCheck.swift` runs it against stubs. NookWeb is imported only when
//  it exists, for the same reason.
//

import Foundation
#if canImport(NookWeb)
import NookWeb
#endif

/// How a lookup reaches the web. `LookupReader` is the real one.
@MainActor
protocol LookupReading: AnyObject {
    func search(_ query: String) async -> [LookupHit]
    func fetch(_ url: URL) async -> (title: String?, image: URL?, text: String)?
    /// Loads `url` in a reader page and returns what it shows. `booking` also asks for the
    /// page's controls, heading and picture.
    func readInPage(_ url: URL, booking: Bool) async -> LookupReadPage?
    /// A picture's bytes: nil unless it arrives whole, within `limit`, and is an image.
    func data(_ url: URL, limit: Int) async -> Data?
    /// The site's icon as image data, nil when it has none worth showing.
    func icon(for url: URL) async -> Data?
    func endAll()
}

/// What a reader page showed.
struct LookupReadPage {
    var title: String
    var text: String
    /// Booking pages only: the controls by label, the first heading, and a JPEG of the page's top.
    var labels: [String] = []
    var heading = ""
    var shot: Data?
}

/// What the tab's cover shows while a lookup runs.
enum LookupStage: Equatable {
    case searching
    case reading(hosts: [String])
    case writing
}

@MainActor
struct LookupPipeline {
    /// A read that gives fewer characters than this is no read: the snippet stands in.
    private static let leastText = 300
    private static let maxPhotoBytes = 3_000_000
    private static let maxPhotos = 5
    private static let photoTypes = ["jpg", "jpeg", "png", "webp", "gif"]
    /// A request and a title go into every prompt, so each has a ceiling. A 50,000 character
    /// title would fill the on-device context by itself.
    private static let maxRequest = 500
    private static let maxTitle = 200
    /// Pages read by a plain fetch that are enough for the one answer call: the scored eval's
    /// answers are written from four.
    private static let enoughPages = 4

    private typealias Fetched = (title: String?, image: URL?, text: String)

    let model: LookupModel
    let reader: LookupReading
    let support: URL
    /// A network model takes its notes calls together; the on-device model runs one at a time anyway.
    let notesTogether: Bool
    /// How long a finished answer waits for photos and icons still coming down.
    var imageWait: Duration = .seconds(3)
    /// Told when a model call fails, with the error's type and case.
    var log: @MainActor (String) -> Void = { _ in }
    /// The day "tomorrow" is counted from.
    var today = Date()
    private static let maxAbout = 240

    /// File names saved so far, by source index. Filled as downloads finish, read at the deadline.
    private final class SavedImages {
        var files: [Int: (photo: String?, icon: String?)] = [:]
    }

    /// Runs `start` to its end and returns the finished record, which is also on disk with its
    /// page. A cancelled task ends as `.stopped`.
    func run(_ start: LookupRecord, onStage: @MainActor (LookupStage) -> Void) async -> LookupRecord {
        var record = start
        record.request = String(start.request.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxRequest))
        record.outcome = .running
        let began = Date()
        func finish(_ outcome: LookupOutcome) -> LookupRecord {
            record.outcome = outcome
            record.seconds = Date().timeIntervalSince(began)
            reader.endAll()
            try? LookupStore.write(record, in: support)
            return record
        }
        // On disk before any work, so a relaunch mid-run restores a page that says something.
        try? LookupStore.write(record, in: support)
        onStage(.searching)

        // A short request that lists nothing is searched in the person's own words unless an act
        // plan words it otherwise. That search and its fetches start now, beside the plan call.
        let budget = model.budget
        let own = LookupSearch.ownSearch(for: record.request)
        let earlyHits = own.map { query in Task { @MainActor in await reader.search(query) } }
        let earlyPages = earlyHits.map { hits in
            Task { @MainActor () -> [URL: Fetched] in
                let picked = LookupSearch.pick([await hits.value], limit: budget.pages)
                return Task.isCancelled ? [:] : await fetch(picked.map(\.hit.url))
            }
        }
        defer {
            earlyHits?.cancel()
            earlyPages?.cancel()
        }

        // A refused plan is not the end: the request itself is a search.
        let planned: LookupPlan
        do {
            planned = try await model.plan(for: record.request)
        } catch {
            if !(error is CancellationError) { log("plan failed: \(Self.describe(error))") }
            planned = LookupPlan(searches: [], kind: .explain)
        }
        if Task.isCancelled { return finish(.stopped) }
        let searches = LookupSearch.normalized(planned.searches, request: record.request, kind: planned.kind)
        record.plan = LookupPlan(searches: searches, kind: planned.kind)
        guard !searches.isEmpty else { return finish(.nothingFound) }
        // The early search is the lookup's own unless the plan asked for others.
        let early = own.map { searches.count == 1 && searches[0].caseInsensitiveCompare($0) == .orderedSame } == true
        if !early {
            earlyHits?.cancel()
            earlyPages?.cancel()
        }

        // What a booking asks for. The day is settled in code where the request says it in words.
        var details: BookingDetails?
        if planned.kind == .act {
            do {
                let said = try await model.booking(in: record.request, today: today)
                let settled = BookingCalendar.corrected(said, request: record.request, today: today)
                if settled.hasDetails { details = settled }
            } catch {
                if !(error is CancellationError) { log("booking failed: \(Self.describe(error))") }
            }
        }
        record.booking = details

        // One at a time: the results endpoint answers a burst with a bot check, for the whole
        // address and for a long while.
        var hitsBySearch: [[LookupHit]] = []
        if early, let earlyHits {
            hitsBySearch = [await Self.value(of: earlyHits)]
        } else {
            for search in searches where !Task.isCancelled {
                hitsBySearch.append(await reader.search(search))
            }
        }
        if Task.isCancelled { return finish(.stopped) }
        // A venue page counts as a place's own only when the person named that place.
        let request = record.request
        func isPlace(_ hit: LookupHit, _ search: Int) -> Bool {
            searches.indices.contains(search) && BookingSites.isPlace(hit.url, request: request, search: searches[search])
        }
        // A place whose search held no such page gets one more search a booking site, within the
        // lookup's four in all. An early search the plan did not use is one of the four.
        if details != nil {
            var sent = searches.count + (own != nil && !early ? 1 : 0)
            for (index, search) in searches.enumerated() where !hitsBySearch[index].contains(where: { isPlace($0, index) }) {
                for word in BookingSites.searchWords(for: request) where sent < LookupSearch.maxSearches && !Task.isCancelled {
                    sent += 1
                    guard let venue = await reader.search("\(search) \(word)").first(where: { isPlace($0, index) }) else { continue }
                    hitsBySearch[index].insert(venue, at: 0)
                    break
                }
            }
            if Task.isCancelled { return finish(.stopped) }
        }
        var picked = LookupSearch.pick(hitsBySearch, limit: budget.pages)
        // A booking reads one page a place: the place's own booking page when the results hold
        // one. With no such page anywhere it is laid out as choices, like any other act request.
        var isBooking = false
        if details != nil {
            let placesFirst = hitsBySearch.enumerated().map { index, hits in
                hits.filter { isPlace($0, index) } + hits.filter { !isPlace($0, index) }
            }
            let onePerPlace = LookupSearch.pick(placesFirst, limit: placesFirst.count)
            if onePerPlace.contains(where: { isPlace($0.hit, $0.search) }) {
                picked = onePerPlace
                isBooking = true
            }
        }
        guard !picked.isEmpty else { return finish(.nothingFound) }
        record.sources = picked.map { LookupSource(hit: $0.hit, search: $0.search, title: String($0.hit.title.prefix(Self.maxTitle))) }
        if isBooking, let details {
            for index in record.sources.indices where isPlace(record.sources[index].hit, record.sources[index].search) {
                let url = record.sources[index].hit.url
                record.sources[index].prefilledURL = BookingSites.prefilled(url, details) ?? url
            }
        }
        onStage(.reading(hosts: record.sources.map { Self.host($0.hit.url) }))

        // Every source is fetched, then the thin ones load in reader pages. A booking page skips
        // the fetch: its reader page also gives its controls, heading and picture.
        let urls = record.sources.map { $0.prefilledURL ?? $0.hit.url }
        let venues = Set(record.sources.indices.filter { record.sources[$0].prefilledURL != nil })
        let fetched: [URL: Fetched]
        if early, let earlyPages {
            fetched = await Self.value(of: earlyPages)
        } else {
            fetched = await fetch(urls.indices.filter { !venues.contains($0) }.map { urls[$0] })
        }
        if Task.isCancelled { return finish(.stopped) }
        let thin = urls.indices.filter { venues.contains($0) || (fetched[urls[$0]]?.text.count ?? 0) < LookupText.thin }
        // Where the model has room, the answer is one call from the pages themselves.
        let direct = !isBooking && budget.answerCharacters > 0
        // Enough pages came whole by fetch to fill that call: the thin ones wait for no reader page.
        let whole = urls.indices.filter { !thin.contains($0) }
        let filled = whole.count >= Self.enoughPages
            && whole.reduce(0) { $0 + min(fetched[urls[$1]]?.text.count ?? 0, budget.pageCharacters) } >= budget.answerCharacters
        let waiting = direct && filled ? [] : thin
        var images = [URL?](repeating: nil, count: urls.count)
        let id = record.id
        func settle(_ index: Int, _ page: LookupReadPage?) {
            let got = fetched[urls[index]]
            images[index] = got?.image
            record.sources[index] = settled(record.sources[index], index: index, fetched: got, page: page, isVenue: venues.contains(index), searches: searches, lookup: id)
        }
        for index in urls.indices where !waiting.contains(index) { settle(index, nil) }
        // Where the answer is written from notes, the model takes them on what the fetch read
        // while the reader pages load.
        async let pages = readPages(waiting.map { (index: $0, url: urls[$0], booking: venues.contains($0)) })
        if !isBooking, !direct {
            await takeNotes(&record, searches: searches, on: urls.indices.filter { !waiting.contains($0) })
        }
        for (index, page) in await pages { settle(index, page) }
        if Task.isCancelled { return finish(.stopped) }
        // A thin page nobody waited for was not read. It leaves the list, so the page does not
        // say of it that it would not load.
        if direct && filled {
            let read = record.sources.indices.filter { record.sources[$0].wasRead }
            record.sources = read.map { record.sources[$0] }
            images = read.map { images[$0] }
        }
        // Photos and icons come down while the model works; they are only waited for at the end.
        let read = record.sources
        let saved = SavedImages()
        let saving = Task { @MainActor [images] in await saveImages(for: read, images: images, lookup: id, into: saved) }
        defer { saving.cancel() }

        if isBooking {
            // The cards carry the page: its picture, its times read in code, one line about the
            // place. Nothing is written across pages, so no notes and no answer.
            onStage(.writing)
            await describePlaces(&record)
            if Task.isCancelled { return finish(.stopped) }
            await Self.wait(for: saving, atMost: imageWait)
            for (index, files) in saved.files where record.sources.indices.contains(index) { record.sources[index].iconFile = files.icon }
            return finish(.done)
        }

        // An act request is laid out as choices; booking pages get their own cards on top.
        let shape: LookupKind = planned.kind == .explain ? .explain : .choose
        var answer: LookupAnswer?
        // With no page read there is no page text to write from: the snippets are the notes.
        let fromPages = direct && record.sources.contains(where: \.wasRead)
        if fromPages {
            onStage(.writing)
            answer = await write(record, shape: shape, fromPages: true)
            if Task.isCancelled { return finish(.stopped) }
        }
        if answer == nil {
            // From notes: the model has no room for the pages, or its one call came to nothing.
            await takeNotes(&record, searches: searches, on: direct ? Array(record.sources.indices) : waiting)
            if Task.isCancelled { return finish(.stopped) }
            if !fromPages { onStage(.writing) }
            guard record.sources.contains(where: Self.hasNotes) else { return finish(.failed) }
            answer = await write(record, shape: shape, fromPages: false)
            if Task.isCancelled { return finish(.stopped) }
        }
        guard let answer else { return finish(.failed) }
        record.answer = answer

        // What has arrived by now is used. A download still running after `imageWait` is dropped,
        // so a slow or endless image cannot hold a finished answer.
        await Self.wait(for: saving, atMost: imageWait)
        for (index, files) in saved.files where record.sources.indices.contains(index) {
            record.sources[index].imageFile = files.photo
            record.sources[index].iconFile = files.icon
        }
        if Task.isCancelled { return finish(.stopped) }
        return finish(.done)
    }

    // MARK: - Writing

    /// The answer from the pages' own text or from their notes, verified. Nil when the model wrote
    /// nothing that stands.
    private func write(_ record: LookupRecord, shape: LookupKind, fromPages: Bool) async -> LookupAnswer? {
        let texts = fromPages
            ? LookupText.excerpts(record.sources.map(\.text), characters: model.budget.answerCharacters)
            : record.sources.map { $0.notes.isEmpty ? "NONE" : $0.notes }
        let material = zip(record.sources, texts).map { "\($0.title) (\(Self.host($0.hit.url))):\n\($1)" }
        var written: LookupAnswer?
        // The smaller shape is for an answer that was cut off or could not be read. A refusal
        // would be refused again, and the pages' own call falls back to notes instead.
        for smaller in (fromPages ? [false] : [false, true]) where written == nil && !Task.isCancelled {
            do {
                written = try await model.answer(request: record.request, kind: shape, notes: material, fromPages: fromPages, smaller: smaller)
            } catch {
                if !(error is CancellationError) { log("answer failed\(fromPages ? " (pages)" : "")\(smaller ? " (smaller)" : ""): \(Self.describe(error))") }
                if LookupModelError.isRefusal(error) { break }
            }
        }
        guard let written else { return nil }
        let corpus = (record.sources.map(\.notes) + record.sources.map(\.text)).joined(separator: "\n")
        let answer = LookupVerify.cleaned(written, sourceCount: record.sources.count, corpus: corpus)
        return answer.isEmpty ? nil : answer
    }

    // MARK: - Reading

    /// Every address fetched at once, by address. One that could not be fetched is left out.
    private func fetch(_ urls: [URL]) async -> [URL: Fetched] {
        await withTaskGroup(of: (URL, Fetched?).self) { group in
            for url in urls {
                group.addTask { @MainActor in (url, await reader.fetch(url)) }
            }
            var fetched: [URL: Fetched] = [:]
            for await (url, page) in group { fetched[url] = page }
            return fetched
        }
    }

    /// Loads each address in a reader page, all at once; the reader keeps three open.
    private func readPages(_ wanted: [(index: Int, url: URL, booking: Bool)]) async -> [(Int, LookupReadPage?)] {
        guard !wanted.isEmpty, !Task.isCancelled else { return [] }
        return await withTaskGroup(of: (Int, LookupReadPage?).self) { group in
            for page in wanted {
                group.addTask { @MainActor in (page.index, await reader.readInPage(page.url, booking: page.booking)) }
            }
            var pages: [(Int, LookupReadPage?)] = []
            for await page in group { pages.append(page) }
            return pages
        }
    }

    /// `source` as its fetch and its reader page left it. A venue also takes its name, its times
    /// and its picture from its reader page.
    private func settled(_ source: LookupSource, index: Int, fetched: Fetched?, page: LookupReadPage?, isVenue: Bool,
                         searches: [String], lookup: UUID) -> LookupSource {
        var source = source
        let byFetch = fetched?.text ?? ""
        let byPage = page?.text ?? ""
        let usedPage = byPage.count > byFetch.count
        let text = usedPage ? byPage : byFetch
        if text.count >= Self.leastText {
            // Kept as the model is given it: the record stays small, and what verification
            // checks an answer against is what the model could have read.
            source.text = LookupText.excerpt(text, characters: model.budget.pageCharacters)
            source.wasRead = true
            source.usedReaderPage = usedPage
            let title = (usedPage ? page?.title : fetched?.title) ?? ""
            if !title.isEmpty { source.title = String(title.prefix(Self.maxTitle)) }
        } else {
            source.text = source.hit.title + ". " + source.hit.snippet
        }
        guard isVenue else { return source }
        // A venue's card is named by its page's own heading, else by what was searched for.
        let searched = searches.indices.contains(source.search) ? searches[source.search] : source.title
        let heading = page?.heading.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        source.name = String((heading.isEmpty || !source.wasRead ? searched : heading).prefix(Self.maxTitle))
        guard source.wasRead, let page else { return source }
        source.times = LookupTimes.times(inLabels: page.labels)
        if let shot = page.shot {
            let folder = LookupStore.folder(for: lookup, in: support)
            let name = "shot\(index + 1).jpg"
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if (try? shot.write(to: folder.appendingPathComponent(name))) != nil { source.shotFile = name }
        }
        return source
    }

    // MARK: - Places

    /// One line about each place that was read, from its own page. A line holding a figure the
    /// page does not, or saying what the page left out, is dropped.
    private func describePlaces(_ record: inout LookupRecord) async {
        let model = model
        let log = log
        func about(_ source: LookupSource) async -> String {
            guard source.wasRead else { return "" }
            do {
                let line = try await model.about(source.text, title: source.title).trimmingCharacters(in: .whitespacesAndNewlines)
                let known = Set(LookupVerify.figures(in: source.text))
                guard LookupVerify.figures(in: line).allSatisfy(known.contains), !LookupVerify.admitsGap(line) else { return "" }
                return String(line.prefix(Self.maxAbout))
            } catch {
                if !(error is CancellationError) { log("about failed: \(Self.describe(error))") }
                return ""
            }
        }
        if notesTogether {
            let sources = record.sources
            await withTaskGroup(of: (Int, String).self) { group in
                for (index, source) in sources.enumerated() {
                    group.addTask { (index, await about(source)) }
                }
                for await (index, line) in group { record.sources[index].about = line }
            }
        } else {
            for index in record.sources.indices where !Task.isCancelled {
                record.sources[index].about = await about(record.sources[index])
            }
        }
    }

    // MARK: - Notes

    /// One model call a page that was read, for the pages at `indices`. A page that was not read
    /// keeps its search snippet as its note.
    private func takeNotes(_ record: inout LookupRecord, searches: [String], on indices: [Int]) async {
        let request = record.request
        let model = model
        let log = log
        func note(_ source: LookupSource) async -> String {
            guard source.wasRead else { return source.hit.snippet }
            let search = searches.indices.contains(source.search) ? searches[source.search] : request
            do {
                return try await model.notes(on: source.text, title: source.title, request: request, search: search)
            } catch {
                if !(error is CancellationError) { log("notes failed: \(Self.describe(error))") }
                return ""
            }
        }
        if notesTogether {
            let sources = record.sources
            await withTaskGroup(of: (Int, String).self) { group in
                for index in indices {
                    group.addTask { (index, await note(sources[index])) }
                }
                for await (index, text) in group { record.sources[index].notes = text }
            }
        } else {
            for index in indices where !Task.isCancelled {
                record.sources[index].notes = await note(record.sources[index])
            }
        }
    }

    private static func hasNotes(_ source: LookupSource) -> Bool {
        let notes = source.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        return !notes.isEmpty && notes.uppercased() != "NONE"
    }

    // MARK: - Images

    /// Saves each read page's lead image and icon into the lookup's folder, so the page loads
    /// nothing from the network. Each file name goes into `saved` as its download finishes.
    private func saveImages(for sources: [LookupSource], images: [URL?], lookup: UUID, into saved: SavedImages) async {
        let folder = LookupStore.folder(for: lookup, in: support)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let wanted = sources.indices.filter { sources[$0].wasRead }
        let withPhoto = Set(wanted.filter { images[$0] != nil }.prefix(Self.maxPhotos))
        await withTaskGroup(of: Void.self) { group in
            for index in wanted {
                group.addTask { @MainActor in
                    var photo: String?
                    if withPhoto.contains(index), let url = images[index], let data = await reader.data(url, limit: Self.maxPhotoBytes), !Task.isCancelled {
                        let type = url.pathExtension.lowercased()
                        let name = "photo\(index + 1)." + (Self.photoTypes.contains(type) ? type : "jpg")
                        if (try? data.write(to: folder.appendingPathComponent(name))) != nil { photo = name }
                    }
                    saved.files[index] = (photo, nil)
                    if let data = await reader.icon(for: sources[index].hit.url), !Task.isCancelled {
                        let name = "icon\(index + 1).png"
                        if (try? data.write(to: folder.appendingPathComponent(name))) != nil { saved.files[index] = (photo, name) }
                    }
                }
            }
        }
    }

    /// `task`'s value. Stopping the lookup stops the task too.
    private static func value<T: Sendable>(of task: Task<T, Never>) async -> T {
        await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    /// Returns when `task` ends or `limit` passes, whichever is first, and cancels it either way.
    private static func wait(for task: Task<Void, Never>, atMost limit: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await task.value }
            group.addTask { try? await Task.sleep(for: limit) }
            await group.next()
            task.cancel()
            group.cancelAll()
        }
    }

    /// An error's type and case, which is all a FoundationModels error says for itself.
    private static func describe(_ error: Error) -> String {
        let label = Mirror(reflecting: error).children.first?.label
        return String(reflecting: type(of: error)) + (label.map { "." + $0 } ?? "")
    }

    private static func host(_ url: URL) -> String {
        let host = url.host ?? ""
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
