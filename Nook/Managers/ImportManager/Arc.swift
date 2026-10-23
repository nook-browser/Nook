// Licensed under GPL-3.0. See LICENSE.
//
//  Arc.swift
//  Nook
//
//  Created by Maciek Bagiński on 29/09/2025.
//

import Foundation

// MARK: - Arc Models
struct ArcImportResult {
    var spaces: [ArcSpace] = []
    /// Favorites by Arc profile: "default" or the profile's directory name ("Profile 1").
    var favorites: [String: [ArcNode]] = [:]
    /// Profile names the person gave in Arc, by the same keys.
    var profileNames: [String: String] = [:]
}

struct ArcSpace {
    let title: String
    let emoji: String?
    let accentHex: String?
    let profile: String
    let pinned: [ArcNode]
    let unpinned: [ArcNode]
}

indirect enum ArcNode: Equatable {
    /// `customTitle` is a name the person (or Arc's tidy titles) gave the tab.
    case tab(url: String, title: String?, customTitle: String?)
    case folder(title: String, children: [ArcNode])
}

// MARK: - Parser

/// Reads `StorableSidebar.json` in sidebar order. Items, spaces and favorites containers are
/// flat `[key, value, key, value]` arrays; the tree comes from each item's `childrenIds`.
func parseArcSidebarData(_ data: Data) throws -> ArcImportResult {
    let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let containers = (root?["sidebar"] as? [String: Any])?["containers"] as? [[String: Any]] ?? []
    guard let container = containers.first(where: { $0["spaces"] != nil }) else { return ArcImportResult() }

    var items: [String: [String: Any]] = [:]
    for case let item as [String: Any] in list(container["items"]) {
        if let id = item["id"] as? String { items[id] = item }
    }

    var visited = Set<String>()
    func nodes(_ ids: [String]) -> [ArcNode] {
        ids.flatMap { id -> [ArcNode] in
            guard visited.insert(id).inserted, let item = items[id],
                  let data = item["data"] as? [String: Any] else { return [] }
            let name = (item["title"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            let children = nodes(item["childrenIds"] as? [String] ?? [])
            if let tab = data["tab"] as? [String: Any] {
                let url = [tab["savedURL"], tab["currentURL"]].lazy.compactMap { $0 as? String }.first { !$0.isEmpty }
                guard let url else { return children }
                let saved = tab["savedTitle"] as? String
                // A tab's own children follow it.
                return [.tab(url: url, title: saved, customTitle: name == saved ? nil : name)] + children
            }
            if data["list"] != nil { return [.folder(title: name ?? "", children: children)] }
            // Split views and any grouping Nook has no counterpart for keep their tabs in place.
            return children
        }
    }
    func contents(_ containerID: String?) -> [ArcNode] {
        guard let containerID, let item = items[containerID] else { return [] }
        return nodes(item["childrenIds"] as? [String] ?? [])
    }

    var result = ArcImportResult()
    // Some files keep favorites only in the sync mirror.
    let mirror = (((root?["sidebarSyncState"] as? [String: Any])?["container"] as? [String: Any])?["value"] as? [String: Any])
    let favorites = pairs(container["topAppsContainerIDs"])
    for (profile, containerID) in favorites.isEmpty ? pairs(mirror?["topAppsContainerIDs"]) : favorites {
        result.favorites[profile, default: []] += contents(containerID)
    }
    for case let space as [String: Any] in list(container["spaces"]) {
        let sections = Dictionary(pairs(space["containerIDs"] ?? space["newContainerIDs"]), uniquingKeysWith: { a, _ in a })
        let custom = space["customInfo"] as? [String: Any]
        let midTone = ((custom?["windowTheme"] as? [String: Any])?["primaryColorPalette"] as? [String: Any])?["midTone"]
        result.spaces.append(ArcSpace(
            title: space["title"] as? String ?? "",
            emoji: (custom?["iconType"] as? [String: Any])?["emoji_v2"] as? String,
            accentHex: hex(midTone as? [String: Any]),
            profile: space["profile"].flatMap(key) ?? "default",
            pinned: contents(sections["pinned"]),
            unpinned: contents(sections["unpinned"])
        ))
    }
    return result
}

/// Objects from an `[id, object, id, object]` array, or from an object keyed by id.
private func list(_ value: Any?) -> [Any] {
    (value as? [Any]) ?? (value as? [String: Any]).map { Array($0.values) } ?? []
}

/// Chrome Web Store ids of the extensions a Chromium profile has enabled, from its
/// `Preferences` and `Secure Preferences` files. Arc's own and Chromium's built-in ones are left out.
func parseChromiumExtensionIDs(_ preferenceFiles: [Data]) -> [String] {
    var ids: [String] = []
    for data in preferenceFiles {
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let settings = (root?["extensions"] as? [String: Any])?["settings"] as? [String: Any] ?? [:]
        for (id, value) in settings.sorted(by: { $0.key < $1.key }) {
            guard let entry = value as? [String: Any], entry["from_webstore"] as? Bool == true,
                  (entry["disable_reasons"] as? [Any] ?? []).isEmpty, entry["state"] as? Int != 0,
                  !ids.contains(id) else { continue }
            ids.append(id)
        }
    }
    return ids
}

/// `[key, id, key, id]`, as in a space's `containerIDs` or `topAppsContainerIDs`.
private func pairs(_ value: Any?) -> [(String, String)] {
    let array = value as? [Any] ?? []
    return stride(from: 0, to: array.count - 1, by: 2).compactMap { i in
        guard let key = key(array[i]), let id = array[i + 1] as? String else { return nil }
        return (key, id)
    }
}

/// A string (`"pinned"`), a tagged object (`{"pinned": {}}`, `{"default": true}`), or a custom
/// profile, keyed by its directory (`{"custom": {"_0": {"directoryBasename": "Profile 1"}}}`).
private func key(_ value: Any) -> String? {
    if let string = value as? String { return string }
    guard let tagged = value as? [String: Any], let tag = tagged.keys.first else { return nil }
    let profile = (tagged["custom"] as? [String: Any])?["_0"] as? [String: Any]
    return profile?["directoryBasename"] as? String ?? tag
}

/// Arc stores extended sRGB, so components can fall outside 0...1.
private func hex(_ color: [String: Any]?) -> String? {
    guard let color, let r = color["red"] as? Double, let g = color["green"] as? Double,
          let b = color["blue"] as? Double else { return nil }
    let byte = { (v: Double) in Int((min(max(v, 0), 1) * 255).rounded()) }
    return String(format: "#%02X%02X%02X", byte(r), byte(g), byte(b))
}
