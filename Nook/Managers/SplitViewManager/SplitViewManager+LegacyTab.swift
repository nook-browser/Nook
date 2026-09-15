//
//  SplitViewManager+LegacyTab.swift
//  Nook
//
//  `Tab` entry points kept for callers outside T3 until task Z deletes `Tab`.
//

import Foundation

extension SplitViewManager {
    func enterSplit(with tab: Tab, placeOn side: Side = .right, in windowState: BrowserWindowState, animate: Bool = true) {
        enterSplit(with: tab.id, placeOn: side, in: windowState)
    }

    /// Split state lives on BrowserWindowState now; nothing to mirror.
    func refreshPublishedState(for windowId: UUID) {}
}
