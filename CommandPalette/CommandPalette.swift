// Licensed under GPL-3.0. See LICENSE.
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

    /// Whether the current presentation was opened from a URL bar.
    var openedFromURLBar = false

    // MARK: - Actions

    /// Open the command palette with optional prefill text
    func open(prefill: String = "", navigateCurrentTab: Bool = false) {
        openedFromURLBar = false
        present(prefill: prefill, navigateCurrentTab: navigateCurrentTab)
    }

    /// Open from the URL bar so the palette can animate from that control.
    func openFromURLBar(prefill: String = "", navigateCurrentTab: Bool = false) {
        openedFromURLBar = true
        present(prefill: prefill, navigateCurrentTab: navigateCurrentTab)
    }

    private func present(prefill: String, navigateCurrentTab: Bool) {
        prefilledText = prefill
        self.shouldNavigateCurrentTab = navigateCurrentTab
        DispatchQueue.main.async {
            self.isVisible = true
        }
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
