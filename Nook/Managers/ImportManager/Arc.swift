// Licensed under GPL-3.0. See LICENSE.
//
//  Arc.swift
//  Nook
//
//  Created by Maciek Bagiński on 29/09/2025.
//

import Foundation

// MARK: - Arc Models

/// Arc's sidebar as a tree, with spaces and items in Arc's own order.
struct ArcImportResult {
    let spaces: [ArcSpace]

    static let empty = ArcImportResult(spaces: [])
}

struct ArcSpace {
    let title: String
    let emoji: String?
    /// The space's theme color as `#RRGGBB`, nil when the space has no theme.
    let accentHex: String?
    /// Arc keeps favorites per profile; these are the favorites of this space's profile.
    let favorites: [ArcNode]
    let pinned: [ArcNode]
    /// Arc's "Today" tabs.
    let unpinned: [ArcNode]
}

indirect enum ArcNode {
    /// `customTitle` is set only when the tab was renamed in Arc.
    case tab(url: String, pageTitle: String, customTitle: String?)
    case folder(title: String, children: [ArcNode])
    /// Tabs Arc shows side by side.
    case split([ArcNode])
}

// MARK: - Parser

/// Reads `StorableSidebar.json`. Arc stores its maps as flat `[key, value, key, value, ...]`
/// arrays and its tree as `childrenIds`, so the walk starts at each space's containers and
/// follows `childrenIds` in order, which is the sidebar's order.
func parseArcSidebarData(from fileURL: URL) throws -> ArcImportResult {
    let root = try JSONSerialization.jsonObject(with: Data(contentsOf: fileURL)) as? [String: Any]
    let containers = (root?["sidebar"] as? [String: Any])?["containers"] as? [[String: Any]] ?? []
    // One container holds the spaces, and with them every sidebar item.
    guard let main = containers.first(where: { $0["spaces"] != nil }) else { return .empty }
    let tree = ArcTree(items: main["items"])

    var favoritesByProfile: [String: String] = [:]
    for (profile, containerID) in pairs(main["topAppsContainerIDs"]) {
        if let key = profileKey(profile), let containerID = containerID as? String {
            favoritesByProfile[key] = containerID
        }
    }

    let spaces: [ArcSpace] = pairs(main["spaces"]).compactMap { _, value in
        guard let space = value as? [String: Any] else { return nil }
        var containerIDs: [String: String] = [:]
        for (role, id) in pairs(space["containerIDs"]) {
            if let role = role as? String, let id = id as? String { containerIDs[role] = id }
        }
        let customInfo = space["customInfo"] as? [String: Any]
        let iconType = customInfo?["iconType"] as? [String: Any]
        return ArcSpace(
            title: space["title"] as? String ?? "",
            emoji: iconType?["emoji_v2"] as? String,
            accentHex: accentHex(theme: customInfo?["windowTheme"]),
            favorites: tree.nodes(in: profileKey(space["profile"]).flatMap { favoritesByProfile[$0] }),
            pinned: tree.nodes(in: containerIDs["pinned"]),
            unpinned: tree.nodes(in: containerIDs["unpinned"])
        )
    }
    return ArcImportResult(spaces: spaces)
}

private struct ArcTree {
    private var items: [String: [String: Any]] = [:]

    init(items flat: Any?) {
        for (id, item) in pairs(flat) {
            if let id = id as? String, let item = item as? [String: Any] { items[id] = item }
        }
    }

    /// The children of a container, folder or split, in sidebar order.
    func nodes(in containerID: String?) -> [ArcNode] {
        guard let containerID, let children = items[containerID]?["childrenIds"] as? [String] else { return [] }
        return children.compactMap { node($0) }
    }

    private func node(_ id: String) -> ArcNode? {
        guard let item = items[id], let data = item["data"] as? [String: Any] else { return nil }
        let title = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        if let tab = data["tab"] as? [String: Any] {
            guard let url = tab["savedURL"] as? String, !url.isEmpty else { return nil }
            return .tab(url: url, pageTitle: tab["savedTitle"] as? String ?? "", customTitle: title)
        }
        if data["splitView"] != nil {
            let halves = nodes(in: id)
            return halves.isEmpty ? nil : .split(halves)
        }
        if data["list"] != nil {
            return .folder(title: title ?? "", children: nodes(in: id))
        }
        return nil
    }
}

/// Arc's flat `[key, value, key, value, ...]` arrays as pairs.
private func pairs(_ value: Any?) -> [(Any, Any)] {
    guard let flat = value as? [Any] else { return [] }
    return stride(from: 0, to: flat.count - 1, by: 2).map { (flat[$0], flat[$0 + 1]) }
}

/// "default" or the profile's folder name ("Profile 3"). Spaces on one profile share its favorites.
private func profileKey(_ value: Any?) -> String? {
    guard let profile = value as? [String: Any] else { return nil }
    if profile["default"] != nil { return "default" }
    let custom = (profile["custom"] as? [String: Any])?["_0"] as? [String: Any]
    return custom?["directoryBasename"] as? String
}

/// The theme palette's mid tone, the shade Arc tints the space with, as `#RRGGBB`.
private func accentHex(theme: Any?) -> String? {
    let palette = (theme as? [String: Any])?["primaryColorPalette"] as? [String: Any]
    guard let color = palette?["midTone"] as? [String: Any],
          let red = color["red"] as? Double, let green = color["green"] as? Double, let blue = color["blue"] as? Double
    else { return nil }
    func byte(_ value: Double) -> Int { Int((min(max(value, 0), 1) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", byte(red), byte(green), byte(blue))
}
