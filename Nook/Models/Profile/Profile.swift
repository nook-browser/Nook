//
//  Profile.swift
//  Nook
//
//  Runtime profile model representing a browsing persona.
//  Each Profile now owns a persistent, isolated WKWebsiteDataStore
//  to provide strong data separation across profiles.
//

import Foundation
import WebKit
import Observation

@MainActor
@Observable
final class Profile: NSObject, Identifiable {
    let id: UUID
    var name: String
    var icon: String
    let dataStore: WKWebsiteDataStore
    // Metadata (not yet persisted)
    var createdDate: Date = Date()
    var lastUsed: Date = Date()
    var isDefault: Bool { name.lowercased() == "default" }
    
    /// Whether this is an ephemeral/incognito profile (no disk persistence)
    var isEphemeral: Bool = false
    
    // Cached stats
    private(set) var cachedCookieCount: Int = 0
    private(set) var cachedRecordCount: Int = 0
    var estimatedDataSize: String { "Cookies: \(cachedCookieCount), Records: \(cachedRecordCount)" }
    var cookieCount: Int { cachedCookieCount }
    var hasStoredData: Bool { cachedCookieCount > 0 || cachedRecordCount > 0 }

    init(
        id: UUID = UUID(),
        name: String = "Default Profile",
        icon: String = "person.crop.circle"
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        // Create a persistent, profile-specific data store derived from the profile ID.
        // Falls back to the default store if unavailable for any reason.
        self.dataStore = Profile.createDataStore(for: id)
        super.init()
    }

    /// Initialize with a custom data store (used for ephemeral profiles)
    init(
        id: UUID = UUID(),
        name: String,
        icon: String,
        dataStore: WKWebsiteDataStore
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.dataStore = dataStore
        super.init()
    }

    // MARK: - Ephemeral Profile Factory
    /// Create a new ephemeral/incognito profile with non-persistent data store
    static func createEphemeral() -> Profile {
        let profile = Profile(
            id: UUID(),
            name: "Incognito",
            icon: "eye.slash",
            dataStore: .nonPersistent()
        )
        profile.isEphemeral = true
        print("🔒 [Profile] Created ephemeral incognito profile: \(profile.id)")
        return profile
    }

    // MARK: - Data Store Creation
    /// Create a persistent, profile-specific WKWebsiteDataStore for the given profile ID.
    /// Uses a deterministic identifier so stores remain stable across launches.
    /// Falls back to the default store for compatibility scenarios.
    private static func createDataStore(for profileId: UUID) -> WKWebsiteDataStore {
        // Prefer a persistent store identified by the profile UUID when available
        if #available(macOS 15.4, *) {
            let store = WKWebsiteDataStore(forIdentifier: profileId)
            if !store.isPersistent {
                print("⚠️ [Profile] Created data store is not persistent for profile: \(profileId.uuidString)")
            } else {
                print("✅ [Profile] Using persistent data store for profile \(profileId.uuidString) — id: \(store.identifier?.uuidString ?? "nil")")
            }
            return store
        } else {
            // Fallback: use default shared store on older systems
            let store = WKWebsiteDataStore.default()
            print("ℹ️ [Profile] Using default website data store (no per-profile stores on this OS)")
            return store
        }
    }

    // MARK: - Validation & Stats
    func validateDataStore() async -> Bool {
        if #available(macOS 15.4, *) {
            // Basic check: store exists and is persistent
            if dataStore.isPersistent == false { return false }
        }
        await refreshDataStoreStats()
        return true
    }

    @MainActor
    func refreshDataStoreStats() async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            dataStore.httpCookieStore.getAllCookies { cookies in
                self.cachedCookieCount = cookies.count
                cont.resume()
            }
        }
        let types: Set<String> = [
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeServiceWorkerRegistrations
        ]
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.dataStore.fetchDataRecords(ofTypes: types) { records in
                self.cachedRecordCount = records.count
                cont.resume()
            }
        }
    }

    // MARK: - Cleanup
    func clearAllData() async {
        let allTypes: Set<String> = [
            WKWebsiteDataTypeCookies,
            WKWebsiteDataTypeDiskCache,
            WKWebsiteDataTypeMemoryCache,
            WKWebsiteDataTypeLocalStorage,
            WKWebsiteDataTypeIndexedDBDatabases,
            WKWebsiteDataTypeFetchCache,
            WKWebsiteDataTypeServiceWorkerRegistrations
        ]
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.dataStore.removeData(ofTypes: allTypes, modifiedSince: .distantPast) {
                cont.resume()
            }
        }
        await refreshDataStoreStats()
    }
    
    /// Destroys the ephemeral data store by clearing all data.
    /// This should be called before releasing an ephemeral profile to ensure
    /// all incognito data is wiped and the store can be properly deallocated.
    /// - Parameter completion: Optional completion handler called when destruction is complete
    func destroyEphemeralDataStore(completion: (() -> Void)? = nil) {
        guard isEphemeral else {
            print("⚠️ [Profile] Cannot destroy data store: profile is not ephemeral")
            completion?()
            return
        }
        
        print("🔒 [Profile] Destroying ephemeral data store for profile: \(id)")
        
        let allTypes = WKWebsiteDataStore.allWebsiteDataTypes()
        
        // Clear all data from the store
        dataStore.removeData(ofTypes: allTypes, modifiedSince: .distantPast) { [weak self] in
            guard let self = self else {
                completion?()
                return
            }
            
            // Also clear cookies specifically
            self.dataStore.httpCookieStore.getAllCookies { cookies in
                for cookie in cookies {
                    self.dataStore.httpCookieStore.delete(cookie)
                }
                
                print("🔒 [Profile] Ephemeral data store destroyed for profile: \(self.id)")
                completion?()
            }
        }
    }
}
