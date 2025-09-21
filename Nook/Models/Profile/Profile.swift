//
//  Profile.swift
//  Nook
//
//  Runtime profile model representing a browsing persona.
//  Each Profile now owns a persistent, isolated WKWebsiteDataStore
//  to provide strong data separation across profiles.
//

import Foundation
import Observation
import WebKit

@MainActor
@Observable
final class Profile: NSObject, Identifiable {
    let id: UUID
    var name: String
    var icon: String
    let dataStore: WKWebsiteDataStore
    // Metadata (not yet persisted)
    var createdDate: Date = .init()
    var lastUsed: Date = .init()
    var isDefault: Bool { name.lowercased() == "default" }

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
        dataStore = Profile.createDataStore(for: id)
        super.init()
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
            WKWebsiteDataTypeServiceWorkerRegistrations,
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
            WKWebsiteDataTypeServiceWorkerRegistrations,
        ]
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.dataStore.removeData(ofTypes: allTypes, modifiedSince: .distantPast) {
                cont.resume()
            }
        }
        await refreshDataStoreStats()
    }
}
