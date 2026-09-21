// Licensed under GPL-3.0. See LICENSE.
//
//  Shortcuts.swift
//  Nook
//
//  Created by Maciek Bagiński on 03/08/2025.
//

import SwiftUI
import NookDesign

struct ShortcutsSettingsView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(\.nookSettings) var nookSettings
    @State private var searchText = ""
    @State private var selectedCategory: ShortcutCategory? = nil
    @Environment(KeyboardShortcutManager.self) var keyboardShortcutManager

    private var filteredShortcuts: [KeyboardShortcut] {
        var filtered = keyboardShortcutManager.shortcuts

        // Filter by category
        if let category = selectedCategory {
            filtered = filtered.filter { $0.action.category == category }
        }

        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter { shortcut in
                shortcut.action.displayName.localizedCaseInsensitiveContains(searchText)
            }
        }

        // Sort by category and display name
        return filtered.sorted {
            if $0.action.category != $1.action.category {
                return $0.action.category.rawValue < $1.action.category.rawValue
            }
            return $0.action.displayName < $1.action.displayName
        }
    }

    private var shortcutsByCategory: [ShortcutCategory: [KeyboardShortcut]] {
        Dictionary(grouping: filteredShortcuts, by: { $0.action.category })
    }

    var body: some View {
        Form {
            Section {
                Toggle("Detect Website Shortcuts", isOn: Binding(
                    get: { WebsiteShortcutProfile.isFeatureEnabled },
                    set: { WebsiteShortcutProfile.isFeatureEnabled = $0 }
                ))
            } footer: {
                Text("When a website uses the same shortcut, press once for the website, twice for Nook.")
            }

            Section("Filter") {
                LabeledContent("Search") {
                    TextField("Search shortcuts...", text: $searchText)
                        .textFieldStyle(.roundedBorder)
                }

                Picker("Category", selection: $selectedCategory) {
                    Text("All").tag(nil as ShortcutCategory?)
                    ForEach(ShortcutCategory.allCases, id: \.self) { category in
                        Text(category.displayName).tag(category as ShortcutCategory?)
                    }
                }

                Button("Reset to Defaults") {
                    keyboardShortcutManager.resetToDefaults()
                }
            }

            ForEach(ShortcutCategory.allCases, id: \.self) { category in
                if let categoryShortcuts = shortcutsByCategory[category], !categoryShortcuts.isEmpty {
                    Section(category.displayName) {
                        ForEach(categoryShortcuts, id: \.id) { shortcut in
                            ShortcutRowView(shortcut: shortcut)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Shortcut Row

private struct ShortcutRowView: View {
    let shortcut: KeyboardShortcut
    @Environment(KeyboardShortcutManager.self) var keyboardShortcutManager
    @State private var localKeyCombination: KeyCombination

    init(shortcut: KeyboardShortcut) {
        self.shortcut = shortcut
        self._localKeyCombination = State(initialValue: shortcut.keyCombination)
    }

    var body: some View {
        LabeledContent {
            HStack(spacing: NookDesign.Spacing.lg) {
                // Shortcut recorder
                if shortcut.isCustomizable {
                    ShortcutRecorderView(
                        keyCombination: $localKeyCombination,
                        action: shortcut.action,
                        shortcutManager: keyboardShortcutManager,
                        onRecordingComplete: {
                            updateShortcut()
                        }
                    )

                    Toggle("Enabled", isOn: Binding(
                        get: { shortcut.isEnabled },
                        set: { newValue in
                            keyboardShortcutManager.toggleShortcut(action: shortcut.action, isEnabled: newValue)
                        }
                    ))
                    .labelsHidden()
                } else {
                    Text(shortcut.keyCombination.displayString)
                        .font(NookDesign.Font.body.monospaced())
                        .padding(.horizontal, NookDesign.Spacing.lg)
                        .padding(.vertical, NookDesign.Spacing.sm)
                        .background(NookDesign.Surface.raised)
                        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: NookDesign.Spacing.xxs) {
                Text(shortcut.action.displayName)
                Text(shortcut.action.category.displayName)
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: shortcut) { _, newShortcut in
            localKeyCombination = newShortcut.keyCombination
        }
    }

    private func updateShortcut() {
        keyboardShortcutManager.updateShortcut(action: shortcut.action, keyCombination: localKeyCombination)
    }
}
