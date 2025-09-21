//
//  HistoryManager.swift
//  Nook
//
//  Created by Jonathan Caudill on 09/08/2025.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
class HistoryManager {
    private let context: ModelContext
    private let maxHistoryDays: Int = 100
    // Current profile context for filtering and assignment
    var currentProfileId: UUID?

    init(context: ModelContext, profileId: UUID? = nil) {
        self.context = context
        currentProfileId = profileId
        Task {
            await cleanupOldHistory()
        }
    }

    // MARK: - Profile Switching

    func switchProfile(_ profileId: UUID?) {
        currentProfileId = profileId
        print("🔁 [HistoryManager] Switched to profile: \(profileId?.uuidString ?? "nil")")
    }

    // MARK: - Public Methods

    func addVisit(url: URL, title: String, timestamp: Date = Date(), tabId: UUID?, profileId: UUID? = nil) {
        // Skip non-web URLs
        guard url.scheme == "http" || url.scheme == "https" else { return }

        // Skip common non-history URLs
        let skipPatterns = ["about:", "chrome:", "moz-extension:", "safari-extension:"]
        if skipPatterns.contains(where: { url.absoluteString.hasPrefix($0) }) {
            return
        }

        do {
            // Check if we already have this URL
            let urlString = url.absoluteString
            // Prefer a simple fetch filtered in-memory to avoid complex SwiftData predicate issues.
            let existingAll = try context.fetch(FetchDescriptor<HistoryEntity>())
            let existing = existingAll.filter { $0.url == urlString }
            let targetProfileId = profileId ?? currentProfileId

            // Prefer same-profile entry; otherwise, only fallback to a nil-profile entry (do NOT merge across other profiles)
            let existingEntrySameProfile = existing.first(where: { $0.profileId == targetProfileId })
            let existingEntryNilProfile = existing.first(where: { $0.profileId == nil })
            let existingEntry = existingEntrySameProfile ?? existingEntryNilProfile

            if let existingEntry = existingEntry {
                // Update existing entry
                existingEntry.visitCount += 1
                existingEntry.lastVisited = timestamp
                existingEntry.title = title.isEmpty ? existingEntry.title : title
                existingEntry.tabId = tabId
                if existingEntry.profileId == nil {
                    existingEntry.profileId = targetProfileId
                }
            } else {
                // Create new entry
                let newEntry = HistoryEntity(
                    url: urlString,
                    title: title.isEmpty ? (url.host ?? "Unknown") : title,
                    visitDate: timestamp,
                    tabId: tabId,
                    visitCount: 1,
                    lastVisited: timestamp,
                    profileId: targetProfileId
                )
                context.insert(newEntry)
            }

            try context.save()
        } catch {
            print("Error saving history entry: \(error)")
        }
    }

    func getHistory(days: Int = 7) -> [HistoryEntry] {
        return getHistory(days: days, page: 0, pageSize: 1000).entries
    }

    func getHistory(days: Int = 7, page: Int = 0, pageSize: Int = 50) -> (entries: [HistoryEntry], hasMore: Bool) {
        do {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let profileFilter = currentProfileId
            // Fetch by date only; apply profile filtering in-memory for stability
            let basePredicate = #Predicate<HistoryEntity> { e in e.lastVisited >= cutoffDate }
            // First get total count by date
            let countDescriptor = FetchDescriptor<HistoryEntity>(predicate: basePredicate)
            let totalCount = (try? context.fetchCount(countDescriptor)) ?? 0
            // Then get paginated results by date, sorted by recency
            var descriptor = FetchDescriptor<HistoryEntity>(
                predicate: basePredicate,
                sortBy: [SortDescriptor(\.lastVisited, order: .reverse)]
            )
            descriptor.fetchLimit = pageSize
            descriptor.fetchOffset = page * pageSize

            let entities = try context.fetch(descriptor)
            let filteredByProfile: [HistoryEntity]
            if let pf = profileFilter {
                filteredByProfile = entities.filter { $0.profileId == pf || $0.profileId == nil }
            } else {
                filteredByProfile = entities
            }
            let entries = filteredByProfile.map { HistoryEntry(from: $0) }
            let hasMore = (page + 1) * pageSize < totalCount

            return (entries: entries, hasMore: hasMore)
        } catch {
            print("Error fetching paginated history: \(error)")
            return (entries: [], hasMore: false)
        }
    }

    func searchHistory(query: String) -> [HistoryEntry] {
        return searchHistory(query: query, page: 0, pageSize: 1000).entries
    }

