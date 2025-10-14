//
//  ExtensionStorageManager.swift
//  Nook
//
//  Created by John Fields on 10/14/25.
//  Manages persistent storage for browser extensions via chrome.storage.local API
//

import Foundation
import os.log

/// Manages persistent storage for browser extensions
/// Implements chrome.storage.local API with file-based persistence
@available(macOS 15.4, *)
class ExtensionStorageManager {
    
    // MARK: - Types
    
    struct StorageChange: Codable {
        let oldValue: AnyCodable?
        let newValue: AnyCodable?
    }
    
    enum StorageError: Error {
        case quotaExceeded
        case invalidKey
        case serializationError
        case fileSystemError(Error)
    }
    
    // MARK: - Properties
    
    /// Storage for each extension: extensionId -> [key: value]
    private var stores: [String: [String: Any]] = [:]
    
    /// File manager for persistence
    private let fileManager = FileManager.default
    
    /// Root directory for extension storage
    private let storageDirectory: URL
    
    /// Quota limit per extension (10MB default, matching Chrome)
    private let quotaBytes: Int = 10_485_760 // 10MB
    
    /// Logger
    private let logger = Logger(subsystem: "com.nook.ExtensionStorageManager", category: "Storage")
    
    /// Change listeners per extension
    private var changeListeners: [String: [(changes: [String: StorageChange], area: String) -> Void]] = [:]
    
    /// Lock for thread safety
    private let lock = NSLock()
    
    // MARK: - Initialization
    
    init() {
        // Storage location: ~/Library/Application Support/Nook/Extensions/Storage/
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        storageDirectory = appSupport.appendingPathComponent("Nook/Extensions/Storage")
        
        // Create directory if needed
        try? fileManager.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
        
        logger.info("📦 ExtensionStorageManager initialized at: \(self.storageDirectory.path)")
    }
    
    // MARK: - Public API
    
    /// Get values from storage
    /// - Parameters:
    ///   - extensionId: Extension identifier
    ///   - keys: Keys to retrieve (nil = get all)
    /// - Returns: Dictionary of key-value pairs
    func get(for extensionId: String, keys: [String]?) async -> [String: Any] {
        lock.lock()
        defer { lock.unlock() }
        
        let store = loadStore(for: extensionId)
        
        if let keys = keys {
            // Return only requested keys
            var result: [String: Any] = [:]
            for key in keys {
                if let value = store[key] {
                    result[key] = value
                }
            }
            logger.debug("📖 Get storage for extension \(extensionId): \(keys.count) keys requested, \(result.count) found")
            return result
        } else {
            // Return all keys
            logger.debug("📖 Get all storage for extension \(extensionId): \(store.count) keys")
            return store
        }
    }
    
    /// Set values in storage
    /// - Parameters:
    ///   - extensionId: Extension identifier
    ///   - items: Key-value pairs to store
    /// - Throws: StorageError if quota exceeded or serialization fails
    func set(for extensionId: String, items: [String: Any]) async throws {
        lock.lock()
        defer { lock.unlock() }
        
        var store = loadStore(for: extensionId)
        var changes: [String: StorageChange] = [:]
        
        // Track changes for onChanged event
        for (key, newValue) in items {
            let oldValue = store[key]
            store[key] = newValue
            
            changes[key] = StorageChange(
                oldValue: oldValue.map { AnyCodable($0) },
                newValue: AnyCodable(newValue)
            )
        }
        
        // Check quota before persisting
        let estimatedSize = estimateStorageSize(store)
        guard estimatedSize <= quotaBytes else {
            logger.error("❌ Quota exceeded for extension \(extensionId): \(estimatedSize) bytes")
            throw StorageError.quotaExceeded
        }
        
        // Persist to disk
        do {
            try saveStore(store, for: extensionId)
            logger.info("💾 Saved storage for extension \(extensionId): \(items.count) items, ~\(estimatedSize) bytes")
        } catch {
            logger.error("❌ Failed to save storage for extension \(extensionId): \(error.localizedDescription)")
            throw StorageError.fileSystemError(error)
        }
        
        // Fire onChanged event
        Task { @MainActor in
            await notifyStorageChange(extensionId: extensionId, changes: changes, area: "local")
        }
    }
    
    /// Remove keys from storage
    /// - Parameters:
    ///   - extensionId: Extension identifier
    ///   - keys: Keys to remove
    /// - Throws: StorageError if file system error occurs
    func remove(for extensionId: String, keys: [String]) async throws {
        lock.lock()
        defer { lock.unlock() }
        
        var store = loadStore(for: extensionId)
        var changes: [String: StorageChange] = [:]
        
        for key in keys {
            if let oldValue = store.removeValue(forKey: key) {
                changes[key] = StorageChange(
                    oldValue: AnyCodable(oldValue),
                    newValue: nil
                )
            }
        }
        
        // Only save if we actually removed something
        guard !changes.isEmpty else {
            logger.debug("🗑️ No keys to remove for extension \(extensionId)")
            return
        }
        
        do {
            try saveStore(store, for: extensionId)
            logger.info("🗑️ Removed \(changes.count) keys from storage for extension \(extensionId)")
        } catch {
            logger.error("❌ Failed to remove keys for extension \(extensionId): \(error.localizedDescription)")
            throw StorageError.fileSystemError(error)
        }
        
        // Fire onChanged event
        Task { @MainActor in
            await notifyStorageChange(extensionId: extensionId, changes: changes, area: "local")
        }
    }
    
