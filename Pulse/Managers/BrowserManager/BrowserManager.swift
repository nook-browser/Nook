//
//  BrowserManager.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI

final class BrowserManager: ObservableObject {
    @Published var sidebarWidth: CGFloat = 250
    @Published var isSidebarVisible: Bool = true
    @Published var hasSplitView: Bool = false
    @Published var isCommandPaletteVisible: Bool = false
    
    // NEW: keep/persist split ratio (0...1)
    @Published var splitRatio: CGFloat = 0.5
    
    var tabManager: TabManager
    
    private var savedSidebarWidth: CGFloat = 250
    private let userDefaults = UserDefaults.standard
    
    init() {
        self.tabManager = TabManager()
        loadSidebarSettings()
        loadSplitSettings()
        self.tabManager.browserManager = self
    }
    
    // MARK: - Split helpers
    func openSplit(duplicate: Bool = true) {
        guard let left = tabManager.currentTab else { return }
        if duplicate {
            let clone = tabManager.duplicate(tab: left)
            tabManager.currentSplittedTab = clone
        } else if let next = tabManager.nextTab(after: left) {
            tabManager.currentSplittedTab = next
        } else {
            // fallback: open a default tab on the right
            tabManager.currentSplittedTab = tabManager.createNewTab(url: "https://apple.com")
        }
        hasSplitView = (tabManager.currentSplittedTab != nil)
        saveSplitSettings()
    }
    
    func setSplit(with tab: Tab) {
        tabManager.currentSplittedTab = tab
        hasSplitView = true
        saveSplitSettings()
    }
    
    func closeSplit() {
        hasSplitView = false
        tabManager.currentSplittedTab = nil
        saveSplitSettings()
    }
    
    func updateSplitRatio(_ ratio: CGFloat) {
        splitRatio = min(max(0.2, ratio), 0.7) // keep panes usable
        saveSplitSettings()
    }
    
    // MARK: - Sidebar (unchanged)
    func updateSidebarWidth(_ width: CGFloat) {
        sidebarWidth = width
        savedSidebarWidth = width
    }
    func saveSidebarWidthToDefaults() { saveSidebarSettings() }
    func toggleSidebar() {
        withAnimation(.easeInOut(duration: 0.1)) {
            isSidebarVisible.toggle()
            sidebarWidth = isSidebarVisible ? savedSidebarWidth : 0
        }
        saveSidebarSettings()
    }
    
    // MARK: - Command Palette (unchanged)
    func openCommandPalette() { isCommandPaletteVisible = true }
    func closeCommandPalette() { isCommandPaletteVisible = false }
    func toggleCommandPalette() { isCommandPaletteVisible ? closeCommandPalette() : openCommandPalette() }
    
    // MARK: - Tab delegation (unchanged)
    func createNewTab() { _ = tabManager.createNewTab() }
    func closeCurrentTab() { tabManager.closeActiveTab() }
    func focusURLBar() { print("Focus URL bar") }
    
    // MARK: - Persistence
    private func loadSidebarSettings() {
        let savedWidth = userDefaults.double(forKey: "sidebarWidth")
        let savedVisibility = userDefaults.bool(forKey: "sidebarVisible")
        if savedWidth > 0 {
            savedSidebarWidth = savedWidth
            sidebarWidth = savedVisibility ? savedWidth : 0
        }
        isSidebarVisible = savedVisibility
    }
    
    private func saveSidebarSettings() {
        userDefaults.set(savedSidebarWidth, forKey: "sidebarWidth")
        userDefaults.set(isSidebarVisible, forKey: "sidebarVisible")
    }
    
    private func loadSplitSettings() {
        hasSplitView = userDefaults.bool(forKey: "hasSplitView")
        let ratio = userDefaults.double(forKey: "splitRatio")
        if ratio > 0 { splitRatio = CGFloat(ratio) }
    }
    
    public func saveSplitSettings() {
        userDefaults.set(hasSplitView, forKey: "hasSplitView")
        userDefaults.set(splitRatio, forKey: "splitRatio")
    }
}
