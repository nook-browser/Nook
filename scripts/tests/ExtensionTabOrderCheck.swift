// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionTabOrderCheck.swift
//  Nook
//
//  The extension adapters' tab order is read once per change and rebuilt on the first read
//  after one. Compiles the shipped source directly:
//
//    swiftc Nook/Managers/ExtensionManager/ExtensionTabOrder.swift \
//           scripts/tests/ExtensionTabOrderCheck.swift \
//           -o /tmp/extension-tab-order-check && /tmp/extension-tab-order-check
//

import Foundation
import Observation

/// Stands in for TabsController: an observed tree and open folders, and one value nothing renders.
@MainActor
@Observable
final class Model {
    var tree: [UUID] = []
    var openFolders: Set<UUID> = []
    var otherTree: [UUID] = []
    @ObservationIgnored var ignored = 0
}

@main
struct ExtensionTabOrderCheck {
    @MainActor
    static func main() {
        let model = Model()
        let cache = ExtensionTabOrderCache()
        let space = UUID(), otherSpace = UUID()
        var reads = 0
        func order() -> ExtensionTabOrder {
            cache.order(for: space) {
                reads += 1
                _ = model.openFolders
                _ = model.ignored
                return model.tree
            }
        }

        let a = UUID(), b = UUID(), c = UUID()
        model.tree = [a, b]

        // One read serves every call until something changes.
        precondition(order().ids == [a, b])
        for _ in 0..<500 { precondition(order().index(of: b) == 1) }
        precondition(reads == 1)
        precondition(order().index(of: c) == nil && !order().contains(c))

        // A move is seen by the very next call.
        model.tree = [b, a]
        precondition(order().ids == [b, a] && order().index(of: a) == 1)
        precondition(reads == 2)

        // An in-place change (an insert, as a folder toggle does) counts too, and so does each
        // change after that: the entry is watched again every time it is rebuilt.
        model.tree.append(c)
        precondition(order().count == 3 && reads == 3)
        model.openFolders.insert(UUID())
        _ = order()
        precondition(reads == 4)
        model.openFolders.removeAll()
        _ = order()
        precondition(reads == 5)

        // A value the read did not observe, or one it never read, keeps the entry.
        model.ignored += 1
        model.otherTree = [c]
        _ = order()
        precondition(reads == 5)

        // Spaces are kept apart: a change only drops the spaces that read it.
        var otherReads = 0
        func other() -> ExtensionTabOrder {
            cache.order(for: otherSpace) {
                otherReads += 1
                return model.otherTree
            }
        }
        precondition(other().ids == [c] && otherReads == 1)
        model.tree = [a]
        precondition(order().ids == [a] && reads == 6)
        precondition(other().ids == [c] && otherReads == 1)
        model.otherTree = []
        precondition(other().ids.isEmpty && otherReads == 2)

        // The first position wins if an id ever appears twice, as `firstIndex(of:)` did.
        precondition(ExtensionTabOrder([a, b, a]).index(of: a) == 0)
        precondition(ExtensionTabOrder.empty.count == 0)

        print("ExtensionTabOrderCheck passed")
    }
}
