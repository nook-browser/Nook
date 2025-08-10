//
//  TabManager.swift
//  Pulse
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import AppKit
import Observation
import WebKit
@Observable
class TabManager {
    weak var browserManager: BrowserManager?
    
    var tabs: [Tab] = []
    var currentTab: Tab?
    var currentSplittedTab: Tab?
    
    init(browserManager: BrowserManager? = nil) {
        self.browserManager = browserManager
    }
    
    // MARK: - Tab Management
    func addTab(_ tab: Tab) {
        tab.browserManager = browserManager
        tabs.append(tab)
        print("Added tab: \(tab.name)")
    }
    
    func removeTab(_ id: UUID) {
        if let index = tabs.firstIndex(where: { $0.id == id }) {
            let tab = tabs[index]
            tabs.remove(at: index)
            if currentTab?.id == id {
                currentTab = tabs.isEmpty ? nil : tabs[max(0, index - 1)]
            }
            print("Removed tab: \(tab.name)")
        }
    }
    
    func setActiveTab(_ tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }) else { return }
        if let old = currentTab, old.id != tab.id { old.pause() }
        currentTab = tab
        print("Set active tab: \(tab.name) (ID: \(tab.id))")
    }
    
    func closeActiveTab() {
        guard let currentTab else { return }
        removeTab(currentTab.id)
    }
    
    func createNewTab(url: String = "https://www.google.com") -> Tab {
        guard let validURL = URL(string: normalizeURL(url)) else {
            print("Invalid URL: \(url) – falling back to Google")
            return createNewTab()
        }
        let newTab = Tab(
            url: validURL, name: "New Tab", favicon: "globe",
            spaceId: nil, browserManager: browserManager
        )
        addTab(newTab)
        setActiveTab(newTab)
        return newTab
    }
    
    // NEW: duplicate and next helpers
    func duplicate(tab: Tab) -> Tab {
        let clone = Tab(
            url: tab.url,
            name: tab.name,
            favicon: "globe",
            spaceId: tab.spaceId,
            browserManager: browserManager
        )
        addTab(clone)
        return clone
    }
    
    func nextTab(after tab: Tab) -> Tab? {
        guard let i = tabs.firstIndex(where: { $0.id == tab.id }) else { return nil }
        let j = tabs.index(after: i)
        return j < tabs.endIndex ? tabs[j] : nil
    }
    
    // FIXED: proper scheme and flags
    func setSplittedTab() {
        guard let manager = browserManager else { return }
        /*let right = Tab(url: URL(string: "https://apple.com")!, name: "Apple", favicon: "safari", spaceId: nil, browserManager: browserManager)
        addTab(right)
        currentSplittedTab = right*/
        manager.hasSplitView = true
        manager.saveSplitSettings()
    }
    
    // MARK: - Navigation
    func selectNextTab() {
        guard !tabs.isEmpty, let current = currentTab,
              let i = tabs.firstIndex(where: { $0.id == current.id }) else { return }
        setActiveTab(tabs[(i + 1) % tabs.count])
    }
    
    func selectPreviousTab() {
        guard !tabs.isEmpty, let current = currentTab,
              let i = tabs.firstIndex(where: { $0.id == current.id }) else { return }
        let prev = (i == 0) ? tabs.count - 1 : i - 1
        setActiveTab(tabs[prev])
    }
    
    // MARK: - Utils
    func getTab(by id: UUID) -> Tab? { tabs.first { $0.id == id } }
    var tabCount: Int { tabs.count }
    var hasCurrentTab: Bool { currentTab != nil }
}
