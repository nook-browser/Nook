// Licensed under GPL-3.0. See LICENSE.
//
//  TabsController+Sync.swift
//  Nook
//
//  Applies remote sync batches through the same apply(_:) path the tab
//  organizer uses, so selection moves, session teardown, compositor refresh
//  and saving all behave exactly as they do for any other tree change.
//

import Foundation
import NookSync
import NookTabsCore

extension TabsController: CloudSyncEngineDelegate {
    public var syncCurrentTree: TabTree { tree }

    public func syncApplyRemote(_ batch: RemoteBatch) {
        let (merged, changed) = SyncMerge.merge(batch, into: tree)
        guard changed else { return }
        apply(SyncMerge.change(from: tree, to: merged))
    }

    public func syncFetchDidComplete() {
        var repaired = tree
        guard repaired.repair() else { return }
        apply(SyncMerge.change(from: tree, to: repaired))
    }
}
