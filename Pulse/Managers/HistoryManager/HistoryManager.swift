//
//  HistoryManager.swift
//  Pulse
//
//  Created by Jonathan Caudill on 09/08/2025.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
class HistoryManager {
    private let context: ModelContext
    private let maxHistoryDays: Int = 100
    
    init(context: ModelContext) {
        self.context = context
        Task {
            await cleanupOldHistory()
        }
    }
    
    // MARK: - Public Methods
    
    func addVisit(url: URL, title: String, timestamp: Date = Date(), tabId: UUID?) {
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
            let predicate = #Predicate<HistoryEntity> { $0.url == urlString }
            let existing = try context.fetch(FetchDescriptor<HistoryEntity>(predicate: predicate))
            
            if let existingEntry = existing.first {
                // Update existing entry
                existingEntry.visitCount += 1
                existingEntry.lastVisited = timestamp
                existingEntry.title = title.isEmpty ? existingEntry.title : title
                existingEntry.tabId = tabId
            } else {
                // Create new entry
                let newEntry = HistoryEntity(
                    url: urlString,
                    title: title.isEmpty ? (url.host ?? "Unknown") : title,
                    visitDate: timestamp,
                    tabId: tabId,
                    visitCount: 1,
                    lastVisited: timestamp
                )
                context.insert(newEntry)
            }
            
            try context.save()
        } catch {
            print("Error saving history entry: \(error)")
        }
    }
    
    func getHistory(days: Int = 7) -> [HistoryEntry] {
        do {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let predicate = #Predicate<HistoryEntity> { $0.lastVisited >= cutoffDate }
            let descriptor = FetchDescriptor<HistoryEntity>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.lastVisited, order: .reverse)]
            )
            
            let entities = try context.fetch(descriptor)
            return entities.map { HistoryEntry(from: $0) }
        } catch {
            print("Error fetching history: \(error)")
            return []
        }
    }
    
    func searchHistory(query: String) -> [HistoryEntry] {
        guard !query.isEmpty else { return getHistory() }
        
        do {
            // Fetch all entries and filter in memory since SwiftData predicates have limitations
            let descriptor = FetchDescriptor<HistoryEntity>(
                sortBy: [SortDescriptor(\.lastVisited, order: .reverse)]
            )
            
            let allEntities = try context.fetch(descriptor)
            let filteredEntities = allEntities.filter { entity in
                entity.title.localizedCaseInsensitiveContains(query) ||
                entity.url.localizedCaseInsensitiveContains(query)
            }
            
            return filteredEntities.map { HistoryEntry(from: $0) }
        } catch {
            print("Error searching history: \(error)")
            return []
        }
    }
    
    func getMostVisited(limit: Int = 10) -> [HistoryEntry] {
        do {
            var descriptor = FetchDescriptor<HistoryEntity>(
                sortBy: [
                    SortDescriptor(\.visitCount, order: .reverse),
                    SortDescriptor(\.lastVisited, order: .reverse)
                ]
            )
            descriptor.fetchLimit = limit
            
            let entities = try context.fetch(descriptor)
            return entities.map { HistoryEntry(from: $0) }
        } catch {
            print("Error fetching most visited: \(error)")
            return []
        }
    }
    
    func clearHistory(olderThan days: Int = 0) {
        do {
            let cutoffDate = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            let predicate = #Predicate<HistoryEntity> { $0.visitDate < cutoffDate }
            let descriptor = FetchDescriptor<HistoryEntity>(predicate: predicate)
            
            let entitiesToDelete = try context.fetch(descriptor)
            for entity in entitiesToDelete {
                context.delete(entity)
            }
            
            try context.save()
            print("Cleared \(entitiesToDelete.count) history entries older than \(days) days")
        } catch {
            print("Error clearing history: \(error)")
        }
    }
    
    func deleteHistoryEntry(_ entryId: UUID) {
        do {
            let predicate = #Predicate<HistoryEntity> { $0.id == entryId }
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
        self.id = entity.id
        self.url = URL(string: entity.url) ?? URL(string: "https://www.google.com")!
        self.title = entity.title
        self.visitDate = entity.visitDate
        self.tabId = entity.tabId
        self.visitCount = entity.visitCount
        self.lastVisited = entity.lastVisited
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
