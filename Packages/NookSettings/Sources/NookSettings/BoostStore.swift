// Licensed under GPL-3.0. See LICENSE.
//
//  BoostStore.swift
//  Nook
//
//  Boosts live in Boosts.json under Application Support, read and written off the main thread.
//  A legacy `settings.boosts` defaults blob moves into the file once and stays where it was.
//

import Foundation
import os

public final class BoostStore: @unchecked Sendable {
    public let fileURL: URL
    private let queue = DispatchQueue(label: "com.gstudios.nook.boosts", qos: .utility)

    public init(fileURL: URL = BoostStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    public static var defaultFileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent(Bundle.main.bundleIdentifier ?? "com.gstudios.nook", isDirectory: true)
            .appendingPathComponent("Boosts.json")
    }

    /// The file's Boosts. With no file yet, the legacy blob (if any) is migrated into it.
    /// An existing file always wins, so a migration happens once.
    public static func read(from url: URL, legacy: Data?) -> [Boost] {
        if let data = try? Data(contentsOf: url) {
            if let decoded = try? JSONDecoder().decode(LossyBoosts.self, from: data) { return decoded.boosts }
            // Unreadable: keep a copy before the next save replaces it.
            let backup = url.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.copyItem(at: url, to: backup)
            Logger(subsystem: "com.gstudios.nook", category: "Boosts")
                .error("Boosts.json could not be decoded; copied to \(backup.lastPathComponent, privacy: .public)")
            return []
        }
        guard let legacy, let decoded = try? JSONDecoder().decode(LossyBoosts.self, from: legacy) else { return [] }
        write(decoded.boosts, to: url)
        return decoded.boosts
    }

    public static func write(_ boosts: [Boost], to url: URL) {
        guard let data = try? JSONEncoder().encode(boosts) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    public func load(legacy: Data?) async -> [Boost] {
        await withCheckedContinuation { cont in
            queue.async { cont.resume(returning: Self.read(from: self.fileURL, legacy: legacy)) }
        }
    }

    /// Returns once every queued write has finished; called at quit.
    public func flush() { queue.sync {} }

    /// Writes run in order on one queue, so the last save is the file.
    public func save(_ boosts: [Boost]) {
        queue.async { Self.write(boosts, to: self.fileURL) }
    }
}
