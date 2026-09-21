// Licensed under GPL-3.0. See LICENSE.
//
//  LegacyDataMigration.swift
//  Nook
//
//  Nook shipped as io.browsewithnook.nook (1.0.x) and com.baingurley.nook (1.1 to 1.2.1) before
//  com.gstudios.nook. Application Support, WebKit's per-space data stores and UserDefaults are all
//  keyed by bundle id, so the first launch under the new id copies them across. Runs before
//  SwiftUI constructs anything, from Main.swift.
//

import Foundation
import OSLog

enum LegacyDataMigration {
    /// Newest first: anyone with both ran the fork after the original.
    static let previousBundleIDs = ["com.baingurley.nook", "io.browsewithnook.nook"]

    private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "Migration")

    static func migrateIfNeeded(
        currentBundleID: String = Bundle.main.bundleIdentifier ?? "Nook",
        library: URL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0],
        defaults: UserDefaults = .standard
    ) {
        let fm = FileManager.default
        let appSupport = library.appendingPathComponent("Application Support", isDirectory: true)
        let webKit = library.appendingPathComponent("WebKit", isDirectory: true)
        let target = appSupport.appendingPathComponent(currentBundleID, isDirectory: true)

        // Anything already under the new id means this ran, or the user started fresh here.
        guard !fm.fileExists(atPath: target.appendingPathComponent("default.store").path),
              !fm.fileExists(atPath: target.appendingPathComponent("Tabs").path)
        else { return }
        guard let old = previousBundleIDs.first(where: {
            fm.fileExists(atPath: appSupport.appendingPathComponent($0).appendingPathComponent("default.store").path)
        }) else { return }

        log.notice("Migrating data from \(old, privacy: .public) to \(currentBundleID, privacy: .public)")
        let source = appSupport.appendingPathComponent(old, isDirectory: true)
        for name in ["default.store", "default.store-shm", "default.store-wal", "Tabs"] {
            copy(source.appendingPathComponent(name), to: target.appendingPathComponent(name))
        }
        copyDataStores(from: webKit.appendingPathComponent(old).appendingPathComponent("WebsiteDataStore"),
                       to: webKit.appendingPathComponent(currentBundleID).appendingPathComponent("WebsiteDataStore"))

        if let domain = defaults.persistentDomain(forName: old) {
            for (key, value) in domain where defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
            log.notice("Copied \(domain.count) defaults from \(old, privacy: .public)")
        }
    }

    /// Caches WebKit refills on demand. Copying them doubles disk use and makes the first launch
    /// after an update wait on hundreds of MB for nothing: measured at 468 MB of NetworkCache in
    /// one space alone. Logins and site data live in the other directories, so those still move.
    private static let regenerableStoreDirectories: Set<String> = ["NetworkCache", "MediaCache"]

    /// Copies each per-space data store, leaving the regenerable caches behind.
    private static func copyDataStores(from: URL, to: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { return }
        guard let stores = try? fm.contentsOfDirectory(at: from, includingPropertiesForKeys: nil) else {
            // Unreadable source: fall back to the whole-directory copy rather than migrating nothing.
            copy(from, to: to)
            return
        }
        var skipped = 0
        for store in stores {
            let target = to.appendingPathComponent(store.lastPathComponent, isDirectory: true)
            guard let children = try? fm.contentsOfDirectory(at: store, includingPropertiesForKeys: nil) else {
                copy(store, to: target)
                continue
            }
            do { try fm.createDirectory(at: target, withIntermediateDirectories: true) } catch { continue }
            for child in children {
                if regenerableStoreDirectories.contains(child.lastPathComponent) {
                    skipped += 1
                    continue
                }
                copy(child, to: target.appendingPathComponent(child.lastPathComponent))
            }
        }
        log.notice("Copied \(stores.count, privacy: .public) data stores, skipped \(skipped, privacy: .public) regenerable caches")
    }

    private static func copy(_ from: URL, to: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path), !fm.fileExists(atPath: to.path) else { return }
        do {
            try fm.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: from, to: to)
            log.notice("Copied \(from.lastPathComponent, privacy: .public)")
        } catch {
            log.error("Copy of \(from.path, privacy: .public) failed: \(String(describing: error), privacy: .public)")
        }
    }
}
