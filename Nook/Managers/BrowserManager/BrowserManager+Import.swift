//
//  BrowserManager+Import.swift
//  Nook
//

import Foundation
import NookTabsCore
import SwiftUI

extension BrowserManager {
    /// Import Data from arc
    func importArcData() async {
        let result = await importManager.importArcSidebarData()
        guard let window = importWindow, let profileID = importProfileID(window) else { return }

        var lastSpace = tabs.spaces(inProfile: profileID).last?.id
        for space in result.spaces {
            guard let spaceID = tabs.createSpace(
                profileID: profileID, name: space.title, icon: space.emoji ?? "person.fill",
                accentHex: "#7C7C7C", after: lastSpace
            ) else { continue }
            lastSpace = spaceID

            importTabs(space.unpinnedTabs.map(\.url), into: .tabs(spaceID: spaceID), window: window)
            // Folders are opened first so pinned tabs end up above them.
            for folder in space.folders.reversed() {
                guard let folderID = tabs.createFolder(title: folder.title, in: .pinned(spaceID: spaceID), after: nil) else { continue }
                importTabs(folder.tabs.map(\.url), into: .folder(itemID: folderID), window: window)
            }
            importTabs(space.pinnedTabs.map(\.url), into: .pinned(spaceID: spaceID), window: window)
        }

        importTabs(result.topTabs.map(\.url), into: .favorites(profileID: profileID), window: window)
    }

    func importDiaData() async {
        let result = await importManager.importDiaData()
        guard let window = importWindow, let profileID = importProfileID(window),
              let spaceID = tabs.spaces(inProfile: profileID).first?.id else { return }

        importTabs(result.favoriteTabs.map(\.url), into: .favorites(profileID: profileID), window: window)
        importTabs(result.windowTabs.map(\.url), into: .tabs(spaceID: spaceID), window: window)
    }

    func importSafariData(from directoryURL: URL, importBookmarks: Bool, importHistory: Bool) async {
        let result = await importManager.importSafariData(
            from: directoryURL,
            importBookmarks: importBookmarks,
            importHistory: importHistory
        )

        if !result.bookmarks.isEmpty, let window = importWindow, let profileID = importProfileID(window),
           let spaceID = tabs.spaces(inProfile: profileID).first?.id {
            let favoritesBookmarks = result.bookmarks.filter { $0.folder == "Favorites" }
            let otherBookmarks = result.bookmarks.filter { $0.folder != "Favorites" }

            importTabs(favoritesBookmarks.map(\.url), into: .favorites(profileID: profileID), window: window)

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

    private func importProfileID(_ window: BrowserWindowState) -> UUID? {
        window.profileID ?? tabs.tree.orderedProfiles.first?.id
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
