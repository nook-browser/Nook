// Licensed under GPL-3.0. See LICENSE.
//
//  TabSelection.swift
//  NookWeb
//

import Foundation

/// A window's multi-selected tab rows (Cmd-click, Shift-click). In memory only.
public struct TabSelection: Equatable, Sendable {
    public private(set) var ids: Set<UUID> = []
    public private(set) var anchor: UUID?

    public init() {}

    public var isEmpty: Bool { ids.isEmpty }
    public func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// Cmd-click. The first one also takes the tab the window shows.
    public mutating func toggle(_ id: UUID, current: UUID?) {
        if ids.isEmpty, let current { ids = [current] }
        if !ids.insert(id).inserted { ids.remove(id) }
        anchor = id
    }

    /// Shift-click. Replaces the selection with the rows from the anchor (else the shown tab) to `id`.
    /// `rows` are the visible tab rows of the clicked row's section; an anchor outside it starts over.
    public mutating func extend(to id: UUID, rows: [UUID], current: UUID?) {
        guard let base = anchor ?? current, let a = rows.firstIndex(of: base), let b = rows.firstIndex(of: id) else {
            ids = [id]
            anchor = id
            return
        }
        ids = Set(rows[min(a, b)...max(a, b)])
        anchor = base
    }

    public mutating func clear() {
        ids = []
        anchor = nil
    }
}
