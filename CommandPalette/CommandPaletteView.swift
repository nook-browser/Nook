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
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPalette.self) private var commandPalette
    @EnvironmentObject var gradientColorManager: GradientColorManager
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
        let isVisible = commandPalette.isVisible
        let textFieldColor: Color = text.isEmpty
            ? (isDark ? .white.opacity(0.25) : .black.opacity(0.25))
            : (isDark ? .white.opacity(0.9) : .black.opacity(0.9))

        return ZStack {
            Color.clear
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {
                    commandPalette.close()
                }
                .gesture(WindowDragGesture())

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack {
                        VStack(alignment: .center,spacing: 6) {
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
                                    .foregroundColor(textFieldColor)
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
                                    .onKeyPress(.escape) {
                                        commandPalette.close()
                                        return .handled
                                    }
                                    .onChange(of: text) { _, newValue in
                                        searchManager.searchSuggestions(
                                            for: newValue
                                        )
                                        selectedSuggestionIndex = searchManager.suggestions.isEmpty ? -1 : 0
                                    }
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 8)

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
                        .background(Color(.windowBackgroundColor).opacity(0.35))
                        .clipShape(.rect(cornerRadius: 26))
                        .universalGlassEffect(
                            .regular.tint(Color(.windowBackgroundColor).opacity(0.35)),
                            in: .rect(cornerRadius: 26))
                        .animation(
                            .easeInOut(duration: 0.15),
                            value: searchManager.suggestions.count
                        )
                        Spacer()
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
        .onChange(of: commandPalette.isVisible) { _, newVisible in
            if newVisible {
                searchManager.setTabManager(browserManager.tabManager)
                searchManager.setHistoryManager(browserManager.historyManager)
                searchManager.updateProfileContext()

                text = commandPalette.prefilledText

                DispatchQueue.main.async {
                    isSearchFocused = true
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
        .onChange(of: browserManager.currentProfile?.id) { _, _ in
            if commandPalette.isVisible {
                searchManager.updateProfileContext()
                searchManager.clearSuggestions()
            }
        }
        .onChange(of: searchManager.suggestions.count) { _, newCount in
            if newCount == 0 {
                selectedSuggestionIndex = -1
            } else if selectedSuggestionIndex < 0 || selectedSuggestionIndex >= newCount {
                selectedSuggestionIndex = 0
            }
        }
        .animation(.easeInOut(duration: 0.15), value: selectedSuggestionIndex)
        .onChange(of: commandPalette.prefilledText) { _, newValue in
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
        @EnvironmentObject var gradientColorManager: GradientColorManager
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
            browserManager.selectTab(existingTab, in: windowState)
            print("Switched to existing tab: \(existingTab.name)")
        case .history(let historyEntry):
            if commandPalette.shouldNavigateCurrentTab
                && browserManager.currentTab(for: windowState) != nil
            {
                browserManager.currentTab(for: windowState)?.loadURL(
                    historyEntry.url.absoluteString
                )
                print(
                    "Navigated current tab to history URL: \(historyEntry.url)"
                )
            } else {
                browserManager.createNewTab(in: windowState)
                browserManager.currentTab(for: windowState)?.loadURL(
                    historyEntry.url.absoluteString
                )
                print(
                    "Created new tab from history in window \(windowState.id)"
                )
            }
        case .url, .search:
            if commandPalette.shouldNavigateCurrentTab
                && browserManager.currentTab(for: windowState) != nil
            {
                browserManager.currentTab(for: windowState)?.navigateToURL(
                    suggestion.text
                )
                print("Navigated current tab to: \(suggestion.text)")
            } else {
                browserManager.createNewTab(in: windowState)
                browserManager.currentTab(for: windowState)?.navigateToURL(
                    suggestion.text
                )
                print("Created new tab in window \(windowState.id)")
            }
        }

        text = ""
        selectedSuggestionIndex = -1
        commandPalette.close()
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

struct BackdropView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .withinWindow
        view.state = .active
        return view
    }
    
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) { }
}
