// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionManager+Migration.swift
//  Nook
//
//  An install from before stable IDs has a random id and no source on record, so it never
//  updates. A copy whose own files name a store listing is installed again from that listing,
//  under its real id and with its data, without the person. A Safari build names nothing, so it
//  moves when the person installs that Safari extension again by hand. A Safari import is then
//  kept in step with its app.
//

import Foundation
import os
import SwiftData
import WebKit

/// On whose word a legacy copy's data goes to the install that replaces it.
enum LegacyCarry {
    /// The copy is this extension: a migration found its source, or its own files name this store
    /// listing. It counts as the earlier version, so the sheet shows only what is new.
    case proven
    /// The person picked a Safari extension of the same name by hand. They see the whole sheet,
    /// and optional grants are not carried.
    case chosen
}

extension ExtensionManager {
    static let migrationTriedKey = "ExtensionLegacyMigrationTried"
    static let migrationCutoffKey = "ExtensionLegacyMigrationCutoff"

    /// An install from before stable IDs: a random UUID for an id, and no store.
    static func isLegacy(id: String, sourceStore: String?) -> Bool {
        sourceStore == nil && UUID(uuidString: id) != nil
    }

    // MARK: - Whose data goes where

    /// The store listing a package's own files name.
    static func storeListing(packageAt package: URL) -> (store: ExtensionStore, id: String)? {
        switch ExtensionPackageOrigin.read(packageAt: package) {
        case .chrome(let id): return (.chrome, id)
        case .edge(let id): return (.edge, id)
        case .firefox(let geckoID): return (.firefox, geckoID)
        case nil: return nil
        }
    }

    /// Whether `copy`'s data goes to the install of `id` that replaces it. A matching name alone
    /// carries nothing: a look-alike must not inherit a password manager's storage.
    func legacyCarry(of copy: InstalledExtension, to id: String, in store: ExtensionStore?, from source: URL,
                     manifest: [String: Any], migrating: Bool, interactive: Bool) -> LegacyCarry? {
        guard storageRoot != nil else { return nil }
        let listing = Self.storeListing(packageAt: URL(fileURLWithPath: copy.packagePath))
        if migrating { return .proven }
        // A Firefox listing's id is Mozilla's number, which the package does not carry.
        if let listing, let store, store != .firefox, listing.store == store, listing.id == id { return .proven }
        let isSafariExtension = ["appex", "app"].contains(source.pathExtension.lowercased())
        if interactive, isSafariExtension, listing == nil, copy.manifestVersion == manifest["manifest_version"] as? Int {
            return .chosen
        }
        return nil
    }

    // MARK: - The daily pass

