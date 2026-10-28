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
    var originalURL: URL
    var path: String
    var date: Date
    var size: Int64?
    var renamedFrom: String?
}

enum DownloadHistoryStore {
    /// The newest this many; older ones are forgotten, never deleted from disk.
    static let limit = 300

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "Nook", isDirectory: true)
            .appendingPathComponent("Downloads.json")
    }

    static func load() -> [DownloadRecord] {
        guard let data = try? Data(contentsOf: fileURL),
              let records = try? JSONDecoder().decode([DownloadRecord].self, from: data) else { return [] }
        return records.filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Off the main thread; the newest write wins.
    static func save(_ records: [DownloadRecord]) {
        let newest = Array(records.sorted { $0.date > $1.date }.prefix(limit))
        let url = fileURL
        queue.async {
            guard let data = try? JSONEncoder().encode(newest) else { return }
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }

    private static let queue = DispatchQueue(label: "com.gstudios.nook.download-history", qos: .utility)
}
