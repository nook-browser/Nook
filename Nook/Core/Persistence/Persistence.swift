//
//  Persistence.swift
//  Nook
//
//  Extracted from BrowserManager.swift
//  Created by AetherAurelia on 12/10/2025.
//

import SwiftUI
import SwiftData
import OSLog

@MainActor
final class Persistence {
    static let shared = Persistence()
    let container: ModelContainer

    // MARK: - Constants
    nonisolated private static let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "Persistence")
    nonisolated private static let storeFileName = "default.store"
    nonisolated private static let backupPrefix = "default_backup_"
    // Backups now use a directory per snapshot: default_backup_<timestamp>/

    static let schema = Schema([
        SpaceEntity.self,
        ProfileEntity.self,
        TabEntity.self,
        FolderEntity.self,
        TabsStateEntity.self,
        HistoryEntity.self,
        ExtensionEntity.self
    ])

    // MARK: - URLs
    nonisolated private static var appSupportURL: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "Nook"
        let dir = base.appendingPathComponent(bundleID, isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            log.error("Failed to create Application Support directory: \(String(describing: error), privacy: .public)")
        }
        return dir
    }

    nonisolated private static var storeURL: URL {
        appSupportURL.appendingPathComponent(storeFileName, isDirectory: false)
    }
    nonisolated private static var backupsDirectoryURL: URL {
        let dir = appSupportURL.appendingPathComponent("Backups", isDirectory: true)
        let fm = FileManager.default
        do { try fm.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            log.error("Failed to create Backups directory: \(String(describing: error), privacy: .public)")
        }
        return dir
    }

    // MARK: - Init
    private init() {
        do {
            let config = ModelConfiguration(url: Self.storeURL)
            container = try ModelContainer(for: Self.schema, configurations: [config])
            Self.log.info("SwiftData container initialized successfully")
        } catch {
            let classification = Self.classifyStoreError(error)
            Self.log.error("SwiftData container initialization failed. Classification=\(String(describing: classification)) error=\(String(describing: error), privacy: .public)")

            switch classification {
            case .schemaMismatch:
                // Attempt a safe reset with optional backup
                var didCreateBackup = false
                do {
                    _ = try Self.createBackup()
                    didCreateBackup = true
                } catch let backupError as PersistenceBackupError {
                    switch backupError {
                    case .storeNotFound:
                        // Treat as recoverable: proceed without a backup
                        Self.log.notice("No existing store to back up. Proceeding with reset.")
                    case .noBackupsFound:
                        // Not expected here but log just in case
                        Self.log.notice("No backups found when attempting to create backup.")
                    }
                } catch {
                    // Unexpected backup failure — continue but warn
                    Self.log.error("Backup attempt failed: \(String(describing: error), privacy: .public). Proceeding with cautious reset.")
                }

                do {
                    try Self.deleteStore()
                    Self.log.notice("Deleted existing store (and sidecars) for schema-mismatch recovery")

                    let config = ModelConfiguration(url: Self.storeURL)
                    container = try ModelContainer(for: Self.schema, configurations: [config])
                    Self.log.notice("Recreated SwiftData container after schema mismatch using configured URL")
                } catch {
                    // On any failure, attempt to restore backup (if one was made) and abort
                    if didCreateBackup {
                        do {
                            try Self.restoreFromBackup()
                            Self.log.fault("Restored store from latest backup after failed recovery attempt")
                        } catch {
                            Self.log.fault("Failed to restore store from backup: \(String(describing: error), privacy: .public)")
                        }
                    }
                    fatalError("Failed to recover from schema mismatch. Aborting to protect data integrity: \(error)")
                }

            case .diskSpace:
                Self.log.fault("Store initialization failed due to insufficient disk space. Not deleting store.")
                fatalError("SwiftData initialization failed due to insufficient disk space: \(error)")

            case .corruption:
                Self.log.fault("Store appears corrupted. Not deleting store. Please investigate backups manually.")
                fatalError("SwiftData initialization failed due to suspected corruption: \(error)")

            case .other:
                Self.log.error("Store initialization failed with unclassified error. Not deleting store.")
                fatalError("SwiftData initialization failed: \(error)")
            }
        }
    }

    // MARK: - Error Classification
    private enum StoreErrorType { case schemaMismatch, diskSpace, corruption, other }
    private static func classifyStoreError(_ error: Error) -> StoreErrorType {
        let ns = error as NSError
        let domain = ns.domain
        let code = ns.code
        let desc = (ns.userInfo[NSLocalizedDescriptionKey] as? String) ?? ns.localizedDescription
        let lower = (desc + " " + domain).lowercased()

        // Disk space: POSIX ENOSPC or clear full-disk wording
        if domain == NSPOSIXErrorDomain && code == 28 { return .diskSpace }
        if lower.contains("no space left") || lower.contains("disk full") { return .diskSpace }

        // Schema mismatch / migration issues
        if lower.contains("migration") || lower.contains("incompatible") || lower.contains("model") || lower.contains("version hash") || lower.contains("mapping model") || lower.contains("schema") {
            return .schemaMismatch
        }

        // Corruption indicators (SQLite/CoreData wording)
        if lower.contains("corrupt") || lower.contains("malformed") || lower.contains("database disk image is malformed") || lower.contains("file is encrypted or is not a database") {
            return .corruption
        }

        return .other
    }

    // MARK: - Backup / Restore
    private enum PersistenceBackupError: Error { case storeNotFound, noBackupsFound }

    // Include SQLite sidecars (-wal/-shm) and back up into a directory
    nonisolated private static func createBackup() throws -> URL {
        try Self.runBlockingOnUtilityQueue {
            let fm = FileManager.default
            let source = Self.storeURL
            guard fm.fileExists(atPath: source.path) else {
                Self.log.info("No existing store found to back up at \(source.path, privacy: .public)")
                throw PersistenceBackupError.storeNotFound
            }

            // Ensure backups root exists
            let backupsRoot = Self.backupsDirectoryURL

            // Create a timestamped backup directory
            let stamp = Self.makeBackupTimestamp()
            let dirName = "\(Self.backupPrefix)\(stamp)"
            let backupDir = backupsRoot.appendingPathComponent(dirName, isDirectory: true)
            try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

            // Gather store + sidecars
            let candidates = [source] + Self.sidecarURLs(for: source)
            for file in candidates {
                if fm.fileExists(atPath: file.path) {
                    let dest = backupDir.appendingPathComponent(file.lastPathComponent, isDirectory: false)
                    do {
                        try fm.copyItem(at: file, to: dest)
                    } catch {
                        Self.log.error("Failed to copy \(file.lastPathComponent, privacy: .public) to backup: \(String(describing: error), privacy: .public)")
                        throw error
                    }
                }
            }

            return backupDir
        }
    }

    // Restore the latest backup directory by copying files back next to the store
    nonisolated private static func restoreFromBackup() throws {
        try Self.runBlockingOnUtilityQueue {
            let fm = FileManager.default
            let root = Self.backupsDirectoryURL
            let contents: [URL]
            do {
                contents = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .isDirectoryKey], options: [.skipsHiddenFiles])
            } catch {
                Self.log.error("Failed to list backups: \(String(describing: error), privacy: .public)")
                throw error
            }

            let backups = contents.filter { url in
                url.lastPathComponent.hasPrefix(Self.backupPrefix) && (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }

            guard !backups.isEmpty else { throw PersistenceBackupError.noBackupsFound }

            // Pick the most recently modified backup directory
            let latest = backups.max { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
                return l < r
            }!

            // Remove current store files first
            try Self.deleteStore()

            // Copy all files from backup dir back to app support dir
            let backupFiles = try fm.contentsOfDirectory(at: latest, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            for file in backupFiles {
                let dest = Self.appSupportURL.appendingPathComponent(file.lastPathComponent, isDirectory: false)
                do { try fm.copyItem(at: file, to: dest) } catch {
                    Self.log.error("Restore copy failed for \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                    throw error
                }
            }

            Self.log.notice("Restored store from backup directory: \(latest.lastPathComponent, privacy: .public)")
        }
    }

    // Deletes the base store and known SQLite sidecars if present
    nonisolated private static func deleteStore() throws {
        try Self.runBlockingOnUtilityQueue {
            let fm = FileManager.default
            let base = Self.storeURL
            let files = [base] + Self.sidecarURLs(for: base)
            for file in files {
                if fm.fileExists(atPath: file.path) {
                    do { try fm.removeItem(at: file) } catch {
                        Self.log.error("Failed to remove \(file.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
                        throw error
                    }
                }
            }
        }
    }

    // MARK: - Helpers
    nonisolated private static func sidecarURLs(for base: URL) -> [URL] {
        // SQLite commonly uses -wal and -shm sidecars when WAL journaling is active
        // Compose manually to append -wal/-shm
        let walURL = URL(fileURLWithPath: base.path + "-wal")
        let shmURL = URL(fileURLWithPath: base.path + "-shm")
        return [walURL, shmURL]
    }

    nonisolated private static func makeBackupTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        return formatter.string(from: Date())
    }

    // Run a throwing closure on a background utility queue and block until it finishes
    nonisolated private static func runBlockingOnUtilityQueue<T>(_ work: @escaping () throws -> T) throws -> T {
        let group = DispatchGroup()
        group.enter()
        var result: Result<T, Error>!
        DispatchQueue.global(qos: .utility).async {
            do { result = .success(try work()) } catch { result = .failure(error) }
            group.leave()
        }
        group.wait()
        switch result! {
        case .success(let value): return value
        case .failure(let error): throw error
        }
    }
}
