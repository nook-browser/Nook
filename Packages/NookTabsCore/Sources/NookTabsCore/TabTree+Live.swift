// Licensed under GPL-3.0. See LICENSE.
import Foundation

/// One page a live folder's source reports.
public struct LivePage: Hashable, Sendable {
    public var url: URL
    public var title: String

    public init(url: URL, title: String) {
        self.url = url
        self.title = title
    }
}

extension TabTree {
    /// Brings a live folder's tabs in line with `pages`. Missing pages are added at the top in
    /// source order and the rest retitled. A tab the source owns (`owns`) but no longer reports
    /// is removed, as is a second tab for one page; tabs in `keeping` (open pages) wait for a
    /// later pass. URLs in `dismissed` are not added. Tabs the source does not own are left alone.
    @discardableResult
    public mutating func reconcileLive(
        _ folderID: UUID, with pages: [LivePage], dismissed: Set<URL> = [], keeping: Set<UUID> = [],
        owns: (URL) -> Bool, now: Date = Date()
    ) throws -> Change {
        guard item(folderID)?.isFolder == true else { throw TreeError.missingItem }
        let parent = Parent.folder(itemID: folderID)
        let titles = Dictionary(pages.map { ($0.url, $0.title) }, uniquingKeysWith: { first, _ in first })
        var change = Change()
        var present: Set<URL> = []
        for child in children(of: parent) {
            guard let url = child.url, owns(url) else { continue }
            if let title = titles[url], present.insert(url).inserted {
                change.merge(try setPageTitle(child.id, title, now: now))
            } else if !keeping.contains(child.id) {
                change.merge(try close(child.id, now: now).change)
            }
        }
        var after: UUID?
        for page in pages where !dismissed.contains(page.url) && present.insert(page.url).inserted {
            let id = UUID()
            change.merge(try createTab(id: id, url: page.url, title: page.title, in: parent, after: after, now: now))
            after = id
        }
        return change
    }
}
