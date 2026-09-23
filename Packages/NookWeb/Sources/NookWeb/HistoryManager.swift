// Licensed under GPL-3.0. See LICENSE.
// History persistence stays on its own executor; UI consumers receive value records.
import Foundation
import SwiftData
import Observation
import OSLog

public struct HistoryVisit: Sendable {
    public let url: URL
    public let title: String
    public let timestamp: Date
    public let tabId: UUID?
    public let profileId: UUID?

    public init(url: URL, title: String, timestamp: Date, tabId: UUID?, profileId: UUID?) {
        self.url = url
        self.title = title
        self.timestamp = timestamp
        self.tabId = tabId
        self.profileId = profileId
    }
}

@MainActor
@Observable
public final class HistoryManager {
    @ObservationIgnored private let storeTask: Task<HistoryStore, Never>
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    public var currentProfileId: UUID?
    /// Visits older than this are pruned at launch, so "All time" in the history panel means this.
    nonisolated public static let retentionDays = 100

    public init(context: ModelContext, profileId: UUID? = nil) {
        currentProfileId = profileId
        let container = context.container
        // Construct the model executor off the main actor as well as calling it there.
        storeTask = Task.detached { HistoryStore(modelContainer: container) }
        // Every space's rows, not only the launch space's.
        enqueue { await $0.clear(days: Self.retentionDays, profile: nil) }
    }

    public func switchProfile(_ profileId: UUID?) { currentProfileId = profileId }

    private func enqueue(_ operation: @escaping @Sendable (HistoryStore) async -> Void) {
        let previous = pendingWrite
        let storeTask = storeTask
        pendingWrite = Task {
            await previous?.value
            await operation(storeTask.value)
        }
    }

    public func addVisit(url: URL, title: String, timestamp: Date = Date(), tabId: UUID?, profileId: UUID? = nil, isEphemeral: Bool = false) {
        guard !isEphemeral else { return }
        importVisits([HistoryVisit(url: url, title: title, timestamp: timestamp, tabId: tabId, profileId: profileId ?? currentProfileId)])
    }

    public func importVisits(_ visits: [HistoryVisit]) {
        enqueue { await $0.addVisits(visits) }
    }

    /// Paged by offset, so a caller that deleted rows it already shows asks for exactly the next ones.
    public func getHistory(days: Int = 7, offset: Int = 0, limit: Int = 50) async -> (entries: [HistoryEntry], hasMore: Bool) {
        let profile = currentProfileId
        await pendingWrite?.value
        return await storeTask.value.history(days: days, profile: profile, offset: offset, limit: limit)
    }

    public func searchHistory(query: String) async -> [HistoryEntry] {
        await searchHistory(query: query, offset: 0, limit: 1000).entries
    }

    public func searchHistory(query: String, offset: Int = 0, limit: Int = 50) async -> (entries: [HistoryEntry], hasMore: Bool) {
        let profile = currentProfileId
        await pendingWrite?.value
        guard !Task.isCancelled else { return ([], false) }
        return await storeTask.value.search(query: query, profile: profile, offset: offset, limit: limit)
    }

    /// Bare host for omnibox inline autofill, e.g. `facebo` -> `facebook.com`. Nil when nothing qualifies.
    /// Skips the pending-write await the other reads take: a keystroke-rate query wants speed, and a
    /// host that is one visit stale autofills the same either way.
    public func autofillHost(prefix: String, minVisits: Int = 2) async -> String? {
        let profile = currentProfileId
        guard !Task.isCancelled else { return nil }
        return await storeTask.value.autofillHost(prefix: prefix, profile: profile, minVisits: minVisits)
    }

    public func clearHistory(olderThan days: Int = 0, profileId: UUID? = nil) {
        let profile = profileId ?? currentProfileId
        enqueue { await $0.clear(days: days, profile: profile) }
    }

    public func deleteHistoryEntry(_ entryId: UUID) {
        enqueue { await $0.delete(entryId) }
    }
}

