//
//  CommandPaletteView.swift
//  Alto
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var searchManager = SearchManager()

    @FocusState private var isSearchFocused: Bool
    @State private var text: String = ""
    @State private var selectedSuggestionIndex: Int = -1

    var body: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    browserManager.closeCommandPalette()
                }
                .gesture(WindowDragGesture())

            VStack(alignment: .center) {
                HStack(spacing: 0) {
                    Spacer()

                    VStack(spacing: 0) {
                        HStack(spacing: 12) {
                            Image(
                                systemName: isLikelyURL(text)
                                    ? "globe" : "magnifyingglass"
                            )
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12, weight: .medium))

                            TextField("Search or enter address", text: $text)
                                .textFieldStyle(.plain)
                                .font(.system(size: 16, weight: .regular))
                                .focused($isSearchFocused)
                                .onKeyPress(.return) {
                                    handleReturn()
                                    return .handled
                                }
                                .onKeyPress(.upArrow) {
                                    navigateSuggestions(direction: -1)
                                    return .handled
                                }
                                .onKeyPress(.downArrow) {
                                    navigateSuggestions(direction: 1)
                                    return .handled
                                }
                                .onChange(of: text) { _, newValue in
                                    selectedSuggestionIndex = -1
                                    searchManager.searchSuggestions(
                                        for: newValue
                                    )
                                }
                        }
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)

                        // Separator
                        if !searchManager.suggestions.isEmpty {
                            RoundedRectangle(cornerRadius: 100)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 8)
                        }

                        // Suggestions
                        if !searchManager.suggestions.isEmpty {
                            LazyVStack(spacing: 2) {
                                ForEach(
                                    Array(
                                        searchManager.suggestions.enumerated()
                                    ),
                                    id: \.element.id
                                ) { index, suggestion in
                                    CommandPaletteSuggestionView(
                                        favicon: iconForSuggestion(suggestion),
                                        text: suggestion.text,
                                        isTabSuggestion: isTabSuggestion(suggestion),
                                        isSelected: selectedSuggestionIndex
                                            == index
                                    )
                                    .onTapGesture {
                                        selectSuggestion(suggestion)
                                    }
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(width: 500)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.white.opacity(0.1), lineWidth: 1)
                    )

                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(browserManager.isCommandPaletteVisible)
        .opacity(browserManager.isCommandPaletteVisible ? 1.0 : 0.0)
        .onChange(of: browserManager.isCommandPaletteVisible) { _, newVisible in
            if newVisible {
                // Set the tab manager when command palette opens
                searchManager.setTabManager(browserManager.tabManager)
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            } else {
                isSearchFocused = false
                searchManager.clearSuggestions()
                text = ""
                selectedSuggestionIndex = -1
            }
        }
        .onKeyPress(.escape) {
            DispatchQueue.main.async {
                browserManager.closeCommandPalette()
            }
            return .handled
        }
        .animation(.easeInOut(duration: 0.15), value: selectedSuggestionIndex)
    }

    private func handleReturn() {
        if selectedSuggestionIndex >= 0
            && selectedSuggestionIndex < searchManager.suggestions.count
        {
            let suggestion = searchManager.suggestions[selectedSuggestionIndex]
            selectSuggestion(suggestion)
        } else {
            // Create new suggestion from text input
            let newSuggestion = SearchManager.SearchSuggestion(
                text: text,
                type: isLikelyURL(text) ? .url : .search
            )
            selectSuggestion(newSuggestion)
        }
    }

    private func selectSuggestion(_ suggestion: SearchManager.SearchSuggestion) {
        switch suggestion.type {
        case .tab(let existingTab):
            // Switch to existing tab
            browserManager.tabManager.setActiveTab(existingTab)
            print("Switched to existing tab: \(existingTab.name)")
        case .url, .search:
            // Create new tab
            let tab = browserManager.tabManager.createNewTab(url: suggestion.text, in: browserManager.tabManager.currentSpace)
            print("Created tab \(tab.name) in \(String(describing: browserManager.tabManager.currentSpace?.name))")
        }
        
        text = ""
        selectedSuggestionIndex = -1
        browserManager.closeCommandPalette()
    }

    private func navigateSuggestions(direction: Int) {
        let maxIndex = searchManager.suggestions.count - 1

        if direction > 0 {
            // Down arrow
            selectedSuggestionIndex = min(selectedSuggestionIndex + 1, maxIndex)
        } else {
            // Up arrow
            selectedSuggestionIndex = max(selectedSuggestionIndex - 1, -1)
        }
    }
    
    private func iconForSuggestion(_ suggestion: SearchManager.SearchSuggestion) -> Image {
        switch suggestion.type {
        case .tab(let tab):
            return tab.favicon
        case .url:
            return Image(systemName: "link")
        case .search:
            return Image(systemName: "magnifyingglass")
        }
    }
    
    private func isTabSuggestion(_ suggestion: SearchManager.SearchSuggestion) -> Bool {
        switch suggestion.type {
        case .tab:
            return true
        case .search, .url:
            return false
        }
    }
}
