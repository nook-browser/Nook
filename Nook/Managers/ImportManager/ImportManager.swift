// Licensed under GPL-3.0. See LICENSE.
//
//  ImportManager.swift
//  Nook
//
//  Created by Maciek Bagiński on 29/09/2025.
//

import Foundation
import Combine
import SwiftUI

class ImportManager: ObservableObject {
    
    func importArcSidebarData() async -> ArcImportResult {
        guard let data = try? Data(contentsOf: arcDirectory.appendingPathComponent("StorableSidebar.json")),
              var result = try? parseArcSidebarData(data) else { return ArcImportResult() }
        if let routes = try? Data(contentsOf: arcDirectory.appendingPathComponent("StorableLinkRouting.json")) {
            result.routing = parseArcLinkRouting(routes)
        }
        if let archived = try? Data(contentsOf: arcDirectory.appendingPathComponent("StorableArchiveItems.json")) {
            result.archive = parseArcArchive(archived)
        }
        // Chromium's Local State names each profile directory.
        let state = (try? Data(contentsOf: arcDirectory.appendingPathComponent("User Data/Local State")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let cache = (state?["profile"] as? [String: Any])?["info_cache"] as? [String: Any] ?? [:]
        for (directory, info) in cache {
            guard let name = (info as? [String: Any])?["name"] as? String else { continue }
            result.profileNames[directory == "Default" ? "default" : directory] = name
        }
        return result
    }

    /// Web Store extensions enabled in any Arc profile, described from the copy Arc keeps of each.
    func arcExtensions() -> [ExtensionOffer] {
        let userData = arcDirectory.appendingPathComponent("User Data")
        let profiles = ((try? FileManager.default.contentsOfDirectory(atPath: userData.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }.sorted()
            .map { userData.appendingPathComponent($0) }
        let ids = parseChromiumExtensionIDs(profiles.flatMap { profile in
            ["Secure Preferences", "Preferences"].compactMap { try? Data(contentsOf: profile.appendingPathComponent($0)) }
        })
        return ids.compactMap { id in profiles.lazy.compactMap { Self.chromiumExtension(id, in: $0) }.first }
    }

    /// The newest unpacked copy of a store extension in a Chromium profile, `Extensions/<id>/<version>_<n>`.
    private static func chromiumExtension(_ id: String, in profile: URL) -> ExtensionOffer? {
        let directory = profile.appendingPathComponent("Extensions").appendingPathComponent(id)
        func version(_ folder: String) -> String { String(folder.prefix { $0 != "_" }) }
        let folders = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .sorted { ExtensionVersion.isNewer(version($0), than: version($1)) }
        for folder in folders {
            let root = directory.appendingPathComponent(folder)
            guard let data = try? Data(contentsOf: root.appendingPathComponent("manifest.json")),
                  let manifest = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let name = manifest["name"] as? String
            else { continue }
            return ExtensionOffer(
                id: id,
                name: ExtensionManager.resolveLocaleString(name, in: root) ?? name,
                version: manifest["version"] as? String ?? "",
                icon: ExtensionManager.findExtensionIcon(in: root, manifest: manifest).flatMap(NSImage.init(contentsOfFile:)),
                package: .store(.chrome)
            )
        }
        return nil
    }

    /// Arc's member card, with the person's Arc name added, as a JSON object.
    func arcMembershipCard() -> Data? {
        guard let data = try? Data(contentsOf: arcDirectory.appendingPathComponent("StorableMembershipCard.json")),
              var card = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let auth = (try? Data(contentsOf: arcDirectory.appendingPathComponent("StorableAuthState.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        let user = (auth?["session"] as? [String: Any])?["user"] as? [String: Any]
        if let name = user?["name"] as? String { card["name"] = name }
        return try? JSONSerialization.data(withJSONObject: card, options: [.prettyPrinted, .sortedKeys])
    }

    func importDiaData() async -> DiaImportResult {
        let fileURL = getDiaFileURL()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return DiaImportResult(favoriteTabs: [], windowTabs: [])
        }

        do {
            let result = try parseDiaData(from: fileURL)
            return result
        } catch {
            return DiaImportResult(favoriteTabs: [], windowTabs: [])
        }
    }

    func checkSafariExport(at directoryURL: URL) -> SafariExportContents? {
        return validateSafariExport(at: directoryURL)
    }

    func importSafariData(from directoryURL: URL, importBookmarks: Bool, importHistory: Bool) async -> SafariImportResult {
        do {
            let result = try parseSafariExport(from: directoryURL, importBookmarks: importBookmarks, importHistory: importHistory)
            return result
        } catch {
            return SafariImportResult(bookmarks: [], history: [])
        }
    }

    private var arcDirectory: URL {
        URL(fileURLWithPath: NSString(string: "~/Library/Application Support/Arc").expandingTildeInPath)
    }

    private func getDiaFileURL() -> URL {
        URL(fileURLWithPath: NSString(string: "~/Library/Application Support/Dia/StorableProfileContainers.json")
            .expandingTildeInPath
        )
    }
}
