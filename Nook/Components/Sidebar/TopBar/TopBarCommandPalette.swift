//
//  TopBarCommandPalette.swift
//  Nook
//
//

import SwiftUI

struct TopBarCommandPalette: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(CommandPaletteState.self) private var commandPalette
    @Environment(\.colorScheme) var colorScheme

    @State private var searchManager = SearchManager()
    @State private var text: String = ""
    @FocusState private var isSearchFocused: Bool
    @State private var selectedSuggestionIndex: Int = -1

    var body: some View {
        let shouldShow = commandPalette.isMiniVisible && browserManager.settingsManager.topBarAddressView

        ZStack {
            if shouldShow {
                // Background overlay
                Color.clear
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        commandPalette.close()
                    }
                
                // Command palette in center with proper animation
                VStack(spacing: 6) {
                    inputRow()
                    separatorIfNeeded(hasSuggestions: !searchManager.suggestions.isEmpty)
                    suggestionsListView()
                }
                .padding(20)
                .frame(width: 800)
                .background(.thickMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            Color.white.opacity(colorScheme == .dark ? 0.3 : 0.6),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 50, x: 0, y: 4)
                .opacity(shouldShow ? 1.0 : 0.0)
                .scaleEffect(shouldShow ? 1.0 : 0.8)
                .animation(.spring(response: 0.4, dampingFraction: 0.7), value: shouldShow)
            }
        }
        .allowsHitTesting(shouldShow)
        .onAppear {
            if shouldShow {
                searchManager.setTabManager(browserManager.tabManager)
                searchManager.setHistoryManager(browserManager.historyManager)
                searchManager.updateProfileContext()
                text = windowState.commandPalettePrefilledText
                DispatchQueue.main.async { isSearchFocused = true }
            }
        }
        .onChange(of: commandPalette.isMiniVisible) { _, newVisible in
            if newVisible && browserManager.settingsManager.topBarAddressView {
                searchManager.setTabManager(browserManager.tabManager)
                searchManager.setHistoryManager(browserManager.historyManager)
                searchManager.updateProfileContext()
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
            commandPalette.close()
            return .handled
        }
        .onChange(of: searchManager.suggestions.count) { _, newCount in
            if newCount == 0 {
                selectedSuggestionIndex = -1
            } else if selectedSuggestionIndex >= newCount {
                selectedSuggestionIndex = -1
            }
        }
        .onChange(of: text) { _, newText in
            if !newText.isEmpty {
                searchManager.searchSuggestions(for: newText)
            } else {
                searchManager.clearSuggestions()
            }
        }
        .onKeyPress(.downArrow) {
            if selectedSuggestionIndex < searchManager.suggestions.count - 1 {
                selectedSuggestionIndex += 1
            }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if selectedSuggestionIndex > 0 {
                selectedSuggestionIndex -= 1
            }
            return .handled
        }
        .onKeyPress(.return) {
            if selectedSuggestionIndex >= 0 && selectedSuggestionIndex < searchManager.suggestions.count {
                selectSuggestion(searchManager.suggestions[selectedSuggestionIndex])
            } else {
                handleSubmit()
            }
            return .handled
        }
    }
    
    private func inputRow() -> some View {
        let symbolName = isLikelyURL(text) ? "globe" : "magnifyingglass"
        
        return HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
            
            TextField("Search or enter URL...", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .focused($isSearchFocused)
                .onSubmit {
                    handleSubmit()
                }
            
            if !text.isEmpty {
                Button(action: {
                    text = ""
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    private func separatorIfNeeded(hasSuggestions: Bool) -> some View {
        if hasSuggestions {
            return AnyView(
                Divider()
                    .padding(.horizontal, 8)
            )
        } else {
            return AnyView(EmptyView())
        }
    }
    
    private func suggestionsListView() -> some View {
        if searchManager.suggestions.isEmpty {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            VStack(spacing: 0) {
                ForEach(Array(searchManager.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                    TopBarSuggestionRow(
                        suggestion: suggestion,
                        isSelected: index == selectedSuggestionIndex,
                        action: {
                            selectSuggestion(suggestion)
                        }
                    )
                    
                    if index < searchManager.suggestions.count - 1 {
                        Divider()
                            .padding(.horizontal, 8)
                    }
                }
            }
        )
    }
    
    private func selectSuggestion(_ suggestion: SearchManager.SearchSuggestion) {
        text = suggestion.text
        handleSubmit()
    }
    
    private func handleSubmit() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        
        if let currentTab = browserManager.currentTab(for: windowState) {
            currentTab.navigateToURL(text)
        }

        commandPalette.close()
    }
}

struct TopBarSuggestionRow: View {
    let suggestion: SearchManager.SearchSuggestion
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 20)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.text)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    
                    // Note: SearchSuggestion doesn't have subtitle property
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var iconName: String {
        switch suggestion.type {
        case .search:
            return "magnifyingglass"
        case .url:
            return "globe"
        case .tab:
            return "square.on.square"
        case .history:
            return "clock"
        }
    }
    
    private var iconColor: Color {
        switch suggestion.type {
        case .search:
            return .blue
        case .url:
            return .green
        case .tab:
            return .orange
        case .history:
            return .gray
        }
    }
}