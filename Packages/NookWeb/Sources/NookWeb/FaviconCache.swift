// Licensed under GPL-3.0. See LICENSE.
//
//  FaviconCache.swift
//  Nook
//
//  Global favicon cache, shared across profiles by design to raise the hit rate and avoid
//  duplicate downloads. Memory LRU of 200 entries plus a disk cache at
//  ~/Library/Caches/FaviconCache/{host}.png that survives relaunch. Disk I/O runs on a
//  background queue.
//

import Foundation
import SwiftUI

public final class FaviconCache: @unchecked Sendable {
    public static let shared = FaviconCache()

    public static let maxMemoryEntries = 200

    private struct Entry {
        let nsImage: PlatformImage
        let image: SwiftUI.Image
    }

    private var memory: [String: Entry] = [:]
    /// Each memory icon's main colors, worked out on first ask (`FaviconTint`).
    private var tints: [String: [FaviconTint.Swatch]] = [:]
    /// Insertion order for LRU eviction.
    private var order: [String] = []
    private let lock = NSLock()
    private let queue = DispatchQueue(label: "favicon.cache", attributes: .concurrent)

    public let directory: URL = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = caches.appendingPathComponent("FaviconCache")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    // MARK: - Lookup

    /// Memory cache only, synchronous.
    public func image(for key: String) -> PlatformImage? {
        lock.withLock { memory[key]?.nsImage }
    }

    /// The cached icon's main colors, for lighting a selected favorite; empty for a gray or
    /// not-yet-cached icon. Worked out once per icon from a 32 px sample.
    public func tint(for key: String) -> [FaviconTint.Swatch] {
        if let known = lock.withLock({ tints[key] }) { return known }
        guard let image = image(for: key), let cg = image.singlePixelCGImage else { return [] }
        let swatches = FaviconTint.swatches(from: cg)
        lock.withLock { tints[key] = swatches }
        return swatches
    }

    /// Memory cache only, as a SwiftUI image.
    public func swiftUIImage(for key: String) -> SwiftUI.Image? {
        lock.withLock { memory[key]?.image }
    }

    /// Memory first, then disk off the main thread. A disk hit is promoted to memory.
    public func cachedImage(for key: String) async -> PlatformImage? {
        if let hit = image(for: key) { return hit }
        return await withCheckedContinuation { continuation in
            queue.async {
                let image = self.readFromDisk(key)?.inkedFavicon
                if let image { self.insert(Entry(nsImage: image, image: SwiftUI.Image(platformImage: image)), for: key) }
                continuation.resume(returning: image)
            }
        }
    }

    /// Synchronous disk read with promotion to memory. For startup restore of a few visible rows.
    public func imageFromDiskSync(for key: String) -> PlatformImage? {
        guard let image = readFromDisk(key)?.inkedFavicon else { return nil }
        insert(Entry(nsImage: image, image: SwiftUI.Image(platformImage: image)), for: key)
        return image
    }

    /// How long a stored favicon is trusted before a visit fetches it again.
    public static let maxAge: TimeInterval = 24 * 60 * 60

    /// True when the disk copy is older than `maxAge`. Memory-only entries (private pages) are never stale.
    public func isStale(_ key: String) async -> Bool {
        let url = fileURL(key)
        return await withCheckedContinuation { continuation in
            queue.async {
                let modified = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
                continuation.resume(returning: modified.map { -$0.timeIntervalSinceNow > Self.maxAge } ?? false)
            }
        }
    }

    // MARK: - Store

    /// Stores in memory and writes a PNG to disk.
    public func store(_ image: PlatformImage, for key: String) {
        store(image, for: key, toDisk: true)
    }

    /// Memory keeps the drawn form (inked if black and white); disk keeps the site's original.
    func store(_ image: PlatformImage, for key: String, toDisk: Bool) {
        let shown = image.inkedFavicon
        insert(Entry(nsImage: shown, image: SwiftUI.Image(platformImage: shown)), for: key)
        guard toDisk else { return }
        // PNG encoding is CPU work, not I/O; do it on the caller.
        guard let png = image.pngData() else { return }
        let url = fileURL(key)
        queue.async(flags: .barrier) {
            try? png.write(to: url)
        }
    }

    // MARK: - Maintenance

    public func clear() {
        lock.withLock {
            memory.removeAll()
            order.removeAll()
        }
        let dir = directory
        queue.async(flags: .barrier) {
            try? FileManager.default.removeItem(at: dir)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    /// Entry counts in memory and on disk.
    public func stats() -> (memory: Int, disk: Int) {
        let memoryCount = lock.withLock { memory.count }
        let diskCount = (try? FileManager.default.contentsOfDirectory(atPath: directory.path).count) ?? 0
        return (memoryCount, diskCount)
    }

    /// Keys currently in memory.
    public var memoryKeys: [String] {
        lock.withLock { Array(memory.keys) }
    }

    // MARK: - Private

    private func insert(_ entry: Entry, for key: String) {
        var evicted: [String] = []
        lock.withLock {
            memory[key] = entry
            tints[key] = nil
            order.removeAll { $0 == key }
            order.append(key)
            if memory.count > Self.maxMemoryEntries {
                let count = memory.count - Self.maxMemoryEntries + 20
                evicted = Array(order.prefix(count))
                for old in evicted { memory.removeValue(forKey: old) }
                order.removeFirst(min(count, order.count))
            }
        }
        guard !evicted.isEmpty else { return }
        let urls = evicted.map(fileURL)
        queue.async(flags: .barrier) {
            for url in urls { try? FileManager.default.removeItem(at: url) }
        }
    }

    private func fileURL(_ key: String) -> URL {
        directory.appendingPathComponent("\(key).png")
    }

    private func readFromDisk(_ key: String) -> PlatformImage? {
        guard let data = try? Data(contentsOf: fileURL(key)) else { return nil }
        return PlatformImage(data: data)
    }
}
