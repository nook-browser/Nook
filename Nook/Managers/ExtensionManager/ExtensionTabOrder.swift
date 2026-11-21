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

/// Tab orders by space, kept so one `tabs.query` builds each order once, not once per tab.
/// An entry drops when anything `read` observed changes, before the new value is stored.
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
