// Licensed under GPL-3.0. See LICENSE.
//
//  The Archive: tabs closed out of a tabs section, and tabs nobody opened for a while.
//

import Foundation
import NookTabsCore

extension TabsController {
    func saveArchive() {
        store.save(archive)
    }

    /// Files a closed tabs-section subtree. Private windows, the Agent space and read-only runs keep nothing.
    func archiveClosed(_ closed: ClosedEntry, reason: ArchiveReason) {
        guard !isReadOnly, closed.section.spaceID != agentSpaceID,
              let entry = ArchiveEntry(closed: closed, reason: reason) else { return }
        archive.add(entry)
        saveArchive()
    }

    /// Removes entries holding any of `ids` (items that are back in the tree).
    func dropArchived(containing ids: Set<UUID>) {
        if archive.remove(containing: ids) { saveArchive() }
    }

    public func removeFromArchive(_ id: UUID) {
        dropArchived(containing: [id])
    }

    /// Puts an entry back at the top of its space's tabs section (this window's space when that
    /// one is gone) and selects it.
    public func restoreArchived(_ id: UUID, in window: BrowserWindowState) {
        guard let entry = archive.entries.first(where: { $0.id == id }),
              let spaceID = tree.space(entry.spaceID)?.id ?? fallbackSpaceID(for: window),
              perform(.main, "restoreArchived", { try $0.restore(entry.items, toTopOf: spaceID) }) != nil else { return }
        dropArchived(containing: Set(entry.items.map(\.id)))
        dropClosed(containing: Set(entry.items.map(\.id)))
        for host in entry.items where host.isFolder || entry.items.contains(where: { $0.parent == .folder(itemID: host.id) }) {
            openFolder(host.id)
        }
        if let first = entry.items.first(where: { !$0.isFolder }) { select(first.id, in: window) }
    }

    private func fallbackSpaceID(for window: BrowserWindowState) -> UUID? {
        if let id = window.spaceID, id != agentSpaceID { return id }
        return tree.orderedSpaces.first { $0.id != agentSpaceID }?.id
    }

    /// Moves top-level tabs idle past Settings > General > Archive tabs after into the Archive.
    /// Runs at launch, on activation and on window attach; no timer.
    public func archiveIdleTabs(now: Date = Date()) {
        let hours = settings.archiveAfter
        guard hours > 0, !isReadOnly else { return }
        let before = device.lastActive
        let shielded = archiveProtectedIDs()
        for id in archiveShielded.subtracting(shielded) where tree.item(id) != nil { device.stampActive(id, at: now) }
        archiveShielded = shielded
        let roots = device.idleArchiveRoots(in: tree, olderThan: TimeInterval(hours) * 3600, keeping: shielded, now: now)
        if device.lastActive != before { save() }
        for root in roots { remove(root, promotingChildren: false, archiving: .auto) }
    }

    /// Tabs auto-archive must not touch: shown, playing, in picture in picture or capturing.
    private func archiveProtectedIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        // Saved window records count too: at launch they hold the selection before a window attaches.
        for record in device.windows {
            if let spaceID = record.spaceID, let selected = record.selectedItemBySpace[spaceID] { ids.insert(selected) }
            if let split = record.split { ids.formUnion([split.leftItemID, split.rightItemID]) }
        }
        for window in regularWindows {
            if let selected = window.selectedItemID { ids.insert(selected) }
            if let split = window.split { ids.formUnion([split.leftItemID, split.rightItemID]) }
        }
        for page in sessions {
            let capturing = page.primaryWebView.map { $0.cameraCaptureState != .none || $0.microphoneCaptureState != .none } ?? false
            if page.hasPlayingAudio || page.hasPiPActive || capturing || isOnScreen(page.itemID) { ids.insert(page.itemID) }
        }
        return ids
    }
}
