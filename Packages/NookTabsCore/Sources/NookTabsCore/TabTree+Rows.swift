// Licensed under GPL-3.0. See LICENSE.
import Foundation

extension TabTree {
    /// Sidebar rows for one space: the pinned section, then the tabs section. The children of a
    /// folder or a parent tab appear only while it is open.
    public func visibleRows(space spaceID: UUID, openFolders: Set<UUID>) -> [Row] {
        let groups = childrenByParent()
        var rows: [Row] = []
        func walk(_ parent: Parent, depth: Int, section: SidebarSection) {
            for child in groups[parent] ?? [] {
                let hasChildren = !child.isFolder && groups[.folder(itemID: child.id)] != nil
                rows.append(Row(item: child, depth: depth, section: section, hasChildren: hasChildren))
                if child.isFolder || hasChildren, openFolders.contains(child.id) {
                    walk(.folder(itemID: child.id), depth: depth + 1, section: section)
                }
            }
        }
        walk(.pinned(spaceID: spaceID), depth: 0, section: .pinned)
        walk(.tabs(spaceID: spaceID), depth: 0, section: .tabs)
        return rows
    }

    /// Where a drop lands, given the visible rows of one section.
    ///
    /// `index` is the insertion slot (0...rows.count): the drop goes before `rows[index]`, at the
    /// same level as that row. `intoFolder` means the pointer is over the middle of the folder
    /// row at `index`, and the drop becomes that folder's first child. `dragged` is excluded as
    /// a neighbor so dropping an item next to itself keeps its place.
    public func dropTarget(section: Parent, rows: [Row], index: Int, intoFolder: Bool, dragged: UUID?) -> (parent: Parent, after: UUID?) {
        let slot = max(0, min(index, rows.count))
        // A slot on the dragged item or inside its own subtree keeps the item where it is.
        if let dragged, let moving = item(dragged), slot < rows.count {
            let target = rows[slot].item.id
            if target == dragged || folderChain(of: target)?.folders.contains(dragged) == true {
                let siblings = children(of: moving.parent)
                let position = siblings.firstIndex(where: { $0.id == dragged }) ?? 0
                return (moving.parent, position > 0 ? siblings[position - 1].id : nil)
            }
        }
        if intoFolder, slot < rows.count, rows[slot].item.isFolder, rows[slot].item.id != dragged {
            return (.folder(itemID: rows[slot].item.id), nil)
        }
        let parent = slot < rows.count ? rows[slot].item.parent : section
        let siblings = children(of: parent).filter { $0.id != dragged }
        guard slot < rows.count, let position = siblings.firstIndex(where: { $0.id == rows[slot].item.id }) else {
            return (parent, siblings.last?.id)
        }
        return (parent, position > 0 ? siblings[position - 1].id : nil)
    }
}
