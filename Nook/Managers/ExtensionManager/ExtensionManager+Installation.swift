// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionManager+Installation.swift
//  Nook
//
//  Extension installation, updates, management, persistence, and Safari extension discovery.
//

import AppKit
import Foundation
import os
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import NookWeb

struct InstallConsent: Identifiable {
    let id = UUID()
    let name: String
    let version: String
    let source: ExtensionSource
    let replacing: InstalledExtension?
    let permissions: [String]
    let hosts: [String]
    let isUpdate: Bool
    let logo: NSImage
}

typealias InstallConsentPresenter = @MainActor (InstallConsent) async -> Bool

/// What an update rewrites on an extension's record, kept so a failed load can put it back.
private struct RecordSnapshot {
    let name: String
    let version: String
    let manifestVersion: Int
    let description: String?
    let packagePath: String
    let iconPath: String?
    let origin: String?
    let safariAppPath: String?
    let sourceStore: String?
    let lastUpdateDate: Date
    let optionalPermissions: [String]?
    let optionalMatchPatterns: [String]?
    let allowsPrivateBrowsing: Bool

    init(_ entity: ExtensionEntity) {
        name = entity.name
        version = entity.version
        manifestVersion = entity.manifestVersion
        description = entity.extensionDescription
        packagePath = entity.packagePath
        iconPath = entity.iconPath
        origin = entity.origin
        safariAppPath = entity.safariAppPath
        sourceStore = entity.sourceStore
        lastUpdateDate = entity.lastUpdateDate
        optionalPermissions = entity.grantedOptionalPermissions
        optionalMatchPatterns = entity.grantedOptionalMatchPatterns
        allowsPrivateBrowsing = entity.allowsPrivateBrowsing
    }

    func apply(to entity: ExtensionEntity) {
        entity.name = name
        entity.version = version
        entity.manifestVersion = manifestVersion
        entity.extensionDescription = description
        entity.packagePath = packagePath
        entity.iconPath = iconPath
        entity.origin = origin
        entity.safariAppPath = safariAppPath
        entity.sourceStore = sourceStore
        entity.lastUpdateDate = lastUpdateDate
        entity.grantedOptionalPermissions = optionalPermissions
        entity.grantedOptionalMatchPatterns = optionalMatchPatterns
        entity.allowsPrivateBrowsing = allowsPrivateBrowsing
    }
}

extension ExtensionManager {

    // MARK: - Locale String Resolution

    /// Resolve a `__MSG_key__` string using the extension's `_locales/` directory.
    nonisolated static func resolveLocaleString(_ value: String, in extensionDir: URL) -> String? {
        guard value.hasPrefix("__MSG_") && value.hasSuffix("__") else { return nil }

        let localesDir = extensionDir.appendingPathComponent("_locales")
        guard FileManager.default.fileExists(atPath: localesDir.path) else { return nil }

        guard let items = try? FileManager.default.contentsOfDirectory(at: localesDir, includingPropertiesForKeys: nil) else { return nil }

        // Build locale candidate list
        var candidates: [String] = []
        let current = Locale.current
        if let lang = current.language.languageCode?.identifier {
            if let region = current.language.region?.identifier {
                candidates.append("\(lang)_\(region)")
                candidates.append("\(lang)-\(region)")
            }
            candidates.append(lang)
        }
        let manifest = (try? Data(contentsOf: extensionDir.appendingPathComponent("manifest.json")))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        if let defaultLocale = manifest?["default_locale"] as? String {
            candidates.append(defaultLocale)
        }
        candidates.append("en")

        let key = String(value.dropFirst(6).dropLast(2))
        for candidate in candidates {
            guard let localeDir = items.first(where: { $0.lastPathComponent.caseInsensitiveCompare(candidate) == .orderedSame }),
                  let data = try? Data(contentsOf: localeDir.appendingPathComponent("messages.json")),
                  let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else { continue }
            let entry = messages.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
            if let text = (entry as? [String: Any])?["message"] as? String {
                return text
            }
        }
        return nil
    }

    // MARK: - Extension Identity

    /// Chrome's extension ID for a manifest `key` (base64 DER public key): SHA-256 of the key,
    /// first 16 bytes as hex, with hex digits 0-f mapped to letters a-p.
    nonisolated static func chromeExtensionID(fromManifestKey key: String) -> String? {
        ExtensionPackageOrigin.chromeID(fromManifestKey: key)
    }

    func fetchEntity(id: String) -> ExtensionEntity? {
        let target = id
        let predicate = #Predicate<ExtensionEntity> { $0.id == target }
        return try? context.fetch(FetchDescriptor<ExtensionEntity>(predicate: predicate)).first
    }

    // MARK: - Install Consent

    /// Permissions and host patterns the user must approve. For a fresh install that is
    /// everything required; for an update it is only what the new version adds.
    static func consentItems(
        for new: WKWebExtension,
        comparedTo previous: WKWebExtension?,
        hiding added: Set<String> = [],
        previouslyHiding previouslyAdded: Set<String> = [],
        bridged: Set<String> = []
    ) -> (permissions: [String], hosts: [String]) {
        func requiredPatterns(_ ext: WKWebExtension) -> [WKWebExtension.MatchPattern] {
            let optional = ext.optionalPermissionMatchPatterns
            return ext.allRequestedMatchPatterns.filter { !optional.contains($0) }
        }
        // What Nook added for its own channel is not the extension's request, in either version.
        let newPermissions = ExtensionCompatBridge.consentPermissions(of: new, hiding: added, bridged: bridged)
        let newPatterns = requiredPatterns(new)
        guard let previous else {
            return (newPermissions.sorted(), Set(newPatterns.map(\.string)).sorted())
        }
        let oldPatterns = requiredPatterns(previous)
        // WebKit's own containment: `<all_urls>` and `*://*/*` cover neither `file:` nor a wider scheme.
        let addedHosts = Set(newPatterns.filter { pattern in !oldPatterns.contains { $0.matches(pattern) } }
            .map(\.string)).sorted()
        let oldPermissions = ExtensionCompatBridge.consentPermissions(of: previous, hiding: previouslyAdded, bridged: bridged)
        let addedPermissions = newPermissions.subtracting(oldPermissions).sorted()
        return (addedPermissions, addedHosts)
    }

    /// Show the permission dialog in the browser window and wait for the user's decision.
    private func presentInBrowserWindow(_ consent: InstallConsent) async -> Bool {
        guard let bm = browserManagerRef else { return false }
        let browserWindows = bm.windowRegistry?.allWindows.compactMap(\.window) ?? []
        // The dialog draws only in browser windows, so one has to exist and be in front of other Nook windows.
        if browserWindows.isEmpty || NSApp.keyWindow.map({ !browserWindows.contains($0) }) == true {
            _ = bm.openBrowserWindow()
        }
        return await withCheckedContinuation { continuation in
            let decide = ResumeOnce(fallback: false) { continuation.resume(returning: $0) }
            bm.showDialog {
                StandardDialog(
                    header: { EmptyView() },
                    content: {
                        ExtensionPermissionView(
                            consent: consent,
                            onGrant: {
                                bm.closeDialog()
                                decide(true)
                            },
                            onDeny: {
                                bm.closeDialog()
                                decide(false)
                            }
                        )
                    },
                    footer: { EmptyView() }
                )
            }
        }
    }

    // MARK: - Extension Installation

    /// Install or update an extension from a ZIP, directory, `.appex`, or `.app`.
    /// - Parameters:
    ///   - store: set for Chrome Web Store / Edge Add-ons installs; enables automatic updates.
    ///   - extensionId: stable ID from the caller (store ID, Safari bundle ID). Falls back to the
    ///     ID derived from the manifest `key`, then a random UUID.
    ///   - presenter: asks for consent where the install started; the browser window when nil.
    ///   - migrating: the id of a legacy install this one takes over from, data and settings
    ///     included. See `ExtensionManager+Migration.swift`.
    func installExtension(
        from url: URL,
        store: ExtensionStore? = nil,
        extensionId: String? = nil,
        presenter: InstallConsentPresenter? = nil,
        migrating: String? = nil,
        completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        guard isExtensionSupportAvailable else {
            completionHandler(.failure(.unsupportedOS))
            return
        }

        Task { @MainActor in
            do {
                let installed = try await performInstallation(
                    from: url, store: store, extensionId: extensionId, presenter: presenter, migrating: migrating
                )
                if let index = installedExtensions.firstIndex(where: { $0.id == installed.id }) {
                    installedExtensions[index] = installed
                } else {
                    installedExtensions.append(installed)
                }
                notifyManagement(installed.id) { .installed($0) }
                completionHandler(.success(installed))
            } catch let error as ExtensionError {
                completionHandler(.failure(error))
            } catch {
                completionHandler(.failure(.installationFailed(error.localizedDescription)))
            }
        }
    }

    private func performInstallation(
        from sourceURL: URL,
        store: ExtensionStore?,
        extensionId callerId: String?,
        presenter: InstallConsentPresenter?,
        migrating: String?
    ) async throws -> InstalledExtension {
        let fm = FileManager.default
        let extensionsDir = getExtensionsDirectory()
        try fm.createDirectory(at: extensionsDir, withIntermediateDirectories: true)

        // STEP 1: Stage the package in a temporary directory (removed on any failure).
        let tempDir = extensionsDir.appendingPathComponent("temp_\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tempDir) }

        var safariAppex: URL?
        switch sourceURL.pathExtension.lowercased() {
        case "zip", "xpi":  // a Firefox .xpi is a plain zip
            try await extractZip(from: sourceURL, to: tempDir)
        case "crx":
            guard let zip = WebStoreDownloader.convertCRXtoZIP(try Data(contentsOf: sourceURL)) else {
                throw ExtensionError.installationFailed("Not a valid CRX file")
            }
            let zipURL = extensionsDir.appendingPathComponent("temp_\(UUID().uuidString).zip")
            defer { try? fm.removeItem(at: zipURL) }
            try zip.write(to: zipURL)
            try await extractZip(from: zipURL, to: tempDir)
        case "appex", "app":
            let appex = try resolveSafariAppex(at: sourceURL)
            safariAppex = appex
            try fm.copyItem(at: appex.appendingPathComponent("Contents/Resources"), to: tempDir)
        default:
            try fm.copyItem(at: sourceURL, to: tempDir)
        }
        try rejectSymbolicLinks(in: tempDir)

        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        let manifest = try ExtensionUtils.validateManifest(at: manifestURL)
        if manifest["manifest_version"] as? Int == 3 {
            try validateMV3Requirements(manifest: manifest, baseURL: tempDir)
        }
        let keyId = (manifest["key"] as? String).flatMap(Self.chromeExtensionID(fromManifestKey:))
        let safariBundleId = safariAppex.flatMap { Bundle(url: $0)?.bundleIdentifier }
        let hasStableId = callerId != nil || safariBundleId != nil || keyId != nil
        let extensionId = callerId ?? safariBundleId ?? keyId ?? UUID().uuidString
        // The ID names a directory under Extensions/, and a Safari bundle identifier comes from
        // an Info.plist nobody vetted. Keep it to one plain path component.
        guard !extensionId.isEmpty, extensionId != ".", extensionId != "..",
              extensionId.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) })
        else {
            throw ExtensionError.installationFailed("Invalid extension identifier")
        }
        // Whatever the package ships under Nook's own file names goes first: one of them says what the consent sheet hides.
        ExtensionCompatPatcher.disown(packageAt: tempDir)
        // Patch before parsing so the consent sheet sees Nook's bridge content script hosts too.
        patchManifestForWebKit(at: manifestURL, extensionId: extensionId, store: store)

        let staged = try await WKWebExtension(resourceBaseURL: tempDir)
        let name = staged.displayName ?? manifest["name"] as? String ?? "Unknown Extension"
        let version = manifest["version"] as? String ?? "1.0"
        let source: ExtensionSource = if let store {
            .store(store)
        } else if let safariAppex {
            .safari(appPath: Self.containingApp(of: safariAppex)?.path)
        } else {
            .file
        }

        // This function suspends, and a second install of the same id would start from the same state.
        guard installingIDs.insert(extensionId).inserted else {
            throw ExtensionError.installationFailed("\(extensionId) is already being installed")
        }
        defer { installingIDs.remove(extensionId) }

        // STEP 2: Decide between fresh install, in-place update, and duplicate.
        let existing = fetchEntity(id: extensionId)
        // A copy installed before stable IDs existed (random UUID) with the same name is treated as
        // the same extension and replaced.
        let legacyCopy = (existing == nil && hasStableId)
            ? installedExtensions.first { copy in
                if let migrating { return copy.id == migrating }
                return copy.name == name && UUID(uuidString: copy.id) != nil
            }
            : nil
        // Whether the copy's data comes along. See `LegacyCarry`: a name alone carries nothing.
        let carry = legacyCopy.flatMap { copy in
            legacyCarry(of: copy, to: extensionId, in: store, from: sourceURL, manifest: manifest,
                        migrating: migrating != nil)
        }
        let carriedID = carry == nil ? nil : legacyCopy?.id
        if migrating != nil, carriedID == nil {
            throw ExtensionError.installationFailed("Nothing to migrate to \(extensionId)")
        }
        // The same extension from the other kind of source. A migration replaces only its own copy.
        let replaced = existing == nil && migrating == nil
            ? installedExtensions.first { $0.name == name && $0.source.isSafari != source.isSafari }
            : nil
        if let existing {
            guard existing.version != version else {
                throw ExtensionError.installationFailed("\(name) v\(version) is already installed")
            }
        } else if legacyCopy == nil, replaced == nil,
                  installedExtensions.contains(where: { $0.name == name && $0.version == version }) {
            throw ExtensionError.installationFailed("\(name) v\(version) is already installed")
        }

        // STEP 3: Consent. Fresh installs always ask; updates ask only when permissions grow.
        var previous: WKWebExtension?
        // A proven copy stands in for an earlier version. A copy the person only chose is new to the sheet.
        let predecessor = existing ?? (carry == .proven ? carriedID.flatMap(fetchEntity(id:)) : nil)
        if let predecessor {
            previous = extensionContexts[predecessor.id]?.webExtension
            if previous == nil {
                previous = try? await WKWebExtension(resourceBaseURL: URL(fileURLWithPath: predecessor.packagePath))
            }
        }
        // A package from somewhere else can claim an installed extension's ID: a sideload copying a
        // store install's manifest `key`, or another app reusing a Safari bundle identifier. As an
        // update it would take over that extension's storage without a word. Ask as for a fresh
        // install, listing everything it requests.
        let takesOver = existing.map { previous in
            switch (previous.source, source) {
            case (.store, .store), (.file, _): false
            case let (.safari(oldApp?), .safari(newApp?)): oldApp != newApp
            default: true
            }
        } ?? false
        let consent = Self.consentItems(
            for: staged, comparedTo: takesOver ? nil : previous,
            hiding: ExtensionCompatPatcher.addedPermissions(packageAt: tempDir),
            previouslyHiding: predecessor.map { ExtensionCompatPatcher.addedPermissions(packageAt: URL(fileURLWithPath: $0.packagePath)) } ?? [],
            bridged: compatBridge.gatedPermissions)
        let needsConsent = predecessor == nil || takesOver || replaced != nil
            || !consent.permissions.isEmpty || !consent.hosts.isEmpty
        if needsConsent {
            let request = InstallConsent(
                name: name, version: version, source: source, replacing: replaced,
                permissions: consent.permissions, hosts: consent.hosts,
                isUpdate: predecessor != nil && !takesOver,
                logo: staged.icon(for: .init(width: 64, height: 64)) ?? NSImage()
            )
            let granted = if let presenter {
                await presenter(request)
            } else {
                await presentInBrowserWindow(request)
            }
            guard granted else {
                throw ExtensionError.cancelled
            }
        }

        // The sheet and the loads above suspended, and the copy may have been removed meanwhile.
        if let carriedID, fetchEntity(id: carriedID) == nil { throw ExtensionError.cancelled }

        // STEP 4: Swap files into place and load them from there, so resource URLs resolve to real
        // files. The previous version's files, record and context come back if its replacement fails.
        let finalDir = extensionsDir.appendingPathComponent(extensionId)
        let backupDir = extensionsDir.appendingPathComponent("backup_\(UUID().uuidString)")
        defer { try? fm.removeItem(at: backupDir) }
        let running = extensionContexts.removeValue(forKey: extensionId)
        let wasRunning = running?.isLoaded == true
        if let running {
            compatBridge.contextUnloaded(running)
            if wasRunning {
                try? extensionController?.unload(running)
                // WebKit starts the new worker in the old background's process while that still stands, and the worker
                // then has no extension API. ponytail: a fixed pause; wait on that process's exit if it proves short.
                try? await Task.sleep(for: .milliseconds(700))
            }
        }
        var placedNewFiles = false
        var insertedRecord: ExtensionEntity?
        let previousRecord = existing.map(RecordSnapshot.init)
        func putBack() {
            extensionContexts[extensionId] = running
            if placedNewFiles { try? fm.removeItem(at: finalDir) }
            if fm.fileExists(atPath: backupDir.path) { try? fm.moveItem(at: backupDir, to: finalDir) }
            if let insertedRecord { context.delete(insertedRecord) }
            if let existing, let previousRecord { previousRecord.apply(to: existing) }
            try? context.save()
            if let running, wasRunning, let existing {
                loadCompatState(for: running, entity: existing)
                try? extensionController?.load(running)
            }
        }
        do {
            if fm.fileExists(atPath: finalDir.path) {
                try fm.moveItem(at: finalDir, to: backupDir)
            }
            try fm.moveItem(at: tempDir, to: finalDir)
            placedNewFiles = true
        } catch {
            putBack()
            throw error
        }

        // A carried copy hands over its storage here, between its context and the new one.
        var returnStorage: (() async -> Void)?
        if let carriedID {
            Self.logger.info("Migrating '\(name, privacy: .public)' from \(carriedID, privacy: .public) to \(extensionId, privacy: .public)")
            do {
                returnStorage = try await takeStorage(ofLegacyCopy: carriedID, for: extensionId)
            } catch {
                putBack()
                throw error
            }
        }

        // STEP 5: Persist. Updates keep the entity, so enabled state and optional grants survive.
        let entity = existing ?? ExtensionEntity(
            id: extensionId,
            name: name,
            version: version,
            manifestVersion: manifest["manifest_version"] as? Int ?? 3,
            packagePath: finalDir.path
        )
        entity.name = name
        entity.version = version
        entity.manifestVersion = manifest["manifest_version"] as? Int ?? 3
        entity.extensionDescription = staged.displayDescription ?? ""
        entity.packagePath = finalDir.path
        entity.iconPath = Self.findExtensionIcon(in: finalDir, manifest: manifest)
        entity.source = source
        if existing == nil {
            context.insert(entity)
            insertedRecord = entity
        } else {
            entity.lastUpdateDate = Date()
        }
        if takesOver {
            entity.grantedOptionalPermissions = nil
            entity.grantedOptionalMatchPatterns = nil
            entity.allowsPrivateBrowsing = false
        }
        let legacy = carriedID.flatMap(fetchEntity(id:))
        if let legacy { entity.takeSettings(from: legacy, grants: carry == .proven) }
        do {
            try context.save()
        } catch {
            // Nothing half done: the previous version, or the carried copy, keeps its record, its storage and its context.
            putBack()
            await returnStorage?()
            throw error
        }
        if let legacy, let carriedID {
            // Its record goes second. Should that save fail, the launch prunes a record with no package.
            let package = legacy.packagePath
            context.delete(legacy)
            try? context.save()
            forget(legacyCopy: carriedID, packageAt: package, nowInstalledAs: extensionId)
        }

        // STEP 6: Load from the final location so resource URLs resolve to real files.
        if entity.isEnabled {
            do {
                let webExtension = try await WKWebExtension(resourceBaseURL: finalDir)
                try registerContext(for: entity, webExtension: webExtension, restoringGrants: !takesOver)
            } catch {
                guard carriedID != nil else {
                    putBack()
                    throw error
                }
                // A carried copy is installed under its new id by now, and loads at the next launch.
                Self.logger.error("'\(name, privacy: .public)' did not load after its migration: \(error.localizedDescription, privacy: .public)")
            }
        }

        // The copies it replaces stay until it is in: had it failed to load, they would be all there is.
        for oldID in Set([legacyCopy?.id, replaced?.id].compactMap { $0 }) where oldID != carriedID {
            Self.logger.info("Replacing \(oldID, privacy: .public) with \(extensionId, privacy: .public)")
            uninstallExtension(oldID)
        }

        Self.logger.info("\(existing == nil ? "Installed" : "Updated", privacy: .public) '\(name, privacy: .public)' v\(version, privacy: .public) as \(extensionId, privacy: .public)")
        return InstalledExtension(from: entity, manifest: manifest)
    }

    /// Create a context for an installed extension, grant its manifest permissions, and load it.
    /// The externally_connectable bridge ships as the extension's own content scripts (see
    /// `patchManifestForWebKit`), so loading and unloading the context is all it needs.
    /// - Parameter restoringGrants: applies the optional grants and private-page access saved on `entity`.
    func registerContext(
        for entity: ExtensionEntity,
        webExtension: WKWebExtension,
        restoringGrants: Bool = true
    ) throws {
        let extensionContext = WKWebExtensionContext(for: webExtension)
        configureContextIdentity(extensionContext, extensionId: entity.id)

        // Required permissions and match patterns were approved at install time.
        for p in webExtension.requestedPermissions {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
        }
        let optionalMatches = webExtension.optionalPermissionMatchPatterns
        for m in webExtension.allRequestedMatchPatterns where !optionalMatches.contains(m) {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
        }

        if restoringGrants {
            let savedPerms = Set(entity.grantedOptionalPermissions ?? [])
            for p in webExtension.optionalPermissions where savedPerms.contains(String(describing: p)) {
                extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
            }
            let savedMatches = Set(entity.grantedOptionalMatchPatterns ?? [])
            for m in optionalMatches where savedMatches.contains(String(describing: m)) {
                extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
            }
            extensionContext.hasAccessToPrivateData = entity.allowsPrivateBrowsing
        }

        extensionContext.isInspectable = true
        extensionContexts[entity.id] = extensionContext
        loadCompatState(for: extensionContext, entity: entity)

        try extensionController?.load(extensionContext)
        objectWillChange.send()

        if webExtension.hasBackgroundContent {
            let name = entity.name
            Task { @MainActor [weak self] in
                do {
                    try await extensionContext.loadBackgroundContent()
                    #if DEBUG
                    self?.probeBackgroundHealth(for: extensionContext, name: name)
                    #endif
                } catch {
                    Self.logger.error("Background content failed for '\(name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        // A module worker that throws never completes the load above, so the errors WebKit
        // recorded are read on a delay, whether the background loaded, failed or hung.
        let extensionName = entity.name
        Task { @MainActor [weak extensionContext] in
            try? await Task.sleep(for: .seconds(5))
            guard let extensionContext, extensionContext.isLoaded else { return }
            Self.logErrors(of: extensionContext, name: extensionName)
        }

        // Tabs that navigated before this extension loaded missed their URL grants.
        if let bm = browserManagerRef {
            for session in bm.tabs.sessions where openedTabIDs.contains(session.itemID) {
                grantExtensionAccessToURL(session.url, private: session.isPrivate)
            }
            // A restored tab on one of this extension's pages was built before the context
            // existed, so its view cannot show the page. Loading again gives it the right one.
            if let origin = PageSession.extensionOrigin(of: extensionContext.baseURL) {
                for session in bm.tabs.sessions
                where !session.isUnloaded && session.viewExtensionOrigin == nil
                    && PageSession.extensionOrigin(of: session.url) == origin {
                    session.load(session.url)
                }
            }
        }

        Self.logger.info("Loaded '\(entity.name, privacy: .public)' MV\(Int(webExtension.manifestVersion)) (contexts: \(self.extensionController?.extensionContexts.count ?? 0))")
    }

    /// WebKit keeps an extension's manifest and script errors, with file and line. Nothing else
    /// reports a background that died while starting.
    static func logErrors(of context: WKWebExtensionContext, name: String) {
        for error in context.errors.prefix(20) {
            logger.error("Extension '\(name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Only the MV3 service worker file is checked; WebKit validates the rest when loading.
    private func validateMV3Requirements(manifest: [String: Any], baseURL: URL) throws {
        guard let background = manifest["background"] as? [String: Any],
              let serviceWorker = background["service_worker"] as? String
        else { return }
        if !FileManager.default.fileExists(atPath: baseURL.appendingPathComponent(serviceWorker).path) {
            throw ExtensionError.installationFailed("MV3 service worker not found: \(serviceWorker)")
        }
    }

    private func extractZip(from zipURL: URL, to destinationURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path, "-d", destinationURL.path]

        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
        if status != 0 {
            throw ExtensionError.installationFailed("Failed to extract ZIP file")
        }
    }

    /// Extension resources are served to web content, so a link pointing outside the package
    /// would expose arbitrary local files. Reject packages that contain any.
    private func rejectSymbolicLinks(in directory: URL) throws {
        let keys: Set<URLResourceKey> = [.isSymbolicLinkKey]
        if (try? directory.resourceValues(forKeys: keys))?.isSymbolicLink == true {
            throw ExtensionError.installationFailed("Extension package is a symbolic link")
        }
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: Array(keys)
        ) else { return }
        for case let url as URL in enumerator
        where (try? url.resourceValues(forKeys: keys))?.isSymbolicLink == true {
            throw ExtensionError.installationFailed(
                "Extension package contains a symbolic link (\(url.lastPathComponent)), which is not allowed"
            )
        }
    }

    /// Resolve the Safari web extension bundle from a .appex or .app.
    /// - .appex: it must hold `Contents/Resources/manifest.json`
    /// - .app: the first `.appex` inside `Contents/PlugIns/` that holds web extension resources
    private func resolveSafariAppex(at bundleURL: URL) throws -> URL {
        func hasManifest(_ appex: URL) -> Bool {
            FileManager.default.fileExists(atPath: appex.appendingPathComponent("Contents/Resources/manifest.json").path)
        }

        switch bundleURL.pathExtension.lowercased() {
        case "appex":
            guard hasManifest(bundleURL) else {
                throw ExtensionError.installationFailed("No manifest.json found in .appex bundle at Contents/Resources")
            }
            return bundleURL
        case "app":
            let plugIns = (try? FileManager.default.contentsOfDirectory(
                at: bundleURL.appendingPathComponent("Contents/PlugIns"), includingPropertiesForKeys: nil
            )) ?? []
            guard let appex = plugIns.first(where: { $0.pathExtension.lowercased() == "appex" && hasManifest($0) }) else {
                throw ExtensionError.installationFailed(
                    "No Safari Web Extension found in app bundle. Check Contents/PlugIns/ for .appex with manifest.json"
                )
            }
            Self.logger.info("Found Safari extension in \(appex.lastPathComponent, privacy: .public)")
            return appex
        case let ext:
            throw ExtensionError.installationFailed("Unsupported bundle format: .\(ext)")
        }
    }

    /// The app an `.appex` ships in, from `<App>.app/Contents/PlugIns/<Extension>.appex`.
    nonisolated static func containingApp(of appex: URL) -> URL? {
        let app = appex.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return app.pathExtension.lowercased() == "app" ? app : nil
    }

    nonisolated static func findExtensionIcon(in directory: URL, manifest: [String: Any])
        -> String?
    {
        if let icons = manifest["icons"] as? [String: String] {
            for size in ["128", "64", "48", "32", "16"] {
                if let iconPath = icons[size] {
                    let fullPath = directory.appendingPathComponent(iconPath)
                    if FileManager.default.fileExists(atPath: fullPath.path) {
                        return fullPath.path
                    }
                }
            }
        }

        let commonIconNames = [
            "icon.png", "logo.png", "icon128.png", "icon64.png",
        ]
        for iconName in commonIconNames {
            let iconURL = directory.appendingPathComponent(iconName)
            if FileManager.default.fileExists(atPath: iconURL.path) {
                return iconURL.path
            }
        }

        return nil
    }

    // MARK: - Extension Management

    func hasOptionsPage(_ extensionId: String) -> Bool {
        guard let context = extensionContexts[extensionId] else { return false }
        return context.isLoaded && context.optionsPageURL != nil
    }

    func openOptionsPage(_ extensionId: String) {
        guard let controller = extensionController, let context = extensionContexts[extensionId] else { return }
        webExtensionController(controller, openOptionsPageFor: context) { _ in }
    }

    func enableExtension(_ extensionId: String) {
        guard let entity = fetchEntity(id: extensionId) else { return }
        updateExtensionEnabled(extensionId, enabled: true)
        notifyManagement(extensionId) { .enabled($0) }

        if let context = extensionContexts[extensionId] {
            guard !context.isLoaded else { return }
            do {
                loadCompatState(for: context, entity: entity)
                try extensionController?.load(context)
                if context.webExtension.hasBackgroundContent {
                    context.loadBackgroundContent { error in
                        if let error {
                            Self.logger.error("Background load failed on enable: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }
            } catch {
                Self.logger.error("Failed to enable extension: \(error.localizedDescription, privacy: .public)")
            }
            return
        }

        // Disabled at launch, so no context exists yet: build one from the package.
        let packageURL = URL(fileURLWithPath: entity.packagePath)
        Task { @MainActor [weak self] in
            do {
                let webExtension = try await WKWebExtension(resourceBaseURL: packageURL)
                try self?.registerContext(for: entity, webExtension: webExtension)
            } catch {
                Self.logger.error("Failed to enable extension '\(entity.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func disableExtension(_ extensionId: String) {
        if let context = extensionContexts[extensionId], context.isLoaded {
            compatBridge.contextUnloaded(context)
            do {
                try extensionController?.unload(context)
            } catch {
                Self.logger.error("Failed to disable extension: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        updateExtensionEnabled(extensionId, enabled: false)
        notifyManagement(extensionId) { .disabled($0) }
    }

    /// WebKit adds or removes the extension's content scripts in private pages at once.
    func setAllowsPrivateBrowsing(_ extensionId: String, allowed: Bool) {
        guard let entity = fetchEntity(id: extensionId) else { return }
        entity.allowsPrivateBrowsing = allowed
        do {
            try context.save()
        } catch {
            Self.logger.error("Failed to save private browsing access: \(error.localizedDescription, privacy: .public)")
        }
        extensionContexts[extensionId]?.hasAccessToPrivateData = allowed
        if let index = installedExtensions.firstIndex(where: { $0.id == extensionId }) {
            installedExtensions[index] = InstalledExtension(from: entity, manifest: installedExtensions[index].manifest)
        }
    }

    func uninstallExtension(_ extensionId: String) {
        // Storage is keyed by ID, so anything left behind would be inherited by the next package
        // installed under this ID. The fetch starts before the context unloads; removal works on
        // an unloaded extension.
        if let controller = extensionController {
            let types = WKWebExtensionController.allExtensionDataTypes
            controller.fetchDataRecords(ofTypes: types) { records in
                MainActor.assumeIsolated {
                    let own = records.filter { $0.uniqueIdentifier == extensionId }
                    guard !own.isEmpty else { return }
                    controller.removeData(ofTypes: types, from: own) {}
                }
            }
        }

        if let context = extensionContexts.removeValue(forKey: extensionId), context.isLoaded {
            compatBridge.contextUnloaded(context)
            do {
                try extensionController?.unload(context)
            } catch {
                Self.logger.error("Failed to unload extension context: \(error.localizedDescription, privacy: .public)")
            }
        }
        optionsWindows.removeValue(forKey: extensionId)?.close()
        actionAnchors[extensionId] = nil

        if let entity = fetchEntity(id: extensionId) {
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: entity.packagePath))
            context.delete(entity)
            do {
                try context.save()
            } catch {
                Self.logger.error("Failed to uninstall extension: \(error.localizedDescription, privacy: .public)")
            }
        }
        installedExtensions.removeAll { $0.id == extensionId }
        compatManagement.changed(.uninstalled(extensionId))
        compatSidePanel.forget(extensionId)
    }

    private func updateExtensionEnabled(_ extensionId: String, enabled: Bool) {
        guard let entity = fetchEntity(id: extensionId) else { return }
        entity.isEnabled = enabled
        do {
            try context.save()
        } catch {
            Self.logger.error("Failed to update extension enabled state: \(error.localizedDescription, privacy: .public)")
        }
        if let index = installedExtensions.firstIndex(where: { $0.id == extensionId }) {
            installedExtensions[index] = InstalledExtension(
                from: entity,
                manifest: installedExtensions[index].manifest
            )
        }
    }

    // MARK: - Safari Extension Discovery

    /// A Safari Web Extension found on the system
    struct SafariExtensionInfo: Identifiable {
        let id: String           // bundle identifier
        let name: String         // display name
        let version: String
        let appPath: URL         // path to the parent .app
        let appexPath: URL       // path to the .appex bundle
    }

    func refreshSafariExtensions() async {
        if let safariScan { return await safariScan.value }
        let scan = Task { safariExtensions = await discoverSafariExtensions() }
        safariScan = scan
        await scan.value
        safariScan = nil
    }

    /// Safari extensions with nothing installed for them, under their own ID or as another version.
    var uninstalledSafariExtensions: [SafariExtensionInfo] {
        (safariExtensions ?? []).filter { !hasInstalled(id: $0.id, name: $0.name, isSafari: true) }
    }

    /// One choice per extension with nothing installed for it, in its own ID or as another version.
    /// A Web Store and a Safari version of the same extension share a choice, Web Store first.
    func choices(from offers: [ExtensionOffer]) -> [ExtensionChoice] {
        let available = offers.filter { !hasInstalled(id: $0.id, name: $0.name, isSafari: $0.isSafari) }
        var safari = available.filter(\.isSafari)
        var choices: [ExtensionChoice] = []
        for offer in available where !offer.isSafari {
            if let match = safari.firstIndex(where: { $0.name == offer.name }) {
                choices.append(ExtensionChoice(versions: [offer, safari.remove(at: match)]))
            } else {
                choices.append(ExtensionChoice(versions: [offer]))
            }
        }
        choices += safari.map { ExtensionChoice(versions: [$0]) }
        return choices.sorted { $0.versions[0].name.localizedStandardCompare($1.versions[0].name) == .orderedAscending }
    }

    /// Installed under `id`, or as the same product from the other kind of source: Safari or a store.
    private func hasInstalled(id: String, name: String, isSafari: Bool) -> Bool {
        installedExtensions.contains {
            $0.id == id || ($0.source.isSafari != isSafari && $0.name == name)
        }
    }

    func safariExtension(id: String) -> SafariExtensionInfo? {
        safariExtensions?.first { $0.id == id }
    }

    func safariUpdate(for ext: InstalledExtension) -> SafariExtensionInfo? {
        safariExtension(id: ext.id).flatMap { ExtensionVersion.isNewer($0.version, than: ext.version) ? $0 : nil }
    }

    func safariAlternative(to ext: InstalledExtension) -> SafariExtensionInfo? {
        guard !ext.source.isSafari else { return nil }
        return safariExtensions?.first { info in
            ext.name == info.name && !installedExtensions.contains { $0.id == info.id }
        }
    }

    /// Discover Safari Web Extensions installed on this Mac by scanning application
    /// bundles for .appex plugins that contain a manifest.json (web extension resources).
    private func discoverSafariExtensions() async -> [SafariExtensionInfo] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var results: [SafariExtensionInfo] = []
                let fm = FileManager.default

                // Scan both system and user Applications directories
                let searchDirs: [URL] = [
                    URL(fileURLWithPath: "/Applications"),
                    fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                ]

                for searchDir in searchDirs {
                    guard let apps = try? fm.contentsOfDirectory(
                        at: searchDir,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    ) else { continue }

                    for appURL in apps where appURL.pathExtension == "app" {
                        let plugInsDir = appURL.appendingPathComponent("Contents/PlugIns")
                        guard let plugins = try? fm.contentsOfDirectory(
                            at: plugInsDir,
                            includingPropertiesForKeys: nil
                        ) else { continue }

                        for pluginURL in plugins where pluginURL.pathExtension == "appex" {
                            // Check if this appex is a Safari web extension by looking for
                            // both the extension point identifier and a manifest.json
                            let infoPlist = pluginURL.appendingPathComponent("Contents/Info.plist")
                            if let plistData = try? Data(contentsOf: infoPlist),
                               let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any],
                               let nsExt = plist["NSExtension"] as? [String: Any],
                               let pointId = nsExt["NSExtensionPointIdentifier"] as? String,
                               pointId == "com.apple.Safari.web-extension" {
                                // Confirmed Safari web extension — check for manifest.json
                            } else {
                                continue
                            }

                            let resourcesDir = pluginURL.appendingPathComponent("Contents/Resources")
                            let manifestPath = resourcesDir.appendingPathComponent("manifest.json")
                            guard fm.fileExists(atPath: manifestPath.path) else { continue }

                            // Read extension name from manifest
                            var extName = appURL.deletingPathExtension().lastPathComponent
                            let manifest = (try? Data(contentsOf: manifestPath))
                                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
                            if let name = manifest?["name"] as? String {
                                if let resolved = Self.resolveLocaleString(name, in: resourcesDir) {
                                    extName = resolved
                                } else if !name.hasPrefix("__MSG_") {
                                    extName = name
                                }
                            }

                            // Get bundle identifier from Info.plist
                            let bundleId = Bundle(url: pluginURL)?.bundleIdentifier ?? pluginURL.lastPathComponent

                            let info = SafariExtensionInfo(
                                id: bundleId,
                                name: extName,
                                version: manifest?["version"] as? String ?? "1.0",
                                appPath: appURL,
                                appexPath: pluginURL
                            )
                            if let index = results.firstIndex(where: { $0.id == bundleId }) {
                                if ExtensionVersion.isNewer(info.version, than: results[index].version) {
                                    results[index] = info
                                }
                            } else {
                                results.append(info)
                            }
                        }
                    }
                }

                continuation.resume(returning: results)
            }
        }
    }

    func installSafariExtension(
        _ info: SafariExtensionInfo,
        presenter: InstallConsentPresenter? = nil,
        completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        installExtension(
            from: info.appexPath, extensionId: info.id, presenter: presenter, completionHandler: completionHandler
        )
    }

    // MARK: - File Picker

    func showExtensionInstallDialog(presenter: InstallConsentPresenter? = nil) {
        let openPanel = NSOpenPanel()
        openPanel.title = "Install Extension"
        openPanel.message = "Select an extension folder, ZIP, XPI or CRX file, or Safari extension (.app/.appex)"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [
            .zip,
            .directory,
            .application,
            .applicationExtension,
        ] + ["xpi", "crx"].compactMap { UTType(filenameExtension: $0) }

        if openPanel.runModal() == .OK, let url = openPanel.url {
            installExtension(from: url, presenter: presenter) { result in
                switch result {
                case .success(let ext):
                    Self.logger.info("Successfully installed extension: \(ext.name, privacy: .public)")
                case .failure(.cancelled):
                    break
                case .failure(let error):
                    Self.logger.error("Failed to install extension: \(error.localizedDescription, privacy: .public)")
                    self.showErrorAlert(error)
                }
            }
        }
    }

    func showErrorAlert(_ error: ExtensionError) {
        showErrorAlert(details: error.localizedDescription)
    }

    private func showErrorAlert(details: String) {
        let alert = NSAlert()
        alert.messageText = "Extension Installation Failed"
        alert.informativeText = details
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    struct ListInstallProgress {
        let total: Int
        var finished = 0
        var failed = 0

        var isDone: Bool { finished == total }
    }

    /// Installs extensions the person chose from a list, one at a time without asking again, then
    /// lists any that failed in one alert.
    func install(_ offers: [ExtensionOffer]) {
        listInstallProgress = offers.isEmpty ? nil : ListInstallProgress(total: offers.count)
        Task { await installInOrder(offers) }
    }

    private func installInOrder(_ offers: [ExtensionOffer]) async {
        let chosen: InstallConsentPresenter = { _ in true }
        var failures: [String] = []
        for offer in offers {
            let result: Result<InstalledExtension, ExtensionError> = await withCheckedContinuation { continuation in
                let finish = { (result: Result<InstalledExtension, ExtensionError>) in continuation.resume(returning: result) }
                switch offer.package {
                case .store(let store):
                    installFromWebStore(extensionId: offer.id, store: store, presenter: chosen, completionHandler: finish)
                case .safari(let info):
                    installSafariExtension(info, presenter: chosen, completionHandler: finish)
                }
            }
            if case .failure(let error) = result {
                Self.logger.error("Failed to install '\(offer.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                failures.append("\(offer.name): \(error.localizedDescription)")
                listInstallProgress?.failed += 1
            }
            listInstallProgress?.finished += 1
        }
        if !failures.isEmpty {
            showErrorAlert(details: failures.joined(separator: "\n"))
        }
    }

    // MARK: - Persistence

    func loadInstalledExtensions() {
        // A quit while an install waited for consent left its staged copy behind.
        let staged = (try? FileManager.default.contentsOfDirectory(at: getExtensionsDirectory(), includingPropertiesForKeys: nil)) ?? []
        for url in staged where url.lastPathComponent.hasPrefix("temp_") { try? FileManager.default.removeItem(at: url) }

        let entities: [ExtensionEntity]
        do {
            entities = try self.context.fetch(FetchDescriptor<ExtensionEntity>())
        } catch {
            Self.logger.error("Failed to fetch extensions: \(error.localizedDescription, privacy: .public)")
            self.extensionsLoaded = true
            return
        }

        var loadedExtensions: [InstalledExtension] = []
        var enabledEntities: [(ExtensionEntity, [String: Any])] = []

        // Prune broken entries (missing package directory or manifest) and
        // duplicates (same name+version, keep the most recently installed).
        var entitiesToRemove: [ExtensionEntity] = []
        var seenExtensions: [String: ExtensionEntity] = [:]  // "name|version" -> entity

        for entity in entities {
            let packageExists = FileManager.default.fileExists(
                atPath: URL(fileURLWithPath: entity.packagePath)
                    .appendingPathComponent("manifest.json").path
            )
            if !packageExists {
                Self.logger.warning("Pruning broken extension entity '\(entity.name, privacy: .public)' — package missing at \(entity.packagePath, privacy: .public)")
                entitiesToRemove.append(entity)
                continue
            }

            let dedupeKey = "\(entity.name)|\(entity.version)"
            if let existing = seenExtensions[dedupeKey] {
                // Keep the newer install, remove the older one
                let older = entity.installDate < existing.installDate ? entity : existing
                Self.logger.warning("Pruning duplicate extension '\(entity.name, privacy: .public)' v\(entity.version, privacy: .public) (keeping newer)")
                entitiesToRemove.append(older)
                seenExtensions[dedupeKey] = entity.installDate >= existing.installDate ? entity : existing
            } else {
                seenExtensions[dedupeKey] = entity
            }
        }

        if !entitiesToRemove.isEmpty {
            for entity in entitiesToRemove {
                // Remove package directory if it still exists
                let packageURL = URL(fileURLWithPath: entity.packagePath)
                if FileManager.default.fileExists(atPath: packageURL.path) {
                    try? FileManager.default.removeItem(at: packageURL)
                }
                context.delete(entity)
            }
            try? context.save()
            Self.logger.info("Pruned \(entitiesToRemove.count) broken/duplicate extension(s)")
        }

        let validEntities = entities.filter { !entitiesToRemove.contains($0) }

        for entity in validEntities {
            let manifestURL = URL(fileURLWithPath: entity.packagePath)
                .appendingPathComponent("manifest.json")
            do {
                // Refresh Nook's bridge scripts so app updates reach installed extensions
                patchManifestForWebKit(
                    at: manifestURL, extensionId: entity.id,
                    store: entity.sourceStore.flatMap(ExtensionStore.init(rawValue:)))
                let manifest = try ExtensionUtils.validateManifest(at: manifestURL)
                // Re-resolve __MSG_ names that weren't properly resolved at install time
                if entity.name.hasPrefix("__MSG_") {
                    let packageDir = URL(fileURLWithPath: entity.packagePath)
                    if let resolved = Self.resolveLocaleString(entity.name, in: packageDir) {
                        entity.name = resolved
                        try? self.context.save()
                    }
                }
                if entity.origin == nil {
                    entity.source = ExtensionSource(inferredFrom: entity)
                    try? self.context.save()
                }
                loadedExtensions.append(InstalledExtension(from: entity, manifest: manifest))
                if entity.isEnabled {
                    enabledEntities.append((entity, manifest))
                }
            } catch {
                Self.logger.error("Failed to load manifest for '\(entity.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }

        self.installedExtensions = loadedExtensions

        // No enabled extensions — mark loaded immediately
        if enabledEntities.isEmpty {
            Self.logger.info("No enabled extensions to load")
            self.extensionsLoaded = true
            return
        }

        // Load enabled extensions — parse manifests in parallel, then register sequentially
        Task { @MainActor in
            // Phase 1: Parse all extensions in parallel (I/O-bound)
            // Extract Sendable values from PersistentModel entities before crossing actor boundary
            let entityIndex = Dictionary(enabledEntities.map { ($0.0.packagePath, $0.0) }, uniquingKeysWith: { _, latest in latest })
            let parsed: [(ExtensionEntity, WKWebExtension)] = await withTaskGroup(
                of: (String, String, WKWebExtension)?.self
            ) { group in
                for (entity, _) in enabledEntities {
                    let packagePath = entity.packagePath
                    let name = entity.name
                    group.addTask {
                        let resourceURL = URL(fileURLWithPath: packagePath)
                        do {
                            let ext = try await WKWebExtension(resourceBaseURL: resourceURL)
                            return (packagePath, name, ext)
                        } catch {
                            Self.logger.error("Failed to load extension '\(name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                            return nil
                        }
                    }
                }
                var results: [(String, String, WKWebExtension)] = []
                for await result in group {
                    if let r = result { results.append(r) }
                }
                return results
            }.compactMap { (path, _, ext) in
                entityIndex[path].map { ($0, ext) }
            }

            // Phase 2: Register contexts sequentially (must be on MainActor)
            for (entity, webExtension) in parsed {
                do {
                    try self.registerContext(for: entity, webExtension: webExtension)
                } catch {
                    Self.logger.error("Failed to load extension '\(entity.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                }
            }

            Self.logger.info("All extensions loaded — signaling ready")
            self.extensionsLoaded = true
            self.checkForExtensionUpdatesIfDue()
        }
    }

    func getExtensionsDirectory() -> URL {
        if !isDefaultSet { return Self.setDirectory(setID) }
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent(SharedSupportFolder.name).appendingPathComponent(
            "Extensions"
        )
    }

    // MARK: - Chrome Web Store Integration

    /// Install (or update) an extension from the Chrome Web Store, Edge Add-ons or Firefox Add-ons by store ID.
    func installFromWebStore(
        extensionId: String,
        store: ExtensionStore = .chrome,
        presenter: InstallConsentPresenter? = nil,
        migrating: String? = nil,
        completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        WebStoreDownloader.downloadExtension(extensionId: extensionId, store: store) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let download):
                self.installExtension(
                    from: download.file, store: store, extensionId: download.id, presenter: presenter, migrating: migrating
                ) { installResult in
                    try? FileManager.default.removeItem(at: download.file)
                    completionHandler(installResult)
                }
            case .failure(let error):
                completionHandler(.failure(.installationFailed(error.localizedDescription)))
            }
        }
    }
}

/// Calls its closure at most once. If never called, `fallback` is delivered on deinit, so a
/// continuation waiting on a dialog still resumes when the dialog is dismissed some other way.
final class ResumeOnce<T> {
    private var body: ((T) -> Void)?
    private let fallback: T

    init(fallback: T, _ body: @escaping (T) -> Void) {
        self.fallback = fallback
        self.body = body
    }

    func callAsFunction(_ value: T) {
        let run = body
        body = nil
        run?(value)
    }

    deinit {
        body?(fallback)
    }
}