@ModelActor
actor HistoryStore {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "History")
    /// Past this age the autofill index is rebuilt, whatever it holds.
    private static let indexMaxAge: TimeInterval = 300

    private struct AutofillIndex {
        let profile: UUID?
        let built: Date
        var hosts: [String: HostStat]

        /// Folds a visit in, when this index covers that profile. The test mirrors what
        /// `visible(to:)` selects: an all-profiles index covers every visit, and a per-profile
        /// index also covers the profile-less rows it would have fetched.
        mutating func record(url: String, profile visitProfile: UUID?, at date: Date) {
            guard profile == nil || visitProfile == nil || profile == visitProfile else { return }
            AutofillRanking.add(url: url, visits: 1, at: date, to: &hosts)
        }
    }

    private var autofillCache: AutofillIndex?

    private func visible(to profile: UUID?) -> Predicate<HistoryEntity> {
        guard let profile else { return #Predicate { _ in true } }
        return #Predicate { $0.profileId == profile || $0.profileId == nil }
    }

    private func exactURL(_ url: String, profile: UUID?) throws -> HistoryEntity? {
        var descriptor = FetchDescriptor<HistoryEntity>(predicate: #Predicate { $0.url == url && $0.profileId == profile })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func addVisits(_ visits: [HistoryVisit]) {
        let interval = BrowserPerformance.signposter.beginInterval("HistoryWrite")
        defer { BrowserPerformance.signposter.endInterval("HistoryWrite", interval) }
        modelContext.autosaveEnabled = false
        do {
            for (index, visit) in visits.enumerated() {
                guard visit.url.scheme == "http" || visit.url.scheme == "https" else { continue }
                let url = visit.url.absoluteString
                let existing = try exactURL(url, profile: visit.profileId)
                    ?? (visit.profileId == nil ? nil : exactURL(url, profile: nil))
                if let entry = existing {
                    entry.visitCount += 1
                    // An import of older history must not move a recent visit backwards.
                    if visit.timestamp >= entry.lastVisited {
                        entry.lastVisited = visit.timestamp
                        if !visit.title.isEmpty { entry.title = visit.title }
                        entry.tabId = visit.tabId
                    }
                    if entry.profileId == nil, visit.profileId != nil {
                        entry.profileId = visit.profileId
                        // The row leaves every other profile's `visible(to:)` here, so an index
                        // built for one of those is still counting a row it can no longer see.
                        autofillCache = nil
                    }
                } else {
                    modelContext.insert(HistoryEntity(url: url, title: visit.title.isEmpty ? (visit.url.host ?? "Unknown") : visit.title,
                        visitDate: visit.timestamp, tabId: visit.tabId, lastVisited: visit.timestamp, profileId: visit.profileId))
                }
                autofillCache?.record(url: url, profile: visit.profileId, at: visit.timestamp)
                // Bound each transaction while avoiding a disk save for every imported row.
                if (index + 1).isMultiple(of: 500) { try modelContext.save() }
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            autofillCache = nil
            Self.logger.error("History write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func history(days: Int, profile: UUID?, offset: Int, limit: Int) -> (entries: [HistoryEntry], hasMore: Bool) {
        guard offset >= 0, limit > 0 else { return ([], false) }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate: Predicate<HistoryEntity>
        if let profile {
            predicate = #Predicate { $0.lastVisited >= cutoff && ($0.profileId == profile || $0.profileId == nil) }
        } else {
            predicate = #Predicate { $0.lastVisited >= cutoff }
        }
        var descriptor = FetchDescriptor<HistoryEntity>(predicate: predicate, sortBy: [SortDescriptor(\.lastVisited, order: .reverse)])
        descriptor.fetchOffset = offset
        descriptor.fetchLimit = limit + 1
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return (entries.prefix(limit).map(HistoryEntry.init), entries.count > limit)
    }

    func search(query: String, profile: UUID?, offset: Int, limit: Int) -> (entries: [HistoryEntry], hasMore: Bool) {
        if query.isEmpty { return history(days: 7, profile: profile, offset: offset, limit: limit) }
        let interval = BrowserPerformance.signposter.beginInterval("HistorySearch")
        defer { BrowserPerformance.signposter.endInterval("HistorySearch", interval) }
        guard offset >= 0, limit > 0 else { return ([], false) }
        // Keep Foundation's localized matching semantics. Scan bounded chunks off-main,
        // stopping once this page plus its lookahead is satisfied.
        let start = offset
        let pageSize = limit
        var matches: [HistoryEntry] = []
        var descriptor = FetchDescriptor<HistoryEntity>(predicate: visible(to: profile), sortBy: [SortDescriptor(\.lastVisited, order: .reverse)])
        descriptor.fetchLimit = 128
        do {
            for offset in stride(from: 0, to: 5000, by: 128) {
                guard !Task.isCancelled else { return ([], false) }
                descriptor.fetchOffset = offset
                descriptor.fetchLimit = min(128, 5000 - offset)
                let entries = try modelContext.fetch(descriptor)
                for entry in entries where entry.title.localizedCaseInsensitiveContains(query) || entry.url.localizedCaseInsensitiveContains(query) {
                    matches.append(HistoryEntry(from: entry))
                    if matches.count > start + pageSize {
                        return (Array(matches.dropFirst(start).prefix(pageSize)), true)
                    }
                }
                if entries.count < descriptor.fetchLimit! { break }
            }
        } catch { Self.logger.error("History search failed: \(error.localizedDescription, privacy: .public)") }
        return (Array(matches.dropFirst(start).prefix(pageSize)), false)
    }

    /// Highest-ranked host whose name, minus `www.`, starts with `prefix`. Ranked by total visits
    /// across the whole host, then recency, so a popular origin beats a deep page visited once.
    /// Reads the cached index, so a keystroke costs a prefix scan over hosts rather than a fetch.
    func autofillHost(prefix: String, profile: UUID?, minVisits: Int) -> String? {
        guard AutofillRanking.isUsable(prefix: prefix) else { return nil }
        return AutofillRanking.bestHost(in: autofillIndex(for: profile), prefix: prefix, minVisits: minVisits)
    }

    /// Host index for `profile`, built on first use. `addVisits` folds new visits in rather than
    /// dropping it, and the age check bounds how long a delete made elsewhere can leave it wrong.
    private func autofillIndex(for profile: UUID?) -> [String: HostStat] {
        if let cache = autofillCache, cache.profile == profile,
           Date().timeIntervalSince(cache.built) < Self.indexMaxAge {
            return cache.hosts
        }
        let interval = BrowserPerformance.signposter.beginInterval("HistoryAutofillIndex")
        defer { BrowserPerformance.signposter.endInterval("HistoryAutofillIndex", interval) }
        // ponytail: one fetch of the 10k most-visited rows; page it if a history that size shows up.
        var descriptor = FetchDescriptor<HistoryEntity>(
            predicate: visible(to: profile),
            sortBy: [SortDescriptor(\.visitCount, order: .reverse), SortDescriptor(\.lastVisited, order: .reverse)]
        )
        descriptor.fetchLimit = 10_000
        let entries: [HistoryEntity]
        do {
            entries = try modelContext.fetch(descriptor)
        } catch {
            // Caching this as an empty index would suppress autofill until it aged out. Offer
            // nothing for this keystroke and let the next one retry the fetch.
            Self.logger.error("Autofill index build failed: \(error.localizedDescription, privacy: .public)")
            return [:]
        }
        let hosts = AutofillRanking.aggregate(entries.map { ($0.url, $0.visitCount, $0.lastVisited) })
        autofillCache = AutofillIndex(profile: profile, built: Date(), hosts: hosts)
        return hosts
    }

    func clear(days: Int, profile: UUID?) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        do {
            if let profile {
                // Same rows `visible(to:)` shows: untagged legacy rows appear in every space,
                // so clearing one space has to take them too.
                try modelContext.delete(model: HistoryEntity.self, where: #Predicate { $0.lastVisited < cutoff && ($0.profileId == profile || $0.profileId == nil) })
            } else {
                try modelContext.delete(model: HistoryEntity.self, where: #Predicate { $0.lastVisited < cutoff })
            }
            try modelContext.save()
            autofillCache = nil
        } catch { Self.logger.error("History clear failed: \(error.localizedDescription, privacy: .public)") }
    }

    func delete(_ id: UUID) {
        do {
            try modelContext.delete(model: HistoryEntity.self, where: #Predicate { $0.id == id })
            try modelContext.save()
            autofillCache = nil
        } catch { Self.logger.error("History deletion failed: \(error.localizedDescription, privacy: .public)") }
    }
}

// MARK: - HistoryEntry Model

public struct HistoryEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let url: URL
    public let title: String
    public let visitDate: Date
    public let tabId: UUID?
    public let visitCount: Int
    public let lastVisited: Date

    public init(from entity: HistoryEntity) {
        self.id = entity.id
        self.url = URL(string: entity.url) ?? URL(string: "https://www.google.com")!
        self.title = entity.title
        self.visitDate = entity.visitDate
        self.tabId = entity.tabId
        self.visitCount = entity.visitCount
        self.lastVisited = entity.lastVisited
    }
    
    public var displayTitle: String {
        return title.isEmpty ? (url.host ?? "Unknown") : title
    }
    
    public var displayURL: String {
        return url.absoluteString
    }
}
