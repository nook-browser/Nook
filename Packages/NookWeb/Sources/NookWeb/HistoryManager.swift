// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
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

    public init(context: ModelContext, profileId: UUID? = nil) {
        currentProfileId = profileId
        let container = context.container
        // Construct the model executor off the main actor as well as calling it there.
        storeTask = Task.detached { HistoryStore(modelContainer: container) }
        clearHistory(olderThan: 100)
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

    public func getHistory(days: Int = 7) async -> [HistoryEntry] {
        await getHistory(days: days, page: 0, pageSize: 1000).entries
    }

    public func getHistory(days: Int = 7, page: Int = 0, pageSize: Int = 50) async -> (entries: [HistoryEntry], hasMore: Bool) {
        let profile = currentProfileId
        await pendingWrite?.value
        return await storeTask.value.history(days: days, profile: profile, page: page, pageSize: pageSize)
    }

    public func searchHistory(query: String) async -> [HistoryEntry] {
        await searchHistory(query: query, page: 0, pageSize: 1000).entries
    }

    public func searchHistory(query: String, page: Int = 0, pageSize: Int = 50) async -> (entries: [HistoryEntry], hasMore: Bool) {
        let profile = currentProfileId
        await pendingWrite?.value
        guard !Task.isCancelled else { return ([], false) }
        return await storeTask.value.search(query: query, profile: profile, page: page, pageSize: pageSize)
    }

    /// Bare host for omnibox inline autofill, e.g. `facebo` -> `facebook.com`. Nil when nothing qualifies.
    /// Skips the pending-write await the other reads take: a keystroke-rate query wants speed, and a
    /// host that is one visit stale autofills the same either way.
    public func autofillHost(prefix: String, minVisits: Int = 2) async -> String? {
        let profile = currentProfileId
        guard !Task.isCancelled else { return nil }
        return await storeTask.value.autofillHost(prefix: prefix, profile: profile, minVisits: minVisits)
    }

    public func getMostVisited(limit: Int = 10) async -> [HistoryEntry] {
        let profile = currentProfileId
        await pendingWrite?.value
        return await storeTask.value.mostVisited(profile: profile, limit: limit)
    }

    public func clearHistory(olderThan days: Int = 0, profileId: UUID? = nil) {
        let profile = profileId ?? currentProfileId
        enqueue { await $0.clear(days: days, profile: profile) }
    }

    public func deleteHistoryEntry(_ entryId: UUID) {
        enqueue { await $0.delete(entryId) }
    }

    public func getHistoryStats(for profileId: UUID?) async -> (count: Int, uniqueHosts: Int) {
        let profile = profileId ?? currentProfileId
        await pendingWrite?.value
        return await storeTask.value.stats(profile: profile)
    }
}

@ModelActor
actor HistoryStore {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "History")

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
                    if entry.profileId == nil { entry.profileId = visit.profileId }
                } else {
                    modelContext.insert(HistoryEntity(url: url, title: visit.title.isEmpty ? (visit.url.host ?? "Unknown") : visit.title,
                        visitDate: visit.timestamp, tabId: visit.tabId, lastVisited: visit.timestamp, profileId: visit.profileId))
                }
                // Bound each transaction while avoiding a disk save for every imported row.
                if (index + 1).isMultiple(of: 500) { try modelContext.save() }
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            Self.logger.error("History write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func history(days: Int, profile: UUID?, page: Int, pageSize: Int) -> (entries: [HistoryEntry], hasMore: Bool) {
        guard page >= 0, pageSize > 0 else { return ([], false) }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        let predicate: Predicate<HistoryEntity>
        if let profile {
            predicate = #Predicate { $0.lastVisited >= cutoff && ($0.profileId == profile || $0.profileId == nil) }
        } else {
            predicate = #Predicate { $0.lastVisited >= cutoff }
        }
        var descriptor = FetchDescriptor<HistoryEntity>(predicate: predicate, sortBy: [SortDescriptor(\.lastVisited, order: .reverse)])
        descriptor.fetchOffset = page * pageSize
        descriptor.fetchLimit = pageSize + 1
        let entries = (try? modelContext.fetch(descriptor)) ?? []
        return (entries.prefix(pageSize).map(HistoryEntry.init), entries.count > pageSize)
    }

    func search(query: String, profile: UUID?, page: Int, pageSize: Int) -> (entries: [HistoryEntry], hasMore: Bool) {
        if query.isEmpty { return history(days: 7, profile: profile, page: page, pageSize: pageSize) }
        let interval = BrowserPerformance.signposter.beginInterval("HistorySearch")
        defer { BrowserPerformance.signposter.endInterval("HistorySearch", interval) }
        guard page >= 0, pageSize > 0 else { return ([], false) }
        // Keep Foundation's localized matching semantics. Scan bounded chunks off-main,
        // stopping once this page plus its lookahead is satisfied.
        let start = page * pageSize
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
    func autofillHost(prefix: String, profile: UUID?, minVisits: Int) -> String? {
        guard AutofillRanking.isUsable(prefix: prefix) else { return nil }
        let interval = BrowserPerformance.signposter.beginInterval("HistoryAutofill")
        defer { BrowserPerformance.signposter.endInterval("HistoryAutofill", interval) }
        // ponytail: scans the 2000 most-visited rows; build an in-memory host index if this shows in a trace.
        var descriptor = FetchDescriptor<HistoryEntity>(
            predicate: visible(to: profile),
            sortBy: [SortDescriptor(\.visitCount, order: .reverse), SortDescriptor(\.lastVisited, order: .reverse)]
        )
        descriptor.fetchLimit = 2000
        guard !Task.isCancelled, let entries = try? modelContext.fetch(descriptor) else { return nil }
        return AutofillRanking.bestHost(
            in: entries.map { ($0.url, $0.visitCount, $0.lastVisited) },
            prefix: prefix,
            minVisits: minVisits
        )
    }

    func mostVisited(profile: UUID?, limit: Int) -> [HistoryEntry] {
        guard limit > 0 else { return [] }
        var descriptor = FetchDescriptor<HistoryEntity>(predicate: visible(to: profile), sortBy: [SortDescriptor(\.visitCount, order: .reverse), SortDescriptor(\.lastVisited, order: .reverse)])
        descriptor.fetchLimit = limit
        return ((try? modelContext.fetch(descriptor)) ?? []).map(HistoryEntry.init)
    }

    func clear(days: Int, profile: UUID?) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        do {
            if let profile {
                try modelContext.delete(model: HistoryEntity.self, where: #Predicate { $0.lastVisited < cutoff && $0.profileId == profile })
            } else {
                try modelContext.delete(model: HistoryEntity.self, where: #Predicate { $0.lastVisited < cutoff })
            }
            try modelContext.save()
        } catch { Self.logger.error("History clear failed: \(error.localizedDescription, privacy: .public)") }
    }

    func delete(_ id: UUID) {
        do {
            try modelContext.delete(model: HistoryEntity.self, where: #Predicate { $0.id == id })
            try modelContext.save()
        } catch { Self.logger.error("History deletion failed: \(error.localizedDescription, privacy: .public)") }
    }

    func stats(profile: UUID?) -> (count: Int, uniqueHosts: Int) {
        let entries = (try? modelContext.fetch(FetchDescriptor<HistoryEntity>(predicate: visible(to: profile)))) ?? []
        return (entries.count, Set(entries.compactMap { URL(string: $0.url)?.host }).count)
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
    
    public var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: lastVisited, relativeTo: Date())
    }
}
