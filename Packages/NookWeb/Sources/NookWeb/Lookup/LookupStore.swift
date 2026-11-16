// Licensed under GPL-3.0. See LICENSE.
//
//  LookupStore.swift
//  NookWeb
//
//  Where a lookup lives on disk: `Lookups/<id>/` under the app's support folder, holding
//  `page.html`, `record.json` and the page's images. One folder a lookup, so a page's read
//  access covers its own files only. Foundation only, so `Checks/LookupPageCheck.swift` can
//  compile it.
//

import Foundation

public enum LookupStore {
    private static let pageName = "page.html"
    private static let recordName = "record.json"

    public static func root(in support: URL) -> URL {
        support.appendingPathComponent("Lookups", isDirectory: true)
    }

    public static func folder(for id: UUID, in support: URL) -> URL {
        root(in: support).appendingPathComponent(id.uuidString, isDirectory: true)
    }

    public static func pageURL(for id: UUID, in support: URL) -> URL {
        folder(for: id, in: support).appendingPathComponent(pageName)
    }

    /// The lookup a page belongs to, or nil for anything that is not `Lookups/<id>/page.html`.
    public static func lookupID(ofPage url: URL, in support: URL) -> UUID? {
        guard url.isFileURL else { return nil }
        let page = url.standardizedFileURL
        let folder = page.deletingLastPathComponent()
        guard page.lastPathComponent == pageName,
              folder.deletingLastPathComponent().path == root(in: support).standardizedFileURL.path else { return nil }
        return UUID(uuidString: folder.lastPathComponent)
    }

    /// Saves the record, then the page rendered from it.
    public static func write(_ record: LookupRecord, in support: URL) throws {
        let folder = folder(for: record.id, in: support)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try JSONEncoder().encode(record).write(to: folder.appendingPathComponent(recordName), options: .atomic)
        try Data(LookupPageRenderer.html(record).utf8).write(to: folder.appendingPathComponent(pageName), options: .atomic)
    }

    public static func record(for id: UUID, in support: URL) -> LookupRecord? {
        guard let data = try? Data(contentsOf: folder(for: id, in: support).appendingPathComponent(recordName)) else { return nil }
        return try? JSONDecoder().decode(LookupRecord.self, from: data)
    }

    /// Whether any lookup is on disk at all.
    public static func hasLookups(in support: URL) -> Bool {
        (try? FileManager.default.contentsOfDirectory(atPath: root(in: support).path))?.isEmpty == false
    }

    /// Deletes every lookup folder whose id is not in `ids`. A folder changed since `cutoff` is
    /// left: it belongs to a lookup that started after `ids` was gathered.
    public static func sweep(keeping ids: Set<UUID>, in support: URL, olderThan cutoff: Date) {
        let root = root(in: support)
        guard let folders = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        for folder in folders where UUID(uuidString: folder.lastPathComponent).map(ids.contains) != true {
            let changed = (try? folder.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if changed < cutoff { try? FileManager.default.removeItem(at: folder) }
        }
    }
}
