//
//  CommandPalette.swift
//  Nook
//
//  Per-window command palette state and actions
//

import Foundation
import SwiftUI

@MainActor
@Observable
class CommandPalette {
    /// Whether the command palette is visible
    var isVisible: Bool = false

    /// Text to prefill in the command palette
    var prefilledText: String = ""

    /// Whether pressing Return should navigate the current tab (vs creating new tab)
    var shouldNavigateCurrentTab: Bool = false

    // MARK: - Actions

    /// Open the command palette with optional prefill text
    func open(prefill: String = "", navigateCurrentTab: Bool = false) {
        prefilledText = prefill
        self.shouldNavigateCurrentTab = navigateCurrentTab
        DispatchQueue.main.async {
            self.isVisible = true
        }
    }

    /// Open the command palette with the current tab's URL
    func openWithCurrentURL(_ url: URL) {
        open(prefill: url.absoluteString, navigateCurrentTab: true)
    }

    /// Close the command palette
    func close() {
        isVisible = false
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
}