    /// Clear all storage for an extension
    /// - Parameter extensionId: Extension identifier
    /// - Throws: StorageError if file system error occurs
    func clear(for extensionId: String) async throws {
        lock.lock()
        defer { lock.unlock() }
        
        let store = loadStore(for: extensionId)
        var changes: [String: StorageChange] = [:]
        
        // Track all items as removed
        for (key, oldValue) in store {
            changes[key] = StorageChange(
                oldValue: AnyCodable(oldValue),
                newValue: nil
            )
        }
        
        // Save empty store
        do {
            try saveStore([:], for: extensionId)
            logger.info("🧹 Cleared all storage for extension \(extensionId)")
        } catch {
            logger.error("❌ Failed to clear storage for extension \(extensionId): \(error.localizedDescription)")
            throw StorageError.fileSystemError(error)
        }
        
        // Fire onChanged event
        Task { @MainActor in
            await notifyStorageChange(extensionId: extensionId, changes: changes, area: "local")
        }
    }
    
    /// Get bytes in use for keys
    /// - Parameters:
    ///   - extensionId: Extension identifier
    ///   - keys: Keys to check (nil = all keys)
    /// - Returns: Estimated bytes used
    func getBytesInUse(for extensionId: String, keys: [String]?) async -> Int {
        lock.lock()
        defer { lock.unlock() }
        
        let store = loadStore(for: extensionId)
        
        if let keys = keys {
            var subset: [String: Any] = [:]
            for key in keys {
                if let value = store[key] {
                    subset[key] = value
                }
            }
            return estimateStorageSize(subset)
        } else {
            return estimateStorageSize(store)
        }
    }
    
    // MARK: - Change Notifications
    
    /// Notify extension contexts about storage changes
    /// - Parameters:
    ///   - extensionId: Extension identifier
    ///   - changes: Dictionary of changes
    ///   - area: Storage area name ("local", "sync", "managed")
    @MainActor
    private func notifyStorageChange(extensionId: String, changes: [String: StorageChange], area: String) async {
        logger.debug("📢 Notifying storage changes for extension \(extensionId): \(changes.count) changes")
        
        // Notify via ExtensionManager to fire events in extension contexts
        NotificationCenter.default.post(
            name: NSNotification.Name("ExtensionStorageChanged"),
            object: nil,
            userInfo: [
                "extensionId": extensionId,
                "changes": changes,
                "area": area
            ]
        )
    }
    
    // MARK: - Persistence
    
    /// Load storage from disk for an extension
    /// - Parameter extensionId: Extension identifier
    /// - Returns: Dictionary of stored data
    private func loadStore(for extensionId: String) -> [String: Any] {
        let fileURL = storageDirectory.appendingPathComponent("\(extensionId).json")
        
        guard fileManager.fileExists(atPath: fileURL.path) else {
            logger.debug("📂 No storage file exists for extension \(extensionId)")
            return [:]
        }
        
        do {
            let data = try Data(contentsOf: fileURL)
            let json = try JSONSerialization.jsonObject(with: data, options: [])
            
            guard let store = json as? [String: Any] else {
                logger.error("❌ Invalid storage format for extension \(extensionId)")
                return [:]
            }
            
            logger.debug("📂 Loaded storage for extension \(extensionId): \(store.count) keys")
            return store
        } catch {
            logger.error("❌ Failed to load storage for extension \(extensionId): \(error.localizedDescription)")
            return [:]
        }
    }
    
    /// Save storage to disk for an extension
    /// - Parameters:
    ///   - store: Data to save
    ///   - extensionId: Extension identifier
    /// - Throws: Error if serialization or file write fails
    private func saveStore(_ store: [String: Any], for extensionId: String) throws {
        let fileURL = storageDirectory.appendingPathComponent("\(extensionId).json")
        
        let data = try JSONSerialization.data(withJSONObject: store, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: fileURL, options: .atomic)
    }
    
    /// Estimate storage size in bytes
    /// - Parameter store: Storage dictionary
    /// - Returns: Estimated size in bytes
    private func estimateStorageSize(_ store: [String: Any]) -> Int {
        do {
            let data = try JSONSerialization.data(withJSONObject: store, options: [])
            return data.count
        } catch {
            // Fallback to rough estimate if serialization fails
            return store.keys.reduce(0) { $0 + $1.utf8.count + 50 } // Key + ~50 bytes per value
        }
    }
    
    // MARK: - Cleanup
    
    /// Remove storage file for an extension
    /// - Parameter extensionId: Extension identifier
    func removeStorage(for extensionId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        let fileURL = storageDirectory.appendingPathComponent("\(extensionId).json")
        
        try? fileManager.removeItem(at: fileURL)
        logger.info("🗑️ Removed storage file for extension \(extensionId)")
    }
}

// MARK: - AnyCodable Helper

/// Helper to encode/decode Any types
struct AnyCodable: Codable {
    let value: Any
    
    init(_ value: Any) {
        self.value = value
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dict as [String: Any]:
            try container.encode(dict.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}