    /// Installs each legacy copy that names a store listing again from that listing, without the
    /// person: a copy whose listing asks for more than it has is left for them.
    func migrateLegacyInstalls() async {
        // A file install made after this first ran is the person's choice of that package, and stays.
        let defaults = UserDefaults.standard
        let cutoff = defaults.object(forKey: Self.migrationCutoffKey) as? Date ?? Date()
        defaults.set(cutoff, forKey: Self.migrationCutoffKey)
        let legacy = ((try? context.fetch(FetchDescriptor<ExtensionEntity>())) ?? [])
            .filter { Self.isLegacy(id: $0.id, sourceStore: $0.sourceStore) && $0.installDate < cutoff }
            .map { (id: $0.id, name: $0.name, package: URL(fileURLWithPath: $0.packagePath)) }
        for copy in legacy {
            guard let listing = Self.storeListing(packageAt: copy.package) else { continue }
            // The real one is here already, beside the copy. Nothing is fetched for that.
            guard listing.store == .firefox || fetchEntity(id: listing.id) == nil else { continue }
            let result = await withCheckedContinuation { continuation in
                installFromWebStore(extensionId: listing.id, store: listing.store, interactive: false, migrating: copy.id) {
                    continuation.resume(returning: $0)
                }
            }
            if case .failure(let error) = result, !error.isCancelled {
                Self.logger.error("Migration failed for '\(copy.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// A Safari import is a copy of what its app shipped that day. When the app has a newer one, take it.
    func refreshSafariImports() async {
        // A Safari import's id is its bundle identifier, which no store id or random id looks like.
        let imports = ((try? context.fetch(FetchDescriptor<ExtensionEntity>())) ?? [])
            .filter { $0.sourceStore == nil && $0.id.contains(".") && UUID(uuidString: $0.id) == nil }
            .map { (id: $0.id, name: $0.name, version: $0.version) }
        guard !imports.isEmpty else { return }
        let safari = await discoverSafariExtensions()
        for copy in imports {
            guard let info = safari.first(where: { $0.id == copy.id }),
                  let manifest = try? ExtensionUtils.validateManifest(at: info.resourcesPath.appendingPathComponent("manifest.json")),
                  let name = manifest["name"] as? String, (Self.resolveLocaleString(name, in: info.resourcesPath) ?? name) == copy.name,
                  let version = manifest["version"] as? String, WebStoreDownloader.isVersion(version, newerThan: copy.version)
            else { continue }
            Self.logger.info("Updating '\(copy.name, privacy: .public)' \(copy.version, privacy: .public) -> \(version, privacy: .public) from its app")
            let result = await withCheckedContinuation { continuation in
                installExtension(from: info.appexPath, extensionId: info.id, interactive: false) { continuation.resume(returning: $0) }
            }
            if case .failure(let error) = result, !error.isCancelled {
                Self.logger.error("Update failed for '\(copy.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Carrying a copy's data

    /// WebKit keeps each extension's storage in a folder named for its id, under this one.
    var storageRoot: URL? {
        guard let configuration = extensionController?.configuration else { return nil }
        if configuration.responds(to: Selector(("_storageDirectoryPath"))),
           let path = configuration.value(forKey: "_storageDirectoryPath") as? String, !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        // Where WebKit puts it when it does not say.
        guard let identifier = configuration.identifier, let bundle = Bundle.main.bundleIdentifier,
              let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first else { return nil }
        let guess = library.appendingPathComponent("WebKit/\(bundle)/WebExtensions/\(identifier.uuidString)")
        return FileManager.default.fileExists(atPath: guess.path) ? guess : nil
    }

    /// Unloads the legacy copy and gives its storage folder to `newID`. WebKit then renames the
    /// extension's own origin data (IndexedDB, localStorage) when the new context first loads at
    /// its new address. Returns how to undo both.
    func takeStorage(ofLegacyCopy legacyID: String, for newID: String) async throws -> () async -> Void {
        guard let root = storageRoot, let legacy = fetchEntity(id: legacyID) else {
            throw ExtensionError.installationFailed("Extension storage could not be located")
        }
        let from = root.appendingPathComponent(legacyID), to = root.appendingPathComponent(newID)
        let package = URL(fileURLWithPath: legacy.packagePath), wasLoaded = extensionContexts[legacyID] != nil
        if let running = extensionContexts.removeValue(forKey: legacyID) {
            compatBridge.contextUnloaded(running)
            if running.isLoaded { try? extensionController?.unload(running) }
            // WebKit lets go of the storage files after the unload returns.
            try? await Task.sleep(for: .milliseconds(700))
        }
        let reload: () async -> Void = { [weak self] in
            guard wasLoaded, let self, let entity = self.fetchEntity(id: legacyID),
                  let webExtension = try? await WKWebExtension(resourceBaseURL: package) else { return }
            self.registerContext(for: entity, webExtension: webExtension)
        }
        let fm = FileManager.default
        guard fm.fileExists(atPath: from.path) else { return reload }
        do {
            // No install has `newID`, so a folder there is what an uninstalled one left behind.
            if fm.fileExists(atPath: to.path) { try fm.removeItem(at: to) }
            try fm.moveItem(at: from, to: to)
        } catch {
            await reload()
            throw ExtensionError.installationFailed("Extension storage could not be moved: \(error.localizedDescription)")
        }
        return {
            try? fm.moveItem(at: to, to: from)
            await reload()
        }
    }

    /// What is left of a legacy copy once its record is gone: the package, and the places that knew it by its old id.
    func forget(legacyCopy oldID: String, packageAt packagePath: String, nowInstalledAs newID: String) {
        try? FileManager.default.removeItem(at: URL(fileURLWithPath: packagePath))
        optionsWindows.removeValue(forKey: oldID)?.close()
        actionAnchors[oldID] = nil
        installedExtensions.removeAll { $0.id == oldID }
        compatManagement.changed(.uninstalled(oldID))
        compatSidePanel.forget(oldID)
        if let settings = browserManagerRef?.nookSettings, let place = settings.pinnedExtensionIDs.firstIndex(of: oldID) {
            settings.pinnedExtensionIDs[place] = newID
        }
    }
}

extension ExtensionEntity {
    /// What the person chose for the copy this record replaces. `grants`: the optional permissions
    /// too, which belong to that extension and to no other.
    func takeSettings(from legacy: ExtensionEntity, grants: Bool) {
        isEnabled = legacy.isEnabled
        installDate = legacy.installDate
        allowsPrivateBrowsing = legacy.allowsPrivateBrowsing
        guard grants else { return }
        grantedOptionalPermissions = legacy.grantedOptionalPermissions
        grantedOptionalMatchPatterns = legacy.grantedOptionalMatchPatterns
    }
}

extension ExtensionError {
    var isCancelled: Bool {
        if case .cancelled = self { return true }
        return false
    }
}
