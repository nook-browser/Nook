//
//  SearchManager.swift
//  Alto
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
class SearchManager {
    var suggestions: [SearchSuggestion] = []
    var isLoading: Bool = false
    
    private let session = URLSession.shared
    private var searchTask: Task<Void, Never>?
    private var searchGeneration = UUID()
    private weak var tabs: TabsController?
    private weak var window: BrowserWindowState?
    private weak var historyManager: HistoryManager?
    private var currentSpaceId: UUID?
    
    /// An open tab the palette can switch to, captured when the query ran.
    struct TabMatch {
        let itemID: UUID
        let title: String
        let url: URL
        let favicon: SwiftUI.Image
    }

    struct SearchSuggestion: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let type: SuggestionType
        
        enum SuggestionType {
            case search
            case url
            case tab(TabMatch)
            case history(HistoryEntry)
        }
        
        static func == (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool {
            switch (lhs.type, rhs.type) {
            case (.search, .search), (.url, .url):
                return lhs.text == rhs.text
            case (.tab(let lhsTab), .tab(let rhsTab)):
                return lhs.text == rhs.text && lhsTab.itemID == rhsTab.itemID
            case (.history(let lhsHistory), .history(let rhsHistory)):
                return lhs.text == rhs.text && lhsHistory.id == rhsHistory.id
            default:
                return false
            }
        }
    }
    
    /// The controller and window whose space's tabs the palette searches.
    func setTabs(_ tabs: TabsController?, window: BrowserWindowState?) {
        self.tabs = tabs
        self.window = window
        updateSpaceContext()
    }
    
    func setHistoryManager(_ historyManager: HistoryManager?) {
        self.historyManager = historyManager
    }

    @MainActor func updateSpaceContext() {
        currentSpaceId = window?.spaceID
    }
    
    @MainActor func searchSuggestions(for query: String) {
        searchTask?.cancel()
        let generation = UUID()
        searchGeneration = generation
        isLoading = false
        updateSpaceContext()
        let space = currentSpaceId
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            updateSuggestionsIfNeeded([])
            return
        }