    func searchHistory(query: String, page: Int = 0, pageSize: Int = 50) -> (entries: [HistoryEntry], hasMore: Bool) {
        guard !query.isEmpty else { return getHistory(page: page, pageSize: pageSize) }

        do {
            // For search, we need to fetch more than needed and filter in memory
            // This is a limitation of SwiftData's predicate system for complex text searches
            let profileFilter = currentProfileId
            var descriptor = FetchDescriptor<HistoryEntity>(
                sortBy: [SortDescriptor(\.lastVisited, order: .reverse)]
            )
            // Limit memory usage for search - fetch reasonable subset for filtering
            descriptor.fetchLimit = min(5000, maxResults)

            let entities = try context.fetch(descriptor)
            // Apply text filtering and profile filtering
            let filteredEntities = entities.filter { entity in
                entity.title.localizedCaseInsensitiveContains(query) ||
                    entity.url.localizedCaseInsensitiveContains(query)
            }.filter { entity in
                guard let pf = profileFilter else { return true }
                return entity.profileId == pf || entity.profileId == nil
            }

            // Apply pagination to filtered results
            let startIndex = page * pageSize
            let endIndex = min(startIndex + pageSize, filteredEntities.count)

            guard startIndex < filteredEntities.count else {
                return (entries: [], hasMore: false)
            }

            let pageEntries = Array(filteredEntities[startIndex ..< endIndex])
            let hasMore = endIndex < filteredEntities.count

            return (entries: pageEntries.map { HistoryEntry(from: $0) }, hasMore: hasMore)
        } catch {
            print("Error searching history: \(error)")
            return (entries: [], hasMore: false)
        }
    }

    private let maxResults: Int = 10000

    func getMostVisited(limit: Int = 10) -> [HistoryEntry] {
        do {
            let profileFilter = currentProfileId
            var descriptor = FetchDescriptor<HistoryEntity>(
                sortBy: [
                    SortDescriptor(\.visitCount, order: .reverse),
                    SortDescriptor(\.lastVisited, order: .reverse),
                ]
            )
            descriptor.fetchLimit = limit

            let entities = try context.fetch(descriptor).filter { entity in
                guard let pf = profileFilter else { return true }
                return entity.profileId == pf || entity.profileId == nil
            }
            return entities.map { HistoryEntry(from: $0) }
        } catch {
            print("Error fetching most visited: \(error)")
            return []
        }
    }

    func clearHistory(olderThan days: Int = 0, profileId: UUID? = nil) {
        do {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let pf = profileId ?? currentProfileId
            // Fetch by date only; profile filtering in-memory for stability
            let datePredicate = #Predicate<HistoryEntity> { e in e.visitDate < cutoffDate }
            let descriptor = FetchDescriptor<HistoryEntity>(predicate: datePredicate)
            var entitiesToDelete = try context.fetch(descriptor)
            if let p = pf {
                entitiesToDelete = entitiesToDelete.filter { $0.profileId == p }
            }
            for entity in entitiesToDelete {
                context.delete(entity)
            }

            try context.save()
            if let p = pf {
                print("Cleared \(entitiesToDelete.count) history entries older than \(days) days for profile=\(p.uuidString)")
            } else {
                print("Cleared \(entitiesToDelete.count) history entries older than \(days) days (all profiles)")
            }
        } catch {
            print("Error clearing history: \(error)")
        }
    }

    func deleteHistoryEntry(_ entryId: UUID) {
        do {
            let eid = entryId
            let predicate = #Predicate<HistoryEntity> { e in e.id == eid }
            let descriptor = FetchDescriptor<HistoryEntity>(predicate: predicate)

            if let entity = try context.fetch(descriptor).first {
                context.delete(entity)
                try context.save()
            }
        } catch {
            print("Error deleting history entry: \(error)")
        }
    }

    // MARK: - Private Methods

    private func cleanupOldHistory() async {
        clearHistory(olderThan: maxHistoryDays)
    }

    // MARK: - Stats

    func getHistoryStats(for profileId: UUID?) -> (count: Int, uniqueHosts: Int) {
        do {
            let pf = profileId ?? currentProfileId
            let entities = try context.fetch(FetchDescriptor<HistoryEntity>()).filter { entity in
                guard let p = pf else { return true }
                return entity.profileId == p || entity.profileId == nil
            }
            let hosts: Set<String> = Set(entities.compactMap { URL(string: $0.url)?.host })
            return (count: entities.count, uniqueHosts: hosts.count)
        } catch {
            print("Error computing history stats: \(error)")
            return (0, 0)
        }
    }
}

// MARK: - HistoryEntry Model

struct HistoryEntry: Identifiable, Hashable {
    let id: UUID
    let url: URL
    let title: String
    let visitDate: Date
    let tabId: UUID?
    let visitCount: Int
    let lastVisited: Date

    init(from entity: HistoryEntity) {
        id = entity.id
        url = URL(string: entity.url) ?? URL(string: "https://www.google.com")!
        title = entity.title
        visitDate = entity.visitDate
        tabId = entity.tabId
        visitCount = entity.visitCount
        lastVisited = entity.lastVisited
    }

    var displayTitle: String {
        return title.isEmpty ? (url.host ?? "Unknown") : title
    }

    var displayURL: String {
        return url.absoluteString
    }

    var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: lastVisited, relativeTo: Date())
    }
}
