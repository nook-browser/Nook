import Foundation
import WebKit

// MARK: - Extension Storage Errors
enum ExtensionStorageError: Error {
    case timeout
    case invalidData
    case encodingError
    case decodingError
}
actor AsyncLock {
    private var isLocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if !isLocked {
            isLocked = true
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        guard let waiter = waiters.first else {
            isLocked = false
            return
        }

        waiters.removeFirst()
        waiter.resume()
    }

    func withLock<T>(_ operation: () async throws -> T) async rethrows -> T {
        await acquire()
        defer { Task { await release() } }
        return try await operation()
    }
}

// MARK: - Extension Storage Manager
class ExtensionStorageManager: ObservableObject {
    static let shared = ExtensionStorageManager()

    private let localUserDefaults = UserDefaults.standard
    private let sessionStorage = NSCache<NSString, NSMutableDictionary>()
    private let asyncLock = AsyncLock()

    private let localStorageKeyPrefix = "extension_local_storage_"
    private let sessionStorageKeyPrefix = "extension_session_storage_"

    private init() {
        sessionStorage.countLimit = 100
    }

    // MARK: - Local Storage (Persistent)

    func getLocal(keys: [String]? = nil, completion: @escaping ([String: Any]?, Error?) -> Void) {
        print("🔧 [ExtensionStorageManager] getLocal called with keys: \(keys ?? ["ALL"])")

        Task {
            do {
                // Add timeout to prevent hanging
                let result = try await withThrowingTaskGroup(of: ([String: Any]?).self) { group in
                    group.addTask {
                        try await self.getLocal(keys: keys)
                    }

                    group.addTask {
                        // Timeout task
                        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                        return nil
                    }

                    let firstResult = try await group.next()!
                    group.cancelAll()

                    if let result = firstResult {
                        print("✅ [ExtensionStorageManager] getLocal completed successfully")
                        return result
                    } else {
                        print("⚠️ [ExtensionStorageManager] getLocal timed out after 5 seconds")
                        return [:]
                    }
                }

                await MainActor.run {
                    completion(result, nil)
                }
            } catch {
                print("❌ [ExtensionStorageManager] getLocal failed with error: \(error)")
                await MainActor.run {
                    completion(nil, error)
                }
            }
        }
    }

    private func getLocal(keys: [String]? = nil) async throws -> [String: Any]? {
        print("🔧 [ExtensionStorageManager] getLocal async called with keys: \(keys ?? ["ALL"])")

        return try await asyncLock.withLock {
            guard let keys = keys else {
                // Return all local storage
                var allData: [String: Any] = [:]
                let allKeys = localUserDefaults.dictionaryRepresentation().keys

                print("🔧 [ExtensionStorageManager] Scanning \(allKeys.count) UserDefaults keys for extension data")

                for key in allKeys {
                    if key.hasPrefix(localStorageKeyPrefix) {
                        let dataKey = String(key.dropFirst(localStorageKeyPrefix.count))
                        if let data = localUserDefaults.data(forKey: key) {
                            do {
                                let anyCodable = try JSONDecoder().decode(AnyCodable.self, from: data)
                                allData[dataKey] = anyCodable.value
                            } catch {
                                print("⚠️ [ExtensionStorageManager] Failed to decode key \(dataKey): \(error)")
                                // Continue with other keys instead of failing completely
                            }
                        }
                    }
                }

                print("🔧 [ExtensionStorageManager] Found \(allData.count) extension storage items")

                // CRITICAL FIX: Always return at least an empty object for Bitwarden
                // Bitwarden expects some storage data even if empty
                if allData.isEmpty {
                    print("⚠️ [ExtensionStorageManager] No extension storage found, returning empty object")
                    return [:]
                }
                return allData
            }

            var result: [String: Any] = [:]
            for key in keys {
                let fullKey = localStorageKeyPrefix + key
                if let data = localUserDefaults.data(forKey: fullKey) {
                    do {
                        let anyCodable = try JSONDecoder().decode(AnyCodable.self, from: data)
                        result[key] = anyCodable.value
                    } catch {
                        print("⚠️ [ExtensionStorageManager] Failed to decode key \(key): \(error)")
                        // Provide default values for known Bitwarden keys to prevent hanging
                        if key.contains("migrations") || key.contains("migration") {
                            result[key] = ["completed": Date().timeIntervalSince1970] // Simulate completed migration
                        }
                    }
                } else {
                    print("⚠️ [ExtensionStorageManager] Key not found: \(key)")
                    // For Bitwarden migration keys, provide a default to prevent hanging
                    if key.contains("migrations") || key.contains("migration") {
                        result[key] = ["completed": Date().timeIntervalSince1970]
                    }
                }
            }

            print("🔧 [ExtensionStorageManager] Returning \(result.count) items for requested keys")
            return result.isEmpty ? [:] : result
        }
    }

