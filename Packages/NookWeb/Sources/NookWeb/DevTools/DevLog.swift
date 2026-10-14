// Licensed under GPL-3.0. See LICENSE.
//
//  DevLog.swift
//  Nook
//
//  A capped log whose entries carry a sequence number, so a reader can ask for what changed
//  since its last read. An update renumbers the entry, so pollers see it again.
//

import Foundation

public protocol DevLogEntry {
    /// Stable for the entry's life; SwiftUI identity.
    var id: Int { get set }
    /// Bumped on every append and update; the cursor DevMCP hands out.
    var seq: Int { get set }
    /// Lets a later event find its entry (a fetch's end finds its start).
    var key: String? { get }
}

public struct DevLog<Entry: DevLogEntry> {
    public let capacity: Int
    public private(set) var items: [Entry] = []
    public private(set) var dropped = 0
    public private(set) var lastSeq = 0

    public init(capacity: Int) {
        self.capacity = capacity
    }

    public mutating func append(_ entry: Entry) {
        var entry = entry
        lastSeq += 1
        entry.id = lastSeq
        entry.seq = lastSeq
        items.append(entry)
        // ponytail: removeFirst is O(n) on a 1,000-entry array; a deque if profiling ever shows it.
        if items.count > capacity {
            dropped += items.count - capacity
            items.removeFirst(items.count - capacity)
        }
    }

    public mutating func update(key: String, _ change: (inout Entry) -> Void) {
        guard let index = items.lastIndex(where: { $0.key == key }) else { return }
        change(&items[index])
        lastSeq += 1
        items[index].seq = lastSeq
    }

    public mutating func updateLast(_ change: (inout Entry) -> Void) {
        guard !items.isEmpty else { return }
        change(&items[items.count - 1])
        lastSeq += 1
        items[items.count - 1].seq = lastSeq
    }

    public func since(_ seq: Int) -> [Entry] {
        items.filter { $0.seq > seq }
    }

    /// Drops entries appended at or before `seq`, keeping later ones.
    public mutating func clear(through seq: Int) {
        items.removeAll { $0.id <= seq }
    }

    /// Keeps `lastSeq`, so a cursor handed out before the clear stays valid.
    public mutating func clear() {
        items.removeAll()
        dropped = 0
    }
}
