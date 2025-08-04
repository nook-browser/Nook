//
//  SearchManager.swift
//  Alto
//
//  Created by Maciek Bagiński on 31/07/2025.
//

import Foundation
import Observation
import SwiftUI

@Observable
class SearchManager {
    var suggestions: [SearchSuggestion] = []
    var isLoading: Bool = false
    
    private let session = URLSession.shared
    private var searchTask: URLSessionDataTask?
    private weak var tabManager: TabManager?
    
    struct SearchSuggestion: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let type: SuggestionType
        
        enum SuggestionType {
            case search
            case url
            case tab(Tab)
        }
        
        static func == (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool {
            switch (lhs.type, rhs.type) {
            case (.search, .search), (.url, .url):
                return lhs.text == rhs.text
            case (.tab(let lhsTab), .tab(let rhsTab)):
                return lhs.text == rhs.text && lhsTab.id == rhsTab.id
            default:
                return false
            }
        }
    }
    
    func setTabManager(_ tabManager: TabManager?) {
        self.tabManager = tabManager
    }
    
    @MainActor func searchSuggestions(for query: String) {
        // Cancel previous request
        searchTask?.cancel()
        
        // Clear suggestions if query is empty
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            if !suggestions.isEmpty {
                withAnimation(.easeInOut(duration: 0.2)) {
                    suggestions = []
                }
            }
            return
        }
        
        // Search tabs first
        let tabSuggestions = searchTabs(for: query)
        
        // If we have tab matches, prioritize them
        if !tabSuggestions.isEmpty {
            let allSuggestions = tabSuggestions + (isLikelyURL(query) ? [SearchSuggestion(text: query, type: .url)] : [])
            updateSuggestionsIfNeeded(allSuggestions)
            
            // Still fetch web suggestions but combine them
            fetchWebSuggestions(for: query, prependTabSuggestions: tabSuggestions)
            return
        }
        
        if isLikelyURL(query) {
            let urlSuggestion = [SearchSuggestion(text: query, type: .url)]
            updateSuggestionsIfNeeded(urlSuggestion)
            fetchWebSuggestions(for: query, prependTabSuggestions: [])
            return
        }
        
        // Fetch web suggestions
        fetchWebSuggestions(for: query, prependTabSuggestions: [])
    }
    
    @MainActor private func searchTabs(for query: String) -> [SearchSuggestion] {
        guard let tabManager = tabManager else { return [] }
        
        let lowercaseQuery = query.lowercased()
        var matchingTabs: [SearchSuggestion] = []
        
        // Access tabs directly using proper types
        let allTabs = tabManager.pinnedTabs + tabManager.tabs
        
        for tab in allTabs {
            let nameMatch = tab.name.lowercased().contains(lowercaseQuery)
            let urlMatch = tab.url.absoluteString.lowercased().contains(lowercaseQuery)
            let hostMatch = tab.url.host?.lowercased().contains(lowercaseQuery) ?? false
            
            if nameMatch || urlMatch || hostMatch {
                let suggestion = SearchSuggestion(
                    text: tab.name,
                    type: .tab(tab)
                )
                matchingTabs.append(suggestion)
            }
        }
        
        // Sort by relevance (name matches first, then URL matches)
        let sortedTabs = matchingTabs.sorted { (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool in
            if case .tab(let lhsTab) = lhs.type, case .tab(let rhsTab) = rhs.type {
                let lhsNameMatch = lhsTab.name.lowercased().contains(lowercaseQuery)
                let rhsNameMatch = rhsTab.name.lowercased().contains(lowercaseQuery)
                
                if lhsNameMatch && !rhsNameMatch {
                    return true
                } else if !lhsNameMatch && rhsNameMatch {
                    return false
                } else {
                    return lhsTab.name.count < rhsTab.name.count
                }
            }
            return false
        }
        
        return Array(sortedTabs.prefix(3)) // Limit to 3 tab suggestions
    }
    
    private func fetchWebSuggestions(for query: String, prependTabSuggestions: [SearchSuggestion]) {
        isLoading = true
        
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let urlString = "https://suggestqueries.google.com/complete/search?client=firefox&q=\(encodedQuery)"
        
        guard let url = URL(string: urlString) else {
            isLoading = false
            return
        }
        
        searchTask = session.dataTask(with: url) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.isLoading = false
                
                guard let data = data,
                      error == nil else {
                    print("Search suggestions error: \(error?.localizedDescription ?? "Unknown error")")
                    return
                }
                
                do {
                    guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any],
                          jsonArray.count >= 2,
                          let suggestionsArray = jsonArray[1] as? [String] else {
                        print("Invalid JSON response format")
                        return
                    }
                    
                    let webSuggestions = suggestionsArray.prefix(5).map { suggestion in
                        SearchSuggestion(
                            text: suggestion,
                            type: isLikelyURL(suggestion) == true ? .url : .search
                        )
                    }
                    
                    // Combine tab suggestions with web suggestions
                    let combinedSuggestions = prependTabSuggestions + Array(webSuggestions)
                    self?.updateSuggestionsIfNeeded(combinedSuggestions)
                    
                } catch {
                    print("JSON parsing error: \(error.localizedDescription)")
                }
            }
        }
        
        searchTask?.resume()
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
        if !suggestions.isEmpty {
            withAnimation(.easeInOut(duration: 0.2)) {
                suggestions = []
            }
        }
        isLoading = false
    }
}
