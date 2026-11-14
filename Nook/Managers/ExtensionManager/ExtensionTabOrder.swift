// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionTabOrder.swift
//  Nook
//
//  The tab order the extension adapters answer from, kept between WebKit's calls.
//

import Foundation
import Observation

/// One space's tabs in the order extensions see them, with each tab's position.
struct ExtensionTabOrder {
    static let empty = ExtensionTabOrder([])

    let ids: [UUID]
    private let positions: [UUID: Int]

    init(_ ids: [UUID]) {
        self.ids = ids
        positions = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var count: Int { ids.count }
    func index(of id: UUID) -> Int? { positions[id] }
    func contains(_ id: UUID) -> Bool { positions[id] != nil }
}

/// Tab orders by space, each kept until a value it was read from changes.
///
/// WebKit asks every tab of a window for its index, its window and whether it is active, all
/// within one `tabs.query`, and each answer needs the space's order. Built on every call, one
/// query walked and sorted the whole tab tree several times per tab: with about 130 tabs in a
/// space, an extension that queries on tab events (1Password) kept the main thread busy and
/// the app stopped responding.
///
/// Observation drops an entry from inside the setter of anything `read` observed, so the first
/// read after a change, even one in the same turn such as a tabs.onMoved report, builds the
/// new order. The drop runs before the new value is stored: a read from inside another
/// observer's onChange would keep the old order, and nothing reads it there.
@MainActor
final class ExtensionTabOrderCache {
    private var orders: [UUID: ExtensionTabOrder] = [:]

    /// The order kept for `spaceID`, else `read()`'s. `read` must get everything it depends on
    /// from observable state: an entry built from nothing observable is never dropped.
    func order(for spaceID: UUID, read: () -> [UUID]) -> ExtensionTabOrder {
        if let kept = orders[spaceID] { return kept }
        let order = withObservationTracking {
            ExtensionTabOrder(read())
        } onChange: { [weak self] in
            // Called from the setter itself; the tab model only changes on the main actor.
            MainActor.assumeIsolated { _ = self?.orders.removeValue(forKey: spaceID) }
        }
        orders[spaceID] = order
        return order
    }
}