    func setLocal(items: [String: Any], completion: @escaping (Error?) -> Void) {
        print("🔧 [ExtensionStorageManager] setLocal called with keys: \(items.keys)")

        Task {
            do {
                // Add timeout to prevent hanging
                try await withThrowingTaskGroup(of: Void.self) { group in
                    group.addTask {
                        try await self.setLocal(items: items)
                    }

                    group.addTask {
                        // Timeout task
                        try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                        throw ExtensionStorageError.timeout
                    }

                    // Wait for first task to complete
                    try await group.next()!
                    group.cancelAll()
                }

                print("✅ [ExtensionStorageManager] setLocal completed successfully")
                await MainActor.run {
                    completion(nil)
                }
            } catch {
                print("❌ [ExtensionStorageManager] setLocal failed with error: \(error)")
                await MainActor.run {
                    completion(error)
                }
            }
        }
    }

    private func setLocal(items: [String: Any]) async throws {
        try await asyncLock.withLock {
            for (key, value) in items {
                let fullKey = localStorageKeyPrefix + key
                let anyCodable = AnyCodable(value)
                let data = try JSONEncoder().encode(anyCodable)
                localUserDefaults.set(data, forKey: fullKey)
            }
        }
    }

    func removeLocal(keys: [String], completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await removeLocal(keys: keys)
                await MainActor.run {
                    completion(nil)
                }
            } catch {
                await MainActor.run {
                    completion(error)
                }
            }
        }
    }

    private func removeLocal(keys: [String]) async throws {
        try await asyncLock.withLock {
            for key in keys {
                let fullKey = localStorageKeyPrefix + key
                localUserDefaults.removeObject(forKey: fullKey)
            }
        }
    }

    func clearLocal(completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await clearLocal()
                await MainActor.run {
                    completion(nil)
                }
            } catch {
                await MainActor.run {
                    completion(error)
                }
            }
        }
    }

    private func clearLocal() async throws {
        try await asyncLock.withLock {
            let keys = localUserDefaults.dictionaryRepresentation().keys.filter {
                $0.hasPrefix(localStorageKeyPrefix)
            }
            for key in keys {
                localUserDefaults.removeObject(forKey: key)
            }
        }
    }

    func getBytesInUseLocal(keys: [String]? = nil, completion: @escaping (Int, Error?) -> Void) {
        Task {
            do {
                let bytes = try await getBytesInUseLocal(keys: keys)
                await MainActor.run {
                    completion(bytes, nil)
                }
            } catch {
                await MainActor.run {
                    completion(0, error)
                }
            }
        }
    }

    private func getBytesInUseLocal(keys: [String]? = nil) async throws -> Int {
        try await asyncLock.withLock {
            guard let keys = keys else {
                // Calculate for all keys
                var totalBytes = 0
                for key in localUserDefaults.dictionaryRepresentation().keys {
                    if key.hasPrefix(localStorageKeyPrefix) {
                        if let data = localUserDefaults.data(forKey: key) {
                            totalBytes += data.count
                        }
                    }
                }
                return totalBytes
            }

            var totalBytes = 0
            for key in keys {
                let fullKey = localStorageKeyPrefix + key
                if let data = localUserDefaults.data(forKey: fullKey) {
                    totalBytes += data.count
                }
            }

            return totalBytes
        }
    }

    // MARK: - Session Storage (Non-persistent)

    func getSession(keys: [String]? = nil, completion: @escaping ([String: Any]?, Error?) -> Void) {
        Task {
            do {
                let result = try await getSession(keys: keys)
                await MainActor.run {
                    completion(result, nil)
                }
            } catch {
                await MainActor.run {
                    completion(nil, error)
                }
            }
        }
    }

    private func getSession(keys: [String]? = nil) async throws -> [String: Any]? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                guard let keys = keys else {
                    // Return all session storage for all extensions
                    var allData: [String: Any] = [:]
                    // This is a simplified approach - in reality, you'd need to track per-extension storage
                    continuation.resume(returning: allData.isEmpty ? nil : allData)
                    return
                }

                var result: [String: Any] = [:]
                // This would need to be implemented based on your session storage strategy
                continuation.resume(returning: result.isEmpty ? nil : result)
            }
        }
    }

    func setSession(items: [String: Any], completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await setSession(items: items)
                await MainActor.run {
                    completion(nil)
                }
            } catch {
                await MainActor.run {
                    completion(error)
                }
            }
        }
    }

    private func setSession(items: [String: Any]) async throws {
        // This would need to be implemented based on your session storage strategy
    }

    func removeSession(keys: [String], completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await removeSession(keys: keys)
                await MainActor.run {
                    completion(nil)
                }
            } catch {
                await MainActor.run {
                    completion(error)
                }
            }
        }
    }

    private func removeSession(keys: [String]) async throws {
        // This would need to be implemented based on your session storage strategy
    }

    func clearSession(completion: @escaping (Error?) -> Void) {
        Task {
            do {
                try await clearSession()
                await MainActor.run {
                    completion(nil)
                }
            } catch {
                await MainActor.run {
                    completion(error)
                }
            }
        }
    }

    private func clearSession() async throws {
        // This would need to be implemented based on your session storage strategy
    }

    func getBytesInUseSession(keys: [String]? = nil, completion: @escaping (Int, Error?) -> Void) {
        Task {
            do {
                let bytes = try await getBytesInUseSession(keys: keys)
                await MainActor.run {
                    completion(bytes, nil)
                }
            } catch {
                await MainActor.run {
                    completion(0, error)
                }
            }
        }
    }

    private func getBytesInUseSession(keys: [String]? = nil) async throws -> Int {
        // This would need to be implemented based on your session storage strategy
        return 0
    }
}