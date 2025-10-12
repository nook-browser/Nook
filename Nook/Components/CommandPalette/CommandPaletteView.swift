//
//  CommandPaletteView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import AppKit
import SwiftUI
import UniversalGlass
import Garnish

struct CommandPaletteView: View {
    @Environment(BrowserManager.self) private var browserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(GradientColorManager.self) private var gradientColorManager
    @State private var searchManager = SearchManager()
    @Environment(\.colorScheme) var colorScheme

    @FocusState private var isSearchFocused: Bool
    @State private var text: String = ""
    @State private var selectedSuggestionIndex: Int = -1
    @State private var hoveredSuggestionIndex: Int? = nil
    
    let commandPaletteWidth: CGFloat = 765
    let commandPaletteHorizontalPadding: CGFloat = 10
    
    /// Active window width
    private var currentWindowWidth: CGFloat {
        return NSApplication.shared.keyWindow?.frame.width ?? 0
    }
    
    /// Check if the command palette fits in the window
    private var isWindowTooNarrow: Bool {
        let requiredWidth = commandPaletteWidth + (commandPaletteHorizontalPadding * 2)
        return currentWindowWidth <= requiredWidth
    }
    
    /// Caclulate the correct command palette width
    private var effectiveCommandPaletteWidth: CGFloat {
        if isWindowTooNarrow {
            return max(200, currentWindowWidth - (commandPaletteHorizontalPadding * 2))
        } else {
            return commandPaletteWidth
        }
    }

    var body: some View {
        let isDark = colorScheme == .dark
        let isActiveWindow =
            browserManager.activeWindowState?.id == windowState.id
        let isVisible = isActiveWindow && windowState.isCommandPaletteVisible

        ZStack {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    browserManager.closeCommandPalette(for: windowState)
                }
                .gesture(WindowDragGesture())

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack {
                        VStack(alignment: .center,spacing: 6) {
                            // Input field - fixed at top of box
                            HStack(spacing: 15) {
                                Image(
                                    systemName: isLikelyURL(text)
                                        ? "globe" : "magnifyingglass"
                                )
                                .id(isLikelyURL(text) ? "globe" : "magnifyingglass")
                                .transition(.blur(intensity: 2, scale: 0.6).animation(.smooth(duration: 0.3)))
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(isDark ? .white : .black)
                                .frame(width: 15)

                                TextField("Search or enter URL...", text: $text)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(
                                        text.isEmpty
                                            ? isDark
                                                ? .white.opacity(0.25)
                                                : .black.opacity(0.25)
                                            : isDark
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
                                        searchManager.searchSuggestions(
                                            for: newValue
                                        )
                                        if windowState.commandPalettePrefilledText
                                            != newValue
                                        {
                                            windowState
                                                .commandPalettePrefilledText =
                                                newValue
                                        }
                                    }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)

                            // Separator
                            if !searchManager.suggestions.isEmpty {
                                RoundedRectangle(cornerRadius: 100)
                                    .fill(
                                        isDark
                                            ? Color.white.opacity(0.4)
                                            : Color.black.opacity(0.4)
                                    )
                                    .frame(height: 0.5)
                                    .frame(maxWidth: .infinity)

                            }

                            // Suggestions - expand the box downward
                            if !searchManager.suggestions.isEmpty {
                                let suggestions = searchManager.suggestions
                                CommandPaletteSuggestionsListView(
                                    suggestions: suggestions,
                                    selectedIndex: $selectedSuggestionIndex,
                                    hoveredIndex: $hoveredSuggestionIndex,
                                    onSelect: { suggestion in
                                        selectSuggestion(suggestion)
                                    }
                                )
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity)
                        .frame(width: effectiveCommandPaletteWidth)
                        .universalGlassEffect(
                            .regular.tint(
                                gradientColorManager.primaryColor.adjustedLuminance(by: colorScheme == .light ? 0.4 : 0.2).opacity( colorScheme == .light ? 0.05 : 0.55)
                            ),
                            in: .rect(cornerRadius: 26))
                        .animation(
                            .easeInOut(duration: 0.15),
                            value: searchManager.suggestions.count
                        )
                        Spacer()
                            .border(.red)
                    }
                    .frame(
                        width: effectiveCommandPaletteWidth,
                        height: 328
                    )

                    Spacer()
                }
                Spacer()
            }

        }
        .allowsHitTesting(isVisible)
        .opacity(isVisible ? 1.0 : 0.0)
        .onChange(of: windowState.isCommandPaletteVisible) { _, newVisible in
            if newVisible && isActiveWindow {
                searchManager.setTabManager(browserManager.tabManager)
                searchManager.setHistoryManager(browserManager.historyManager)
                searchManager.updateProfileContext()

                // Pre-fill text if provided and select all for easy replacement
                text = windowState.commandPalettePrefilledText

                DispatchQueue.main.async {
                    isSearchFocused = true
                    // Select all once focused so the URL is highlighted
                    DispatchQueue.main.async {
                        NSApplication.shared.sendAction(
                            #selector(NSText.selectAll(_:)),
                            to: nil,
                            from: nil
                        )
                    }
                }
            } else {
                isSearchFocused = false
                searchManager.clearSuggestions()
                text = ""
                selectedSuggestionIndex = -1
            }
        }
        // Keep search profile context updated while palette is open
        .onChange(of: browserManager.currentProfile?.id) { _, _ in
            if windowState.isCommandPaletteVisible {
                searchManager.updateProfileContext()
                // Clear suggestions to avoid cross-profile residue
                searchManager.clearSuggestions()
            }
        }
        .onKeyPress(.escape) {
            DispatchQueue.main.async {
                browserManager.closeCommandPalette(for: windowState)
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
        .animation(.easeInOut(duration: 0.15), value: selectedSuggestionIndex)
        .onChange(of: windowState.commandPalettePrefilledText) { _, newValue in
            if isVisible {
                text = newValue
                DispatchQueue.main.async {
                    isSearchFocused = true
                }
            }
        }
    }

    private func isEmoji(_ string: String) -> Bool {
        return string.unicodeScalars.contains { scalar in
            (scalar.value >= 0x1F300 && scalar.value <= 0x1F9FF)
                || (scalar.value >= 0x2600 && scalar.value <= 0x26FF)
                || (scalar.value >= 0x2700 && scalar.value <= 0x27BF)
        }
    }

    // MARK: - Suggestions List Subview
    private struct CommandPaletteSuggestionsListView: View {
        @Environment(GradientColorManager.self) private var gradientColorManager
        let suggestions: [SearchManager.SearchSuggestion]
        @Binding var selectedIndex: Int
        @Binding var hoveredIndex: Int?
        @Environment(\.colorScheme) var colorScheme
        let onSelect: (SearchManager.SearchSuggestion) -> Void

        var body: some View {
            let isDark = colorScheme == .dark
            LazyVStack(spacing: 5) {
                ForEach(suggestions.indices, id: \.self) { index in
                    let suggestion = suggestions[index]
                    let isHovered = hoveredIndex == index
                    row(for: suggestion, isSelected: selectedIndex == index)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 11)
                        .background(
                            selectedIndex == index
                                ? gradientColorManager.primaryColor
                                : isHovered
                                    ? isDark
                                        ? .white.opacity(0.05)
                                        : .black.opacity(0.05) : .clear
                        )
                        .clipShape(
                            RoundedRectangle(cornerRadius: 6)
                        )
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                        .onHover { hovering in
                            withAnimation(.easeInOut(duration: 0.12)) {
                                if hovering {
                                    hoveredIndex = index
                                } else {
                                    hoveredIndex = nil
                                }
                            }
                        }
                        .onTapGesture { onSelect(suggestion) }
                }
            }
        }

        @ViewBuilder
        private func row(
            for suggestion: SearchManager.SearchSuggestion,
            isSelected: Bool
        ) -> some View {
            switch suggestion.type {
            case .tab(let tab):
                TabSuggestionItem(tab: tab, isSelected: isSelected)
            case .history(let entry):
                HistorySuggestionItem(entry: entry, isSelected: isSelected)
            case .url:
                GenericSuggestionItem(
                    icon: Image(systemName: "link"),
                    text: suggestion.text,
                    isSelected: isSelected
                )
            case .search:
                GenericSuggestionItem(
                    icon: Image(systemName: "magnifyingglass"),
                    text: suggestion.text,
                    isSelected: isSelected
                )
            }
        }
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

    private func selectSuggestion(_ suggestion: SearchManager.SearchSuggestion)
    {
        switch suggestion.type {
        case .tab(let existingTab):
            // Switch to existing tab in this window
            browserManager.selectTab(existingTab, in: windowState)
            print("Switched to existing tab: \(existingTab.name)")
        case .history(let historyEntry):
            if windowState.shouldNavigateCurrentTab
                && browserManager.currentTab(for: windowState) != nil
            {
                // Navigate current tab to history URL
                browserManager.currentTab(for: windowState)?.loadURL(
                    historyEntry.url.absoluteString
                )
                print(
                    "Navigated current tab to history URL: \(historyEntry.url)"
                )
            } else {
                // Create new tab from history entry
                browserManager.createNewTab(in: windowState)
                browserManager.currentTab(for: windowState)?.loadURL(
                    historyEntry.url.absoluteString
                )
                print(
                    "Created new tab from history in window \(windowState.id)"
                )
            }
        case .url, .search:
            if windowState.shouldNavigateCurrentTab
                && browserManager.currentTab(for: windowState) != nil
            {
                // Navigate current tab to new URL with proper normalization
                browserManager.currentTab(for: windowState)?.navigateToURL(
                    suggestion.text
                )
                print("Navigated current tab to: \(suggestion.text)")
            } else {
                // Create new tab
                browserManager.createNewTab(in: windowState)
                browserManager.currentTab(for: windowState)?.navigateToURL(
                    suggestion.text
                )
                print("Created new tab in window \(windowState.id)")
            }
        }

        text = ""
        selectedSuggestionIndex = -1
        browserManager.closeCommandPalette(for: windowState)
    }

    private func navigateSuggestions(direction: Int) {
        let maxIndex = searchManager.suggestions.count - 1

        if direction > 0 {
            selectedSuggestionIndex = min(selectedSuggestionIndex + 1, maxIndex)
        } else {
            selectedSuggestionIndex = max(selectedSuggestionIndex - 1, -1)
        }
    }

    private func iconForSuggestion(_ suggestion: SearchManager.SearchSuggestion)
        -> Image
    {
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
    private func suggestionRow(
        for suggestion: SearchManager.SearchSuggestion,
        isSelected: Bool
    ) -> some View {
        switch suggestion.type {
        case .tab(let tab):
            TabSuggestionItem(tab: tab, isSelected: isSelected)
                .foregroundStyle(AppColors.textPrimary)
        case .history(let entry):
            HistorySuggestionItem(entry: entry, isSelected: isSelected)
                .foregroundStyle(AppColors.textPrimary)
        case .url:
            GenericSuggestionItem(
                icon: Image(systemName: "link"),
                text: suggestion.text,
                isSelected: isSelected
            )
            .foregroundStyle(AppColors.textPrimary)
        case .search:
            GenericSuggestionItem(
                icon: Image(systemName: "magnifyingglass"),
                text: suggestion.text,
                isSelected: isSelected
            )
            .foregroundStyle(AppColors.textPrimary)
        }
    }

    private func urlForSuggestion(_ suggestion: SearchManager.SearchSuggestion)
        -> URL?
    {
        switch suggestion.type {
        case .history(let entry):
            return entry.url
        default:
            return nil
        }
    }

    private func isTabSuggestion(_ suggestion: SearchManager.SearchSuggestion)
        -> Bool
    {
        switch suggestion.type {
        case .tab:
            return true
        case .search, .url, .history:
            return false
        }
    }
}
