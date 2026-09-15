//
//  BrowserManager+Import.swift
//  Nook
//

import Foundation
import SwiftUI

extension BrowserManager {
    /// Import Data from arc
    func importArcData() async {
        let result = await importManager.importArcSidebarData()

        for space in result.spaces {
            #if DEBUG
            print("========== \(space.title)")
            #endif
            self.tabManager.createSpace(name: space.title, icon: space.emoji ?? "person.fill")

            guard
                let createdSpace = self.tabManager.spaces.first(where: {
                    $0.name == space.title
                })
            else {
                continue
            }

            for tab in space.unpinnedTabs {
                #if DEBUG
                print("Unpinned tab - \(tab.title)")
                #endif
                self.tabManager.createNewTab(url: tab.url, in: createdSpace)
            }

            for tab in space.pinnedTabs {
                #if DEBUG
                print("Pinned tab - \(tab.title)")
                #endif
                let newtab = self.tabManager.createNewTab(url: tab.url, in: createdSpace)
                self.tabManager.pinTabToSpace(newtab, spaceId: createdSpace.id)
            }
            for folder in space.folders {
                #if DEBUG
                print("Folder - \(folder.title)")
                #endif
                let newFolder = self.tabManager.createFolder(
                    for: createdSpace.id, name: folder.title)

                for tab in folder.tabs {
                    let newtab = self.tabManager.createNewTab(url: tab.url, in: createdSpace)
                    self.tabManager.moveTabToFolder(tab: newtab, folderId: newFolder.id)
                }
            }
        }
        for topTab in result.topTabs {
            #if DEBUG
            print("TopTab - \(topTab.title)")
            #endif
            let tab = self.tabManager.createNewTab(
                url: topTab.url, in: self.tabManager.spaces.first!)
            self.tabManager.addToEssentials(tab)
        }
    }

    func importDiaData() async {
        let result = await importManager.importDiaData()

        guard let defaultSpace = self.tabManager.spaces.first else { return }

        for tab in result.favoriteTabs {
            #if DEBUG
            print("Dia Favorite - \(tab.title)")
            #endif
            let newTab = self.tabManager.createNewTab(url: tab.url, in: defaultSpace)
            self.tabManager.addToEssentials(newTab)
        }

        for tab in result.windowTabs {
            #if DEBUG
            print("Dia Tab - \(tab.title)")
            #endif
            self.tabManager.createNewTab(url: tab.url, in: defaultSpace)
        }
    }

    func importSafariData(from directoryURL: URL, importBookmarks: Bool, importHistory: Bool) async {
        let result = await importManager.importSafariData(
            from: directoryURL,
            importBookmarks: importBookmarks,
            importHistory: importHistory
        )

        guard let defaultSpace = self.tabManager.spaces.first else { return }

        if !result.bookmarks.isEmpty {
            let favoritesBookmarks = result.bookmarks.filter { $0.folder == "Favorites" }
            let otherBookmarks = result.bookmarks.filter { $0.folder != "Favorites" }

            for bookmark in favoritesBookmarks {
                let tab = self.tabManager.createNewTab(url: bookmark.url, in: defaultSpace)
                self.tabManager.addToEssentials(tab)
            }

            var folderGroups: [String: [SafariBookmark]] = [:]
            var unfolderedBookmarks: [SafariBookmark] = []

            for bookmark in otherBookmarks {
                if let folder = bookmark.folder, !folder.isEmpty {
                    folderGroups[folder, default: []].append(bookmark)
                } else {
                    unfolderedBookmarks.append(bookmark)
                }
            }

            for (folderName, bookmarks) in folderGroups {
                let newFolder = self.tabManager.createFolder(for: defaultSpace.id, name: folderName)
                for bookmark in bookmarks {
                    let tab = self.tabManager.createNewTab(url: bookmark.url, in: defaultSpace)
                    self.tabManager.moveTabToFolder(tab: tab, folderId: newFolder.id)
                }
            }

            for bookmark in unfolderedBookmarks {
                self.tabManager.createNewTab(url: bookmark.url, in: defaultSpace)
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
}
