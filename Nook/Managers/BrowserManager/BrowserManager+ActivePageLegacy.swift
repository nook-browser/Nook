//
//  BrowserManager+ActivePageLegacy.swift
//  Nook
//
//  `Tab` lookup kept for callers outside T3 until task Z deletes `Tab`.
//

import Foundation

extension BrowserManager {
    /// Get the current tab for the active window (used by keyboard shortcuts)
    func currentTabForActiveWindow() -> Tab? {
        if let activeWindow = windowRegistry?.activeWindow {
            return currentTab(for: activeWindow)
        }
        // Fallback to global current tab for backward compatibility
        return tabManager.currentTab
    }
}
