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
                        // Search input
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
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)

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
                                        favicon: Image(
                                            systemName: suggestion.type == .url
                                                ? "link" : "magnifyingglass"
                                        ),
                                        text: suggestion.text,
                                        isSelected: selectedSuggestionIndex
                                            == index
                                    )
                                    .onTapGesture {
                                        selectSuggestion(suggestion.text)
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
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            } else {
                isSearchFocused = false
                searchManager.clearSuggestions()
                selectedSuggestionIndex = -1
            }
            if let url = browserManager.tabManager.currentTab?.url {
                //decide if tab is being opened as new, or just entering new url into current page???
                print("url: \(url)")
                text = url.absoluteString
            }
        }
        .onKeyPress(.escape) {
            DispatchQueue.main.async {
                browserManager.closeCommandPalette()
            }
            return .handled
        }
        // Only animate selection changes
        .animation(.easeInOut(duration: 0.15), value: selectedSuggestionIndex)
    }

    private func handleReturn() {
        let finalText: String

        if selectedSuggestionIndex >= 0
            && selectedSuggestionIndex < searchManager.suggestions.count
        {
            finalText = searchManager.suggestions[selectedSuggestionIndex].text
        } else {
            finalText = text
        }

        selectSuggestion(finalText)
    }

    private func selectSuggestion(_ suggestionText: String) {
        browserManager.tabManager.createNewTab(url: suggestionText)
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
}
