//
//  CommandPaletteState.swift
//  Nook
//
//  Per-window command palette state and actions
//

import Foundation
import SwiftUI

// MARK: - FocusedValue Key

extension FocusedValues {
    var commandPalette: CommandPaletteState? {
        get { self[CommandPaletteKey.self] }
        set { self[CommandPaletteKey.self] = newValue }
    }
}

private struct CommandPaletteKey: FocusedValueKey {
    typealias Value = CommandPaletteState
}

@MainActor
@Observable
class CommandPaletteState {
    /// Whether the full command palette is visible
    var isVisible: Bool = false

    /// Whether the mini command palette (URL bar popup) is visible
    var isMiniVisible: Bool = false

    /// Text to prefill in the command palette
    var prefilledText: String = ""

    /// Whether pressing Return should navigate the current tab (vs creating new tab)
    var shouldNavigateCurrentTab: Bool = false

    // MARK: - Actions

    /// Open the full command palette with optional prefill text
    func open(prefill: String = "", navigateCurrentTab: Bool = false) {
        prefilledText = prefill
        self.shouldNavigateCurrentTab = navigateCurrentTab
        isMiniVisible = false
        DispatchQueue.main.async {
            self.isVisible = true
        }
    }

    /// Open the full command palette with the current tab's URL
    func openWithCurrentURL(_ url: URL) {
        open(prefill: url.absoluteString, navigateCurrentTab: true)
    }

    /// Close the full command palette
    func close() {
        isVisible = false
        isMiniVisible = false
        shouldNavigateCurrentTab = false
        prefilledText = ""
    }

    /// Toggle the command palette visibility
    func toggle() {
        if isVisible {
            close()
        } else {
            open()
        }
    }

    /// Show the mini command palette (URL bar popup)
    func showMini(prefill: String = "") {
        prefilledText = prefill
        shouldNavigateCurrentTab = true
        isVisible = false
        DispatchQueue.main.async {
            self.isMiniVisible = true
        }
    }

    /// Hide the mini command palette
    func hideMini() {
        isMiniVisible = false
        shouldNavigateCurrentTab = false
        prefilledText = ""
    }
}
