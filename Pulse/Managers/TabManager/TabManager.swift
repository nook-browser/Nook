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
            
            // If we're closing the current tab, switch to another tab
            if currentTab?.id == id {
                if !tabs.isEmpty {
                    // Switch to the previous tab, or the first tab if this was the first
                    let newIndex = max(0, index - 1)
                    currentTab = tabs.indices.contains(newIndex) ? tabs[newIndex] : tabs.first
                } else {
                    currentTab = nil
                }
            }
            
            print("Removed tab: \(tab.name)")
        }
    }
    
    func setActiveTab(_ tab: Tab) {
        guard tabs.contains(where: { $0.id == tab.id }) else {
            print("Tab not found in tabs array")
            return
        }
        
        // Pause media in the current tab before switching
        if let oldTab = currentTab, oldTab.id != tab.id {
            oldTab.pause()
        }
        
        print("Set active tab: \(tab.name) (ID: \(tab.id))")
        currentTab = tab
    }
    
    func closeActiveTab() {
        guard let currentTab = currentTab else {
            print("No active tab to close")
            return
        }
        removeTab(currentTab.id)
    }
    
    func createNewTab(url: String = "https://www.google.com") -> Tab {
        guard let validURL = URL(string: normalizeURL(url)) else {
            print("Invalid URL: \(url)")
            return createNewTab()
        }
        print(normalizeURL(url))
        
        let newTab = Tab(
            url: validURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: nil,
            browserManager: browserManager
        )
        
        addTab(newTab)
        setActiveTab(newTab)
        
        return newTab
    }
    
    
    
    // MARK: - Tab Navigation
    func selectNextTab() {
        guard !tabs.isEmpty, let current = currentTab else { return }
        
        if let currentIndex = tabs.firstIndex(where: { $0.id == current.id }) {
            let nextIndex = (currentIndex + 1) % tabs.count
            setActiveTab(tabs[nextIndex])
        }
    }
    
    func selectPreviousTab() {
        guard !tabs.isEmpty, let current = currentTab else { return }
        
        if let currentIndex = tabs.firstIndex(where: { $0.id == current.id }) {
            let previousIndex = currentIndex == 0 ? tabs.count - 1 : currentIndex - 1
            setActiveTab(tabs[previousIndex])
        }
    }
    
    // MARK: - Utility
    func getTab(by id: UUID) -> Tab? {
        return tabs.first { $0.id == id }
    }
    
    var tabCount: Int {
        return tabs.count
    }
    
    var hasCurrentTab: Bool {
        return currentTab != nil
    }

}
