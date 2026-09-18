// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  Profile.swift
//  Nook
//
//  One space's login context: the persistent, isolated WKWebsiteDataStore keyed by the space's
//  id, plus its stats and cleanup. There is no profile as a user-facing concept; spaces own
//  their data. `TabsController.profile(forSpace:)` vends these, one per space, and a private
//  window holds an ephemeral one that is destroyed when the window closes.
//

import Foundation
import WebKit
import Observation

@MainActor
@Observable
public final class Profile: NSObject, Identifiable {
    public let id: UUID
    public var name: String
    public var icon: String
    public let dataStore: WKWebsiteDataStore
    // Metadata (not yet persisted)
    public var createdDate: Date = Date()
    public var lastUsed: Date = Date()
    public var isDefault: Bool { name.lowercased() == "default" }
    
    /// Whether this is an ephemeral/incognito profile (no disk persistence)
    public var isEphemeral: Bool = false
    
    // Cached stats
    public private(set) var cachedCookieCount: Int = 0
    public private(set) var cachedRecordCount: Int = 0
    public var estimatedDataSize: String { "Cookies: \(cachedCookieCount), Records: \(cachedRecordCount)" }
    public var cookieCount: Int { cachedCookieCount }
    public var hasStoredData: Bool { cachedCookieCount > 0 || cachedRecordCount > 0 }

    public init(
        id: UUID = UUID(),
        name: String = "Default Profile",
        icon: String = "person.crop.circle"
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        // A persistent store identified by the space's UUID, so it is stable across launches.
        self.dataStore = WKWebsiteDataStore(forIdentifier: id)
        super.init()
    }

    /// Initialize with a custom data store (used for ephemeral profiles)
    public init(
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
    public static func createEphemeral() -> Profile {
        let profile = Profile(
            id: UUID(),
            name: "Incognito",
            icon: "eye.slash",
            dataStore: .nonPersistent()
        )
        profile.isEphemeral = true
        return profile
    }

    // MARK: - Validation & Stats
    public func validateDataStore() async -> Bool {
        // Basic check: store exists and is persistent
        if dataStore.isPersistent == false { return false }
        await refreshDataStoreStats()
        return true
    }

    @MainActor
    public func refreshDataStoreStats() async {
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
    public func clearAllData() async {
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
    public func destroyEphemeralDataStore(completion: (() -> Void)? = nil) {
        guard isEphemeral else {
            completion?()
            return
        }
        
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
                
                completion?()
            }
        }
    }
}
