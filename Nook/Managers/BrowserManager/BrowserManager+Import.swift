// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserManager+Import.swift
//  Nook
//

import Foundation
import NookTabsCore
import NookWeb
import SwiftUI

extension BrowserManager {
    /// Import Data from arc
    func importArcData() async {
        let result = await importManager.importArcSidebarData()
        guard let window = importWindow else { return }
        // A first launch starts with one empty space; next to Arc's spaces it is only an extra.
        let emptyBefore = tabs.orderedSpaces.map(\.id).filter { tabs.items(inSpace: $0).isEmpty }

        var lastSpace = tabs.orderedSpaces.last?.id
        var firstImported: UUID?
        for space in result.spaces {
            guard let spaceID = tabs.createSpace(
                name: space.title, icon: space.emoji ?? "person.fill",
                accentHex: space.accentHex ?? "#7C7C7C", after: lastSpace
            ) else { continue }
            lastSpace = spaceID
            firstImported = firstImported ?? spaceID

            importArcNodes(space.favorites, into: .favorites(spaceID: spaceID), after: nil)
            importArcNodes(space.pinned, into: .pinned(spaceID: spaceID), after: nil)
            importArcNodes(space.unpinned, into: .tabs(spaceID: spaceID), after: nil)
        }

        guard let firstImported else { return }
        if window.spaceID.map({ emptyBefore.contains($0) }) ?? true {
            tabs.setSpace(firstImported, in: window)
        }
        emptyBefore.forEach { tabs.deleteSpace($0) }
    }

    /// Adds Arc's items under `parent` in Arc's order, folders nested, without loading pages.
    /// Nook has no saved split, so a split's tabs go side by side where the split was.
    /// Returns the last item added, for the next sibling to follow.
    @discardableResult
    private func importArcNodes(_ nodes: [ArcNode], into parent: Parent, after first: UUID?) -> UUID? {
        var previous = first
        for node in nodes {
            switch node {
            case .tab(let string, let pageTitle, let customTitle):
                guard let url = URL(string: string), url.scheme != nil,
                      let id = tabs.importTab(url: url, title: pageTitle, in: parent, after: previous) else { continue }
                if let customTitle { tabs.rename(id, customTitle) }
                previous = id
            case .folder(let title, let children):
                guard let id = tabs.createFolder(title: title, in: parent, after: previous) else { continue }
                importArcNodes(children, into: .folder(itemID: id), after: nil)
                previous = id
            case .split(let halves):
                previous = importArcNodes(halves, into: parent, after: previous) ?? previous
            }
        }
        return previous
    }

    func importDiaData() async {
        let result = await importManager.importDiaData()
        guard let window = importWindow, let spaceID = importSpaceID(window) else { return }

        importTabs(result.favoriteTabs.map(\.url), into: .favorites(spaceID: spaceID), window: window)
        importTabs(result.windowTabs.map(\.url), into: .tabs(spaceID: spaceID), window: window)
    }

    func importSafariData(from directoryURL: URL, importBookmarks: Bool, importHistory: Bool) async {
        let result = await importManager.importSafariData(
            from: directoryURL,
            importBookmarks: importBookmarks,
            importHistory: importHistory
        )

        if !result.bookmarks.isEmpty, let window = importWindow, let spaceID = importSpaceID(window) {
            let favoritesBookmarks = result.bookmarks.filter { $0.folder == "Favorites" }
            let otherBookmarks = result.bookmarks.filter { $0.folder != "Favorites" }

            importTabs(favoritesBookmarks.map(\.url), into: .favorites(spaceID: spaceID), window: window)

            var folderGroups: [String: [SafariBookmark]] = [:]
            var unfolderedBookmarks: [SafariBookmark] = []
            for bookmark in otherBookmarks {
                if let folder = bookmark.folder, !folder.isEmpty {
                    folderGroups[folder, default: []].append(bookmark)
                } else {
                    unfolderedBookmarks.append(bookmark)
                }
            }

            importTabs(unfolderedBookmarks.map(\.url), into: .tabs(spaceID: spaceID), window: window)
            for (folderName, bookmarks) in folderGroups.sorted(by: { $0.key > $1.key }) {
                guard let folderID = tabs.createFolder(title: folderName, in: .pinned(spaceID: spaceID), after: nil) else { continue }
                importTabs(bookmarks.map(\.url), into: .folder(itemID: folderID), window: window)
            }
        }

        if !result.history.isEmpty {
            let profileId = historyManager.currentProfileId
            historyManager.importVisits(result.history.compactMap { entry in
                guard let url = URL(string: entry.url) else { return nil }
                return HistoryVisit(url: url, title: entry.title, timestamp: entry.visitDate,
                                    tabId: nil, profileId: profileId)
            })
        }
    }

    // MARK: - Helpers

    /// A regular window: intents need one to pick the main tree. Imports never go to a private
    /// window. Onboarding imports run before any browser window registers; an unregistered window
    /// state still targets the main tree, and background opens never select in it.
    private var importWindow: BrowserWindowState? {
        if let active = windowRegistry?.activeWindow, !active.isIncognito { return active }
        return tabs.regularWindows.first ?? BrowserWindowState()
    }

    private func importSpaceID(_ window: BrowserWindowState) -> UUID? {
        window.spaceID ?? tabs.orderedSpaces.first?.id
    }

    /// Adds tabs under `parent` in source order without loading pages or changing selection.
    /// `open` inserts at the top, so the list goes in reversed.
    private func importTabs(_ urls: [String], into parent: Parent, window: BrowserWindowState) {
        for string in urls.reversed() {
            guard let url = URL(string: string), url.scheme != nil else { continue }
            tabs.open(url: url, in: window, placement: .background, parent: parent)
        }
    }
}
