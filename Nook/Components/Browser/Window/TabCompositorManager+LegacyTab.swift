//
//  TabCompositorManager+LegacyTab.swift
//  Nook
//
//  `Tab` entry points kept for TabManager, Tab and BrowserManager until task Z deletes `Tab`.
//

import Foundation

extension TabCompositorManager {
    func loadTab(_ tab: Tab) {
        markTabAccessed(tab.id)
        tab.loadWebViewIfNeeded()
    }

    func unloadTab(_ tab: Tab) {
        forget(tab.id)
        tab.unloadWebView()
    }

    func canUnloadInactiveTab(_ tab: Tab) -> Bool {
        browserManager?.tabs.session(for: tab.id).map(canUnloadInactive) ?? false
    }
}
