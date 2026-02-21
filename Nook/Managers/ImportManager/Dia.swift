//
//  Dia.swift
//  Nook
//
//  Created by Maciek Bagiński on 19/02/2026.
//

import Foundation

// MARK: - Dia JSON Models

struct DiaProfileContainers: Codable {
    let version: Int
    let containers: [DiaContainer]
}

struct DiaContainer: Codable {
    let tabs: [DiaTab]
    let id: DiaContainerID
}

struct DiaContainerID: Codable {
    let container: DiaContainerType
    let profileID: String
}

struct DiaContainerType: Codable {
    let window: DiaWindowID?
    let favorites: DiaFavorites?

    var isFavorites: Bool { favorites != nil }
    var isWindow: Bool { window != nil }
}

struct DiaWindowID: Codable {
    let _0: String
}

struct DiaFavorites: Codable {}

struct DiaTab: Codable {
    let id: String
    let contents: [DiaTabContent]
    let lastActiveDate: Double?
    let creationDate: Double?
    let referrerID: String?
}

struct DiaTabContent: Codable {
    let variant: DiaTabVariant
}

struct DiaTabVariant: Codable {
    let webContent: DiaWebContent?
}

struct DiaWebContent: Codable {
    let _0: DiaWebContentData
}

struct DiaWebContentData: Codable {
    let url: String
    let title: String?
}

// MARK: - Import Result Models

struct DiaImportResult {
    let favoriteTabs: [DiaImportTab]
    let windowTabs: [DiaImportTab]
}

struct DiaImportTab {
    let id: String
    let title: String
    let url: String
}

// MARK: - Parser

func parseDiaData(from fileURL: URL) throws -> DiaImportResult {
    let data = try Data(contentsOf: fileURL)
    let decoded = try JSONDecoder().decode(DiaProfileContainers.self, from: data)

    var favoriteTabs: [DiaImportTab] = []
    var windowTabs: [DiaImportTab] = []

    for container in decoded.containers {
        let importedTabs = container.tabs.compactMap { tab -> DiaImportTab? in
            guard let content = tab.contents.first,
                  let webContent = content.variant.webContent
            else { return nil }

            let url = webContent._0.url
            guard !url.isEmpty else { return nil }

            return DiaImportTab(
                id: tab.id,
                title: webContent._0.title ?? url,
                url: url
            )
        }

        if container.id.container.isFavorites {
            favoriteTabs.append(contentsOf: importedTabs)
        } else if container.id.container.isWindow {
            windowTabs.append(contentsOf: importedTabs)
        }
    }

    return DiaImportResult(favoriteTabs: favoriteTabs, windowTabs: windowTabs)
}
