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
    
    struct SearchSuggestion: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let type: SuggestionType
        
        enum SuggestionType {
            case search
            case url
        }
        
        static func == (lhs: SearchSuggestion, rhs: SearchSuggestion) -> Bool {
            return lhs.text == rhs.text && lhs.type == rhs.type
        }
    }
    
    func searchSuggestions(for query: String) {
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
        
        if isLikelyURL(query) {
            let urlSuggestion = [SearchSuggestion(text: query, type: .url)]
            updateSuggestionsIfNeeded(urlSuggestion)
            return
        }
        
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
                    
                    let newSuggestions = suggestionsArray.prefix(5).map { suggestion in
                        SearchSuggestion(
                            text: suggestion,
                            type: isLikelyURL(suggestion) == true ? .url : .search
                        )
                    }
                    
                    self?.updateSuggestionsIfNeeded(Array(newSuggestions))
                    
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
