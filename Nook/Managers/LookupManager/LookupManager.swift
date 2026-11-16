// Licensed under GPL-3.0. See LICENSE.
//
//  LookupManager.swift
//  Nook
//
//  Look It Up: the person types a request, and a tab becomes a page answering it from pages
//  Nook read. This owns the lookups in flight; `LookupPipeline` does the work and `LookupStore`
//  keeps the result. Nothing here runs until a lookup is asked for.
//

import AppKit
import Foundation
import NookSettings
import NookWeb
import OSLog

@MainActor
@Observable
final class LookupManager {
    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "Lookup")

    /// The stage of each lookup in flight, by lookup id. The tab's cover reads it.
    private(set) var stages: [UUID: LookupStage] = [:]
    /// The sites a lookup in flight is reading, kept once reading has begun.
    private(set) var hosts: [UUID: [String]] = [:]

    @ObservationIgnored private var tasks: [UUID: Task<LookupRecord, Never>] = [:]
    /// The request behind each lookup asked about, nil for one whose record could not be read.
    @ObservationIgnored private var requests: [UUID: String?] = [:]
    /// The tab each lookup in flight was started in.
    @ObservationIgnored private var tabs: [UUID: UUID] = [:]
    @ObservationIgnored private weak var browserManager: BrowserManager?

    /// The folder `Lookups/` lives in: the one that holds `Tabs/`, so a run against another
    /// state directory keeps its lookups there too.
    let support: URL

    init(browserManager: BrowserManager) {
        self.browserManager = browserManager
        support = browserManager.tabs.lookupSupport ?? browserManager.tabs.directory.deletingLastPathComponent()
    }

    // MARK: - Availability

    /// Whether Shift-Return may start a lookup from `window`: with the setting on, never in a
    /// private window, since the answer is a file on disk, and only with a model to write it.
    func isAvailable(in window: BrowserWindowState) -> Bool {
        browserManager?.nookSettings?.lookupEnabled != false && !window.isIncognito && hasModel
    }

    /// Asked on every palette keystroke, so it builds nothing.
    private var hasModel: Bool {
        if browserManager?.aiService?.hasPlainProvider == true { return true }
        if #available(macOS 26, *) { return OnDeviceLookupModel.isAvailable }
        return false
    }

    /// The connected provider when it is the active one and usable, else the system model.
    private func model() -> (model: LookupModel, together: Bool)? {
        if let plain = browserManager?.aiService?.plainProvider() {
            return (ProviderLookupModel(provider: plain.provider, model: plain.model, config: plain.config), true)
        }
        if #available(macOS 26, *), OnDeviceLookupModel.isAvailable { return (OnDeviceLookupModel(), false) }
        return nil
    }

    // MARK: - Running

    /// Starts a lookup and returns its id at once. Its record and page are on disk from the
    /// start and are rewritten when it ends.
    @discardableResult
    func begin(_ request: String, accentHex: String, id: UUID = UUID()) -> UUID {
        let record = LookupRecord(id: id, request: request, searchURL: searchURL(for: request), accentHex: accentHex)
        requests[id] = request
        tasks[id] = Task { @MainActor [weak self] in
            guard let self else { return record }
            let finished = await self.work(record)
            self.tasks[id] = nil
            self.stages[id] = nil
            self.hosts[id] = nil
            // The tab shows the placeholder under its cover; now it shows what was written.
            if let item = self.tabs.removeValue(forKey: id), let session = self.browserManager?.tabs.session(for: item),
               session.webView != nil, LookupStore.lookupID(ofPage: session.url, in: self.support) == id {
                session.load(LookupStore.pageURL(for: id, in: self.support))
            }
            Self.log.info("Lookup ended: \(finished.outcome.rawValue, privacy: .public), \(finished.sources.count) pages, \(finished.seconds, format: .fixed(precision: 1)) s")
            return finished
        }
        return id
    }

    /// Stops a lookup. Its cover goes at once; the work behind it winds down in its own time.
    func stop(_ id: UUID) {
        tasks[id]?.cancel()
        stages[id] = nil
        hosts[id] = nil
    }

    func isRunning(_ id: UUID) -> Bool { tasks[id] != nil }

    private func work(_ start: LookupRecord) async -> LookupRecord {
        guard let browserManager, let chosen = model(), let host = browserManager.lookupReaderHost() else {
            var failed = start
            failed.outcome = .failed
            try? LookupStore.write(failed, in: support)
            return failed
        }
        // Reader pages get a data store of their own, gone with the lookup: no logins, no trace.
        let profile = Profile.createEphemeral()
        defer { profile.destroyEphemeralDataStore() }
        let reader = LookupReader(tabs: browserManager.tabs, host: host, profile: profile)
        var pipeline = LookupPipeline(model: chosen.model, reader: reader, support: support, notesTogether: chosen.together)
        pipeline.log = { Self.log.info("Lookup: \($0, privacy: .public)") }
        return await pipeline.run(start) { [weak self] stage in
            // A stopped lookup keeps running to its next check; its cover stays down.
            guard let self, self.tasks[start.id]?.isCancelled == false else { return }
            self.stages[start.id] = stage
            if case .reading(let hosts) = stage { self.hosts[start.id] = hosts }
        }
    }

    // MARK: - Tabs

    /// Opens a tab for `request` in `window` and starts the lookup behind it. Returns the tab's id.
    /// `space` puts the tab in another space without showing it, which is how DevMCP runs one.
    @discardableResult
    func start(_ request: String, in window: BrowserWindowState, space: UUID? = nil) -> UUID? {
        guard let browserManager, isAvailable(in: window) else { return nil }
        let id = UUID()
        let accent = browserManager.gradientColorManager.accentNSColor.toHexString() ?? LookupRecord.defaultAccent
        // The placeholder page is on disk before the tab asks for it.
        try? LookupStore.write(LookupRecord(id: id, request: request, searchURL: searchURL(for: request), accentHex: accent), in: support)
        begin(request, accentHex: accent, id: id)
        let item = browserManager.tabs.open(
            url: LookupStore.pageURL(for: id, in: support), in: window, placement: .newTab,
            parent: space.map { .tabs(spaceID: $0) }, title: request)
        if let item { tabs[id] = item } else { stop(id) }
        return item
    }

    /// The stage of the lookup behind an answer page, nil once it has ended. Asked for every
    /// page a window shows, so anything that is not a lookup in flight costs nothing.
    func stage(forPage url: URL) -> LookupStage? {
        guard !stages.isEmpty, url.isFileURL else { return nil }
        return LookupStore.lookupID(ofPage: url, in: support).flatMap { stages[$0] }
    }

    func hosts(forPage url: URL) -> [String] {
        LookupStore.lookupID(ofPage: url, in: support).flatMap { hosts[$0] } ?? []
    }

    func stop(page url: URL) {
        if let id = LookupStore.lookupID(ofPage: url, in: support) { stop(id) }
    }

    /// A closed tab takes its lookup with it.
    func tabClosed(_ item: UUID) {
        for (id, tab) in tabs where tab == item { stop(id) }
    }

    /// Deletes the folders of lookups nothing points at any more, once at launch. The folder is
    /// looked at off the main actor first: most launches have no lookups, and then that is all.
    func sweep() {
        let support = support
        let cutoff = Date()
        Task.detached(priority: .utility) { [weak self] in
            guard LookupStore.hasLookups(in: support), let kept = await self?.keptLookups() else { return }
            LookupStore.sweep(keeping: kept, in: support, olderThan: cutoff)
        }
    }

    /// Nil when the tab files could not be read: nothing is deleted on a stand-in tree's word.
    private func keptLookups() -> Set<UUID>? {
        browserManager?.tabs.referencedLookupIDs().map { $0.union(tasks.keys) }
    }

    // MARK: - Lookups by Page

    /// The request behind an answer page, for the URL bar.
    func request(forPage url: URL) -> String? {
        guard let id = LookupStore.lookupID(ofPage: url, in: support) else { return nil }
        if let known = requests[id] { return known }
        let saved = LookupStore.record(for: id, in: support)?.request
        requests[id] = .some(saved)
        return saved
    }

    /// The same text as an ordinary search in the person's search engine.
    private func searchURL(for request: String) -> URL? {
        let template = browserManager?.nookSettings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
        return URL(string: normalizeURL(request, queryTemplate: template))
    }
}
