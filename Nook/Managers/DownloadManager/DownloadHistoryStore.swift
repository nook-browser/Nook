// Licensed under GPL-3.0. See LICENSE.
//
//  DownloadHistoryStore.swift
//  Nook
//
//  Finished downloads, kept across launches so the list reads like Arc's (Today, Yesterday,
//  2 days ago). Only the file's path and where it came from are kept; a file that has since
//  been moved or deleted drops out on the next load.
//

import Foundation

struct DownloadRecord: Codable, Equatable {
    /// Without its query, fragment or credentials: signed links carry tokens there.
    var originalURL: URL
    var path: String
    var date: Date
    var size: Int64?
    var renamedFrom: String?
    /// The profile (data store id) the download came from; nil for records from before profiles.
    var profileID: UUID?
}

/// What the manager knows about one download, reduced to what history needs, so the rules
/// below run without AppKit or WebKit.
struct DownloadSnapshot {
    var originalURL: URL
    var path: String
    var date: Date
    var size: Int64?
    var renamedFrom: String?
    var profileID: UUID?
    var isCompleted: Bool
    /// A private window or the Agent space: nothing about it reaches disk.
    var isPrivate: Bool
}

enum DownloadHistoryStore {
    /// The newest this many; older ones are forgotten, never deleted from disk.
    static let limit = 300

    /// The records worth keeping: finished, not private, query stripped, newest first, capped.
    static func records(from snapshots: [DownloadSnapshot]) -> [DownloadRecord] {
        snapshots
            .filter { $0.isCompleted && !$0.isPrivate }
            .sorted { $0.date > $1.date }
            .prefix(limit)
            .map {
                DownloadRecord(originalURL: strippingQuery($0.originalURL), path: $0.path, date: $0.date,
                               size: $0.size, renamedFrom: $0.renamedFrom, profileID: $0.profileID)
            }
    }

    static func strippingQuery(_ url: URL) -> URL {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url }
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        return parts.url ?? url
    }

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Nook", isDirectory: true)
            .appendingPathComponent("Downloads.json")
    }

    /// Reads the file and checks each path on the store's queue, then calls back on the main queue.
    static func load(completion: @escaping ([DownloadRecord]) -> Void) {
        let url = fileURL
        queue.async {
            var kept: [DownloadRecord] = []
            if let data = try? Data(contentsOf: url),
               let records = try? JSONDecoder().decode([DownloadRecord].self, from: data) {
                // Older files stored the query; drop it on the way in.
                kept = records.filter { FileManager.default.fileExists(atPath: $0.path) }
                    .map { var r = $0; r.originalURL = strippingQuery(r.originalURL); return r }
            }
            DispatchQueue.main.async { completion(kept) }
        }
    }

    /// Off the main thread; the newest write wins.
    static func save(_ snapshots: [DownloadSnapshot]) {
        let newest = records(from: snapshots)
        let url = fileURL
        queue.async {
            guard let data = try? JSONEncoder().encode(newest) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private static let queue = DispatchQueue(label: "com.gstudios.nook.download-history", qos: .utility)
}
