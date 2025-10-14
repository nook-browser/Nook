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
    @Environment(BrowserManager.self) private var browserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.nookTheme) private var gradientColorManager
    @Environment(\.nookCommandPalette) private var commandPalette
    @State private var searchManager = SearchManager()
    @Environment(\.colorScheme) var colorScheme

    @FocusState private var isSearchFocused: Bool
    @State private var text: String = ""
    @State private var selectedSuggestionIndex: Int = -1
    @State private var hoveredSuggestionIndex: Int? = nil

    // Will be overridden by overlay to match URL bar width
    var forcedWidth: CGFloat? = nil
    var forcedCornerRadius: CGFloat? = nil

    var body: some View {
        let isDark = colorScheme == .dark
        let symbolName = isLikelyURL(text) ? "globe" : "magnifyingglass"
        let isActiveWindow = browserManager.isActive(windowState)
        let suggestions = searchManager.suggestions

        VStack(spacing: 6) {
            inputRow(symbolName: symbolName)
            separatorIfNeeded(hasSuggestions: !suggestions.isEmpty)
            suggestionsListView(suggestions: suggestions)
        }
        .padding(10)
        .frame(width: forcedWidth ?? 460)
        .background(.thickMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    Color.white.opacity(isDark ? 0.3 : 0.6),
                    lineWidth: 0.5
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 50, x: 0, y: 4)
        .onAppear {
            // Wire managers
            searchManager.setTabManager(browserManager.tabManager)
            searchManager.setHistoryManager(browserManager.historyManager)
            searchManager.updateProfileContext()

            // Ensure prefill and focus when the mini palette is presented
            text = windowState.commandPalettePrefilledText
            DispatchQueue.main.async { isSearchFocused = true }
        }
        .onChange(of: windowState.isMiniCommandPaletteVisible) { _, newVisible in
            if newVisible && isActiveWindow {
                searchManager.setTabManager(browserManager.tabManager)
                searchManager.setHistoryManager(browserManager.historyManager)
                searchManager.updateProfileContext()
                // Pre-fill and focus
                text = windowState.commandPalettePrefilledText
                DispatchQueue.main.async { isSearchFocused = true }
            } else {
                isSearchFocused = false
                searchManager.clearSuggestions()
                text = ""
                selectedSuggestionIndex = -1
            }
        }
       .onKeyPress(.escape) {
            DispatchQueue.main.async {
                commandPalette.hideMiniCommandPalette(using: browserManager, windowState: windowState)
            }
            return .handled
        }
        .onChange(of: searchManager.suggestions.count) { _, newCount in
            if newCount == 0 {
                selectedSuggestionIndex = -1
            } else if selectedSuggestionIndex >= newCount {
                selectedSuggestionIndex = -1
            }
        }
        .onChange(of: windowState.commandPalettePrefilledText) { _, newValue in
            if isActiveWindow && windowState.isMiniCommandPaletteVisible {
                text = newValue
            }
        }
        .onChange(of: browserManager.currentProfile?.id) { _, _ in
            if isActiveWindow && windowState.isMiniCommandPaletteVisible {
                searchManager.updateProfileContext()
                searchManager.clearSuggestions()
            }
        }
    }

    private func inputRow(symbolName: String) -> some View {
        HStack(spacing: 15) {
            Image(systemName: symbolName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(colorScheme == .dark ? .white : .black)

            TextField("Search or enter URL...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(
                    text.isEmpty
                    ? colorScheme == .dark
                            ? .white.opacity(0.25)
                            : .black.opacity(0.25)
                    : colorScheme == .dark
                            ? .white.opacity(0.9)
                            : .black.opacity(0.9)

                )
                .tint(gradientColorManager.primaryColor)
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
                    if windowState.commandPalettePrefilledText != newValue {
                        windowState.commandPalettePrefilledText = newValue
                    }
                }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
    }

    @ViewBuilder
    private func separatorIfNeeded(hasSuggestions: Bool) -> some View {
        if hasSuggestions {
            RoundedRectangle(cornerRadius: 100)
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.4)
                        : Color.black.opacity(0.4)
                )
                .frame(height: 0.5)
                .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func suggestionsListView(suggestions: [SearchManager.SearchSuggestion]) -> some View {
        if suggestions.isEmpty {
            EmptyView()
        } else {
            LazyVStack(spacing: 5) {
                ForEach(suggestions.indices, id: \.self) { index in
                    let suggestion = suggestions[index]
                    suggestionRow(for: suggestion, isSelected: selectedSuggestionIndex == index)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 11)
                        .background(
                            selectedSuggestionIndex == index
                                ? gradientColorManager.primaryColor
                                : hoveredSuggestionIndex == index
                            ? colorScheme == .dark
                                        ? .white.opacity(0.05)
                                        : .black.opacity(0.05) : .clear
                        )                        .cornerRadius(8)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentShape(Rectangle())
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.12)) {
                                if hovering {
                                    hoveredSuggestionIndex = index
                                } else {
                                    hoveredSuggestionIndex = nil
                                }
                            }
                        }
                        .onTapGesture { selectSuggestion(suggestion) }
                }
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
            browserManager.selectTab(existingTab, in: windowState)
        case .history(let historyEntry):
            if windowState.shouldNavigateCurrentTab && browserManager.currentTab(for: windowState) != nil {
                browserManager.currentTab(for: windowState)?.loadURL(historyEntry.url.absoluteString)
            } else {
                browserManager.createNewTab(in: windowState)
                browserManager.currentTab(for: windowState)?.loadURL(historyEntry.url.absoluteString)
            }
        case .url, .search:
            if windowState.shouldNavigateCurrentTab && browserManager.currentTab(for: windowState) != nil {
                browserManager.currentTab(for: windowState)?.navigateToURL(suggestion.text)
            } else {
                browserManager.createNewTab(in: windowState)
                browserManager.currentTab(for: windowState)?.navigateToURL(suggestion.text)
            }
        }

        text = ""
        selectedSuggestionIndex = -1
        commandPalette.hideMiniCommandPalette(using: browserManager, windowState: windowState)
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
