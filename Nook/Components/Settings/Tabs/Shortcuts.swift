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
    @State private var searchText = ""
    @Environment(KeyboardShortcutManager.self) var keyboardShortcutManager

    private var shortcutsByCategory: [ShortcutCategory: [KeyboardShortcut]] {
        let matching = keyboardShortcutManager.shortcuts.filter {
            searchText.isEmpty || $0.action.displayName.localizedCaseInsensitiveContains(searchText)
        }
        return Dictionary(grouping: matching, by: { $0.action.category })
    }

    var body: some View {
        Form {
            Section {
                SidebarMenuSearchField(prompt: "Search shortcuts...", text: $searchText)

                Toggle("Detect Website Shortcuts", isOn: Binding(
                    get: { WebsiteShortcutProfile.isFeatureEnabled },
                    set: { WebsiteShortcutProfile.isFeatureEnabled = $0 }
                ))
            } footer: {
                Text("When a website uses the same shortcut, press once for the website, twice for Nook.")
            }

            ForEach(ShortcutCategory.allCases, id: \.self) { category in
                if let categoryShortcuts = shortcutsByCategory[category], !categoryShortcuts.isEmpty {
                    Section(category.displayName) {
                        ForEach(categoryShortcuts, id: \.action) { shortcut in
                            ShortcutRowView(shortcut: shortcut)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Reset to Defaults") {
                        keyboardShortcutManager.resetToDefaults()
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

    private var keys: KeyCombination? {
        shortcut.isEnabled && !shortcut.keyCombination.key.isEmpty ? shortcut.keyCombination : nil
    }

    var body: some View {
        LabeledContent(shortcut.action.displayName) {
            if shortcut.isCustomizable {
                ShortcutRecorderView(
                    keyCombination: keys,
                    action: shortcut.action,
                    shortcutManager: keyboardShortcutManager,
                    onRecord: { keyboardShortcutManager.updateShortcut(action: shortcut.action, keyCombination: $0) }
                )
            } else {
                Text(keys?.displayString ?? "(none)")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