        let tabs = Array(searchTabs(for: query).prefix(2))
        let urlSuggestion: SearchSuggestion? = isLikelyURL(query)
            ? SearchSuggestion(text: query, type: .url) : nil
        let urlRows = urlSuggestion.map { [$0] } ?? []
        // Keep the previous query's web and history rows until fresh ones arrive, so the
        // list updates in place instead of collapsing and re-expanding on every keystroke.
        let carriedWeb = suggestions.filter { if case .search = $0.type { true } else { false } }
        let carriedHistory = suggestions.filter { if case .history = $0.type { true } else { false } }
        updateSuggestionsIfNeeded(Array((urlRows + carriedWeb + carriedHistory + tabs).prefix(5)))
        isLoading = true
        searchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(125)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            async let web = self.fetchWebSuggestions(for: query)
            let history = Array(await self.searchHistory(for: query).prefix(2))
            guard !Task.isCancelled, self.searchGeneration == generation,
                  self.window?.spaceID == space else { return }
            self.updateSuggestionsIfNeeded(Array((urlRows + carriedWeb + history + tabs).prefix(5)))
            let webSuggestions = await web
            guard !Task.isCancelled, self.searchGeneration == generation,
                  self.window?.spaceID == space else { return }
            self.updateSuggestionsIfNeeded(Array((urlRows + webSuggestions + history + tabs).prefix(5)))
            self.isLoading = false
        }
    }

    @MainActor private func searchTabs(for query: String) -> [SearchSuggestion] {
        guard let tabs, let spaceID = window?.spaceID else { return [] }
        let lowercaseQuery = query.lowercased()
        let matches: [TabMatch] = tabs.items(inSpace: spaceID).compactMap { item in
            let session = tabs.session(for: item.id)
            guard let url = session?.url ?? tabs.device.openPages[item.id]?.url ?? item.url else { return nil }
            let title = item.customTitle.flatMap { $0.isEmpty ? nil : $0 } ?? session?.title ?? item.displayTitle
            guard title.lowercased().contains(lowercaseQuery)
                    || url.absoluteString.lowercased().contains(lowercaseQuery) else { return nil }
            let favicon = session?.favicon
                ?? url.host.flatMap { FaviconCache.shared.swiftUIImage(for: $0) }
                ?? SwiftUI.Image(systemName: "globe")
            return TabMatch(itemID: item.id, title: title, url: url, favicon: favicon)
        }
        // Title matches first, then shorter titles.
        let sorted = matches.sorted { lhs, rhs in
            let lhsTitle = lhs.title.lowercased().contains(lowercaseQuery)
            let rhsTitle = rhs.title.lowercased().contains(lowercaseQuery)
            if lhsTitle != rhsTitle { return lhsTitle }
            return lhs.title.count < rhs.title.count
        }
        return sorted.prefix(3).map { SearchSuggestion(text: $0.title, type: .tab($0)) }
    }

    @MainActor private func searchHistory(for query: String) async -> [SearchSuggestion] {
        guard let historyManager = historyManager else { return [] }
        
        let lowercaseQuery = query.lowercased()
        let historyEntries = await historyManager.searchHistory(query: query, page: 0, pageSize: 20)
        
        let matchingHistory = historyEntries.entries.map {
            SearchSuggestion(text: $0.displayTitle, type: .history($0))
        }

        // Sort by relevance (title matches first, then URL matches, then by visit count and recency)
        let sortedHistory = matchingHistory.sorted { (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool in
            if case .history(let lhsHistory) = lhs.type, case .history(let rhsHistory) = rhs.type {
                let lhsTitleMatch = lhsHistory.title.lowercased().contains(lowercaseQuery)
                let rhsTitleMatch = rhsHistory.title.lowercased().contains(lowercaseQuery)
                
                // First prioritize title matches
                if lhsTitleMatch && !rhsTitleMatch {
                    return true
                } else if !lhsTitleMatch && rhsTitleMatch {
                    return false
                } else {
                    // Then prioritize by visit count and recency
                    if lhsHistory.visitCount != rhsHistory.visitCount {
                        return lhsHistory.visitCount > rhsHistory.visitCount
                    } else {
                        return lhsHistory.lastVisited > rhsHistory.lastVisited
                    }
                }
            }
            return false
        }
        
        return sortedHistory
    }
    
    private func fetchWebSuggestions(for query: String) async -> [SearchSuggestion] {
        var components = URLComponents(string: "https://suggestqueries.google.com/complete/search")!
        components.queryItems = [URLQueryItem(name: "client", value: "firefox"), URLQueryItem(name: "q", value: query)]
        guard let url = components.url else { return [] }
        do {
            let (data, _) = try await session.data(from: url)
            try Task.checkCancellation()
            guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any],
                  jsonArray.count >= 2, let strings = jsonArray[1] as? [String] else { return [] }
            return strings.prefix(5).map {
                SearchSuggestion(text: $0, type: isLikelyURL($0) ? .url : .search)
            }
        } catch { return [] }
    }

    private func updateSuggestionsIfNeeded(_ newSuggestions: [SearchSuggestion]) {
        let shouldAnimate = shouldAnimateChange(from: suggestions, to: newSuggestions)
        
        if shouldAnimate {
            withAnimation(.easeInOut(duration: 0.25)) {
                suggestions = newSuggestions
            }
        } else {
            suggestions = newSuggestions
        }
    }
    
    private func shouldAnimateChange(from oldSuggestions: [SearchSuggestion], to newSuggestions: [SearchSuggestion]) -> Bool {
        if oldSuggestions.isEmpty != newSuggestions.isEmpty {
            return true
        }
        
        // Always animate if count changes significantly
        if abs(oldSuggestions.count - newSuggestions.count) > 2 {
            return true
        }
        
        // Compare suggestion texts to see if there are significant changes
        let oldTexts = Set(oldSuggestions.map { $0.text })
        let newTexts = Set(newSuggestions.map { $0.text })
        
        // Calculate how many suggestions are different
        let intersection = oldTexts.intersection(newTexts)
        let totalUnique = oldTexts.union(newTexts).count
        let similarityRatio = Double(intersection.count) / Double(max(totalUnique, 1))
        
        // Only animate if less than 60% of suggestions are the same
        return similarityRatio < 0.6
    }
    
    
    func clearSuggestions() {
        searchTask?.cancel()
        searchGeneration = UUID()
        if !suggestions.isEmpty {
            withAnimation(.easeInOut(duration: 0.2)) {
                suggestions = []
            }
        }
        isLoading = false
    }
}
