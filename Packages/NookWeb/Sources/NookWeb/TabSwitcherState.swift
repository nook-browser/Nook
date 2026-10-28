// Licensed under GPL-3.0. See LICENSE.
//
//  TabSwitcherState.swift
//  NookWeb
//
//  The Control-Tab switcher's place in a window's recent tabs: which tabs it shows (most recent
//  first, the current one at the front) and which is highlighted. Foundation only, checked by
//  `Checks/TabSwitcherStateCheck.swift`.
//

import Foundation

public struct TabSwitcherState: Equatable, Sendable {
    public let items: [UUID]
    public private(set) var index: Int

    /// Opens on the tab you were on before this one (or the oldest, going backwards), as Arc's
    /// does; nil when there is nothing to switch to.
    public static func start(items: [UUID], step: Int) -> TabSwitcherState? {
        guard items.count > 1 else { return nil }
        return TabSwitcherState(items: items, index: step >= 0 ? 1 : items.count - 1)
    }

    public mutating func advance(by step: Int) {
        index = ((index + step) % items.count + items.count) % items.count
    }

    public var highlighted: UUID { items[index] }
}
