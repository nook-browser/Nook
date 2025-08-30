//
//  CommandPaletteView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

struct CommandPaletteView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var searchManager = SearchManager()
    @Environment(\.colorScheme) var colorScheme

    @FocusState private var isSearchFocused: Bool
    @State private var text: String = ""
    @State private var selectedSuggestionIndex: Int = -1

    var body: some View {
        let isDark = colorScheme == .dark
        
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
                .onTapGesture {
                    browserManager.closeCommandPalette()
                }
                .gesture(WindowDragGesture())

            GeometryReader { geometry in
                HStack {
                    Spacer()
                    
                    // Single box that expands/contracts but stays anchored at top
                    VStack(spacing: 0) {
                        // Input field - fixed at top of box
                        HStack(spacing: 12) {
                            Image(
                                systemName: isLikelyURL(text)
                                    ? "globe" : "magnifyingglass"
                            )
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textPrimary)

                            TextField("Search or enter address", text: $text)
                                .textFieldStyle(.plain)
                                .font(.system(size: 16, weight: .regular))
                                .foregroundColor(AppColors.textPrimary)
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
                        .padding(.vertical, 16)
                        .padding(.horizontal, 13)

                        // Separator
                        if !searchManager.suggestions.isEmpty {
                            RoundedRectangle(cornerRadius: 100)
                                .fill(Color.white.opacity(0.4))
                                .frame(height: 1)
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                        }

                        // Suggestions - expand the box downward
                        if !searchManager.suggestions.isEmpty {
                            LazyVStack(spacing: 2) {
                                ForEach(
                                    Array(
                                        searchManager.suggestions.enumerated()
                                    ),
                                    id: \.element.id
                                ) { index, suggestion in
                                    suggestionRow(for: suggestion, isSelected: selectedSuggestionIndex == index)
                                        .padding(8)
                                        .background(selectedSuggestionIndex == index ? Color.blue.opacity(1.0) : Color.clear)
                                        .cornerRadius(6)
                                        .foregroundStyle(AppColors.textPrimary) // ensure text and images get correct styling
                                        .onTapGesture {
                                            selectSuggestion(suggestion)
                                        }
                                }
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 4)
                        }
                    }
                    .frame(width: 600)
                    .background(isDark ? Color.white.opacity(0.3) : Color.white.opacity(0.8))
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .animation(.easeInOut(duration: 0.15), value: searchManager.suggestions.count)
                    .alignmentGuide(.top) { _ in -geometry.size.height / 2 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    
                    Spacer()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(browserManager.isCommandPaletteVisible)
        .opacity(browserManager.isCommandPaletteVisible ? 1.0 : 0.0)
        .onChange(of: browserManager.isCommandPaletteVisible) { _, newVisible in
            if newVisible {
                searchManager.setTabManager(browserManager.tabManager)
                searchManager.setHistoryManager(browserManager.historyManager)
                
                // Pre-fill text if provided and select all for easy replacement
                text = browserManager.commandPalettePrefilledText
                
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
        case .history(let historyEntry):
            if browserManager.shouldNavigateCurrentTab && browserManager.tabManager.currentTab != nil {
                // Navigate current tab to history URL
                browserManager.tabManager.currentTab?.loadURL(historyEntry.url.absoluteString)
                print("Navigated current tab to history URL: \(historyEntry.url)")
            } else {
                // Create new tab from history entry
                let tab = browserManager.tabManager.createNewTab(url: historyEntry.url.absoluteString, in: browserManager.tabManager.currentSpace)
                print("Created tab \(tab.name) from history in \(String(describing: browserManager.tabManager.currentSpace?.name))")
            }
        case .url, .search:
            if browserManager.shouldNavigateCurrentTab && browserManager.tabManager.currentTab != nil {
                // Navigate current tab to new URL with proper normalization
                browserManager.tabManager.currentTab?.navigateToURL(suggestion.text)
                print("Navigated current tab to: \(suggestion.text)")
            } else {
                // Create new tab
                let tab = browserManager.tabManager.createNewTab(url: suggestion.text, in: browserManager.tabManager.currentSpace)
                print("Created tab \(tab.name) in \(String(describing: browserManager.tabManager.currentSpace?.name))")
            }
        }
        
        text = ""
        selectedSuggestionIndex = -1
        browserManager.closeCommandPalette()
    }

    private func navigateSuggestions(direction: Int) {
        let maxIndex = searchManager.suggestions.count - 1

        if direction > 0 {
            selectedSuggestionIndex = min(selectedSuggestionIndex + 1, maxIndex)
        } else {
            selectedSuggestionIndex = max(selectedSuggestionIndex - 1, -1)
        }
    }
    
    private func iconForSuggestion(_ suggestion: SearchManager.SearchSuggestion) -> Image {
        switch suggestion.type {
        case .tab(let tab):
            return tab.favicon
        case .history:
            return Image(systemName: "globe")
        case .url:
            return Image(systemName: "link")
        case .search:
            return Image(systemName: "magnifyingglass")
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
    
    private func urlForSuggestion(_ suggestion: SearchManager.SearchSuggestion) -> URL? {
        switch suggestion.type {
        case .history(let entry):
            return entry.url
        default:
            return nil
        }
    }
    
    private func isTabSuggestion(_ suggestion: SearchManager.SearchSuggestion) -> Bool {
        switch suggestion.type {
        case .tab:
            return true
        case .search, .url, .history:
            return false
        }
    }
}

#if DEBUG
#Preview("Manual Command Palette Preview") {
    @Previewable @Environment(\.colorScheme) var colorScheme
    let isDark = colorScheme == .dark
    ZStack {
        Color.black.opacity(0.2)
            .ignoresSafeArea()

        VStack(spacing: 0) {
            // Fake search input row
            HStack(spacing: 12) {
                Image(systemName: "globe")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)

                Rectangle()
                    .fill(Color.white.opacity(0.2))
                    .frame(height: 20)
                    .cornerRadius(4)
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 13)

            // Separator
            RoundedRectangle(cornerRadius: 100)
                .fill(Color.white.opacity(0.4))
                .frame(height: 1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            // Fake suggestion rows
            VStack(spacing: 2) {
                HStack(spacing: 12) {
                    Image(systemName: "globe")
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 18, height: 18)
                    Text("History Entry Example")
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }
                .padding(8)
                .background(Color.blue.opacity(0.3))
                .cornerRadius(6)

                HStack(spacing: 12) {
                    Image(systemName: "link")
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 18, height: 18)
                    Text("https://example.com")
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }
                .padding(8)
                .background(Color.clear)
                .cornerRadius(6)

                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 18, height: 18)
                    Text("Search query example")
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                }
                .padding(8)
                .background(Color.clear)
                .cornerRadius(6)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 4)
        }
        .frame(width: 600)
        .background(isDark ? Color.white.opacity(0.3) : Color.white.opacity(0.8))
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .padding()
    }
}
#endif

