//
//  MiniCommandPaletteView.swift
//  Nook
//
//  A compact command palette anchored to the URL bar.
//

import SwiftUI

//
//  MiniCommandPaletteView.swift
//  Nook
//
//  A compact command palette anchored to the URL bar.
//

import SwiftUI

struct MiniCommandPaletteView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var gradientColorManager: GradientColorManager
    @State private var searchManager = SearchManager()
    @Environment(\.colorScheme) var colorScheme

    @FocusState private var isSearchFocused: Bool
    @State private var text: String = ""
    @State private var selectedSuggestionIndex: Int = -1

    // Will be overridden by overlay to match URL bar width
    var forcedWidth: CGFloat? = nil
    var forcedCornerRadius: CGFloat? = nil

    var body: some View {
        let isDark = colorScheme == .dark

        VStack(spacing: 0) {
            // Input
            HStack(spacing: 10) {
                Image(systemName: isLikelyURL(text) ? "globe" : "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)

                TextField("Search or enter address", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(AppColors.textPrimary)
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
                        searchManager.searchSuggestions(for: newValue)
                    }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)

            // Separator
            if !searchManager.suggestions.isEmpty {
                RoundedRectangle(cornerRadius: 100)
                    .fill(Color.white.opacity(0.35))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }

            // Suggestions
            if !searchManager.suggestions.isEmpty {
                let suggestions = searchManager.suggestions
                LazyVStack(spacing: 2) {
                    ForEach(suggestions.indices, id: \.self) { index in
                        let suggestion = suggestions[index]
                        suggestionRow(for: suggestion, isSelected: selectedSuggestionIndex == index)
                            .padding(6)
                            .background(selectedSuggestionIndex == index ? gradientColorManager.primaryColor : Color.clear)
                            .cornerRadius(8)
                            .font(.system(size: 15, weight: .regular))
                            .foregroundStyle(AppColors.textPrimary)
                            .contentShape(Rectangle())
                            .onHover { hovering in
                                withAnimation(.easeInOut(duration: 0.12)) {
                                    if hovering {
                                        selectedSuggestionIndex = index
                                    } else if selectedSuggestionIndex == index {
                                        selectedSuggestionIndex = -1
                                    }
                                }
                            }
                            .onTapGesture { selectSuggestion(suggestion) }
                    }
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 4)
                .frame(maxHeight: 240)
            }
        }
        .frame(width: forcedWidth ?? 460)
        .background(isDark ? Color.white.opacity(0.28) : Color.white.opacity(0.85))
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: forcedCornerRadius ?? 12))
        .overlay(
            RoundedRectangle(cornerRadius: forcedCornerRadius ?? 12)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 12)
        .onAppear {
            // Wire managers
            searchManager.setTabManager(browserManager.tabManager)
            searchManager.setHistoryManager(browserManager.historyManager)

            // Ensure prefill and focus when the mini palette is presented
            text = browserManager.commandPalettePrefilledText
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: browserManager.isMiniCommandPaletteVisible) { _, newVisible in
            if newVisible {
                // Pre-fill and focus
                text = browserManager.commandPalettePrefilledText
                DispatchQueue.main.async { isSearchFocused = true }
            } else {
                isSearchFocused = false
                searchManager.clearSuggestions()
                text = ""
                selectedSuggestionIndex = -1
            }
        }
        .onKeyPress(.escape) {
            DispatchQueue.main.async { browserManager.isMiniCommandPaletteVisible = false }
            return .handled
        }
        .onChange(of: searchManager.suggestions.count) { _, newCount in
            if newCount == 0 {
                selectedSuggestionIndex = -1
            } else if selectedSuggestionIndex >= newCount {
                selectedSuggestionIndex = -1
            }
        }
    }

    private func handleReturn() {
        if selectedSuggestionIndex >= 0 && selectedSuggestionIndex < searchManager.suggestions.count {
            selectSuggestion(searchManager.suggestions[selectedSuggestionIndex])
        } else {
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
            browserManager.tabManager.setActiveTab(existingTab)
        case .history(let historyEntry):
            if browserManager.shouldNavigateCurrentTab && browserManager.tabManager.currentTab != nil {
                browserManager.tabManager.currentTab?.loadURL(historyEntry.url.absoluteString)
            } else {
                _ = browserManager.tabManager.createNewTab(url: historyEntry.url.absoluteString, in: browserManager.tabManager.currentSpace)
            }
        case .url, .search:
            if browserManager.shouldNavigateCurrentTab && browserManager.tabManager.currentTab != nil {
                browserManager.tabManager.currentTab?.navigateToURL(suggestion.text)
            } else {
                _ = browserManager.tabManager.createNewTab(url: suggestion.text, in: browserManager.tabManager.currentSpace)
            }
        }

        text = ""
        selectedSuggestionIndex = -1
        browserManager.isMiniCommandPaletteVisible = false
    }

    private func navigateSuggestions(direction: Int) {
        let maxIndex = searchManager.suggestions.count - 1
        if direction > 0 {
            selectedSuggestionIndex = min(selectedSuggestionIndex + 1, maxIndex)
        } else {
            selectedSuggestionIndex = max(selectedSuggestionIndex - 1, -1)
        }
    }

    @ViewBuilder
    private func suggestionRow(for suggestion: SearchManager.SearchSuggestion, isSelected: Bool) -> some View {
        switch suggestion.type {
        case .tab(let tab):
            TabSuggestionItem(tab: tab, isSelected: isSelected)
                .foregroundStyle(AppColors.textPrimary)
        case .history(let entry):
            HistorySuggestionItem(entry: entry, isSelected: isSelected)
                .foregroundStyle(AppColors.textPrimary)
        case .url:
            GenericSuggestionItem(icon: Image(systemName: "link"), text: suggestion.text, isSelected: isSelected)
                .foregroundStyle(AppColors.textPrimary)
        case .search:
            GenericSuggestionItem(icon: Image(systemName: "magnifyingglass"), text: suggestion.text, isSelected: isSelected)
                .foregroundStyle(AppColors.textPrimary)
        }
    }
}
