//
//  FindManager+LegacyTab.swift
//  Nook
//
//  `Tab` entry points kept for BrowserManager until task Z deletes `Tab`.
//

import Foundation

extension FindManager {
    func showFindBar(for tab: Tab?) {
        showFindBar(for: tab.flatMap { $0.browserManager?.tabs.session(for: $0.id) })
    }

    func updateCurrentTab(_ tab: Tab?) {
        updateCurrentSession(tab.flatMap { $0.browserManager?.tabs.session(for: $0.id) })
    }
}
