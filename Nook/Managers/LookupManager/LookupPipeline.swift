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
        for search in searches where !Task.isCancelled {
            hitsBySearch.append(await reader.search(search))
        }
        if Task.isCancelled { return finish(.stopped) }
        // A venue page counts as a place's own only when the person named that place.
        let request = record.request
        func isPlace(_ hit: LookupHit, _ search: Int) -> Bool {
            searches.indices.contains(search) && BookingSites.isPlace(hit.url, request: request, search: searches[search])
        }
        // A place whose search held no such page gets one more search a booking site, within the
        // lookup's four in all.
        if details != nil {
            var sent = searches.count
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
        var picked = LookupSearch.pick(hitsBySearch, limit: model.budget.pages)
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

        let images = await read(&record, searches: searches)
        if Task.isCancelled { return finish(.stopped) }
        // Photos and icons come down while the model works; they are only waited for at the end.
        let read = record.sources
        let id = record.id
        let saved = SavedImages()
        let saving = Task { @MainActor in await saveImages(for: read, images: images, lookup: id, into: saved) }
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

        await takeNotes(&record, searches: searches)
        if Task.isCancelled { return finish(.stopped) }

        onStage(.writing)
        let notes = record.sources.map { "\($0.title) (\(Self.host($0.hit.url))):\n\($0.notes.isEmpty ? "NONE" : $0.notes)" }
        guard record.sources.contains(where: Self.hasNotes) else { return finish(.failed) }
        // An act request is laid out as choices; booking pages get their own cards on top.
        let shape: LookupKind = planned.kind == .explain ? .explain : .choose
        var written: LookupAnswer?
        // The smaller shape is for an answer cut off at its token cap; it is tried after any failure.
        for smaller in [false, true] where written == nil && !Task.isCancelled {
            do {
                written = try await model.answer(request: record.request, kind: shape, notes: notes, smaller: smaller)
            } catch {
                if !(error is CancellationError) { log("answer failed\(smaller ? " (smaller)" : ""): \(Self.describe(error))") }
            }
        }
        if Task.isCancelled { return finish(.stopped) }
        guard let written else { return finish(.failed) }
        let corpus = (record.sources.map(\.notes) + record.sources.map(\.text)).joined(separator: "\n")
        let answer = LookupVerify.cleaned(written, sourceCount: record.sources.count, corpus: corpus)
        guard !answer.isEmpty else { return finish(.failed) }
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

    // MARK: - Reading

    /// Fetches every source, then loads the thin ones in reader pages. A booking page skips the
    /// fetch: its prefilled address loads in a reader page, which also gives its controls,
    /// heading and picture. Returns each source's lead image address.
    private func read(_ record: inout LookupRecord, searches: [String]) async -> [URL?] {
        var images = [URL?](repeating: nil, count: record.sources.count)
        var fetched = [(title: String?, image: URL?, text: String)?](repeating: nil, count: record.sources.count)
        let urls = record.sources.map { $0.prefilledURL ?? $0.hit.url }
        let venues = Set(record.sources.indices.filter { record.sources[$0].prefilledURL != nil })
        await withTaskGroup(of: (Int, (title: String?, image: URL?, text: String)?).self) { group in
            for (index, url) in urls.enumerated() where !venues.contains(index) {
                group.addTask { @MainActor in (index, await reader.fetch(url)) }
            }
            for await (index, page) in group { fetched[index] = page }
        }
        var pages = [LookupReadPage?](repeating: nil, count: record.sources.count)
        let thin = urls.indices.filter { venues.contains($0) || (fetched[$0]?.text.count ?? 0) < LookupText.thin }
        if !thin.isEmpty, !Task.isCancelled {
            await withTaskGroup(of: (Int, LookupReadPage?).self) { group in
                for index in thin {
                    group.addTask { @MainActor in (index, await reader.readInPage(urls[index], booking: venues.contains(index))) }
                }
                for await (index, page) in group { pages[index] = page }
            }
        }
        let folder = LookupStore.folder(for: record.id, in: support)
        for index in record.sources.indices {
            let byFetch = fetched[index]?.text ?? ""
            let byPage = pages[index]?.text ?? ""
            let usedPage = byPage.count > byFetch.count
            let text = usedPage ? byPage : byFetch
            images[index] = fetched[index]?.image
            if text.count >= Self.leastText {
                // Kept as the model is given it: the record stays small, and what verification
                // checks an answer against is what the model could have read.
                record.sources[index].text = LookupText.excerpt(text, characters: model.budget.pageCharacters)
                record.sources[index].wasRead = true
                record.sources[index].usedReaderPage = usedPage
                let title = (usedPage ? pages[index]?.title : fetched[index]?.title) ?? ""
                if !title.isEmpty { record.sources[index].title = String(title.prefix(Self.maxTitle)) }
            } else {
                record.sources[index].text = record.sources[index].hit.title + ". " + record.sources[index].hit.snippet
            }
            guard venues.contains(index) else { continue }
            // A venue's card is named by its page's own heading, else by what was searched for.
            let source = record.sources[index]
            let searched = searches.indices.contains(source.search) ? searches[source.search] : source.title
            let heading = pages[index]?.heading.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            record.sources[index].name = String((heading.isEmpty || !source.wasRead ? searched : heading).prefix(Self.maxTitle))
            guard source.wasRead, let page = pages[index] else { continue }
            record.sources[index].times = LookupTimes.times(inLabels: page.labels)
            if let shot = page.shot {
                let name = "shot\(index + 1).jpg"
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                if (try? shot.write(to: folder.appendingPathComponent(name))) != nil { record.sources[index].shotFile = name }
            }
        }
        return images
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

    /// One model call a page that was read. A page that was not keeps its search snippet as its note.
    private func takeNotes(_ record: inout LookupRecord, searches: [String]) async {
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
                for (index, source) in sources.enumerated() {
                    group.addTask { (index, await note(source)) }
                }
                for await (index, text) in group { record.sources[index].notes = text }
            }
        } else {
            for index in record.sources.indices where !Task.isCancelled {
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
