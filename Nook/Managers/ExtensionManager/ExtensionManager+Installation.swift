// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  ExtensionManager+Installation.swift
//  Nook
//
//  Extension installation, updates, management, persistence, and Safari extension discovery.
//

import AppKit
import CryptoKit
import Foundation
import os
import SwiftData
import SwiftUI
import UniformTypeIdentifiers
import WebKit

extension ExtensionManager {

    // MARK: - Locale String Resolution

    /// Resolve a `__MSG_key__` string using the extension's `_locales/` directory.
    static func resolveLocaleString(_ value: String, in extensionDir: URL) -> String? {
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
        candidates.append("en")

        // Find matching locale directory
        var localeDir: URL?
        for candidate in candidates {
            if let match = items.first(where: { $0.lastPathComponent.caseInsensitiveCompare(candidate) == .orderedSame }) {
                localeDir = match
                break
            }
        }

        guard let localeDir, let data = try? Data(contentsOf: localeDir.appendingPathComponent("messages.json")),
              let messages = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        let key = String(value.dropFirst(6).dropLast(2))
        let entry = messages.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
        if let dict = entry as? [String: Any], let text = dict["message"] as? String {
            return text
        }
        return nil
    }

    // MARK: - Extension Identity

    /// Chrome's extension ID for a manifest `key` (base64 DER public key): SHA-256 of the key,
    /// first 16 bytes as hex, with hex digits 0-f mapped to letters a-p.
    nonisolated static func chromeExtensionID(fromManifestKey key: String) -> String? {
        guard let der = Data(base64Encoded: key.filter { !$0.isWhitespace }), !der.isEmpty else { return nil }
        let hex = SHA256.hash(data: der).prefix(16).map { String(format: "%02x", $0) }.joined()
        return String(hex.compactMap { digit in
            Int(String(digit), radix: 16).map { Character(UnicodeScalar(UInt8(97 + $0))) }
        })
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
        comparedTo previous: WKWebExtension?
    ) -> (permissions: [String], hosts: [String]) {
        func requiredPatterns(_ ext: WKWebExtension) -> [WKWebExtension.MatchPattern] {
            let optional = ext.optionalPermissionMatchPatterns
            return ext.allRequestedMatchPatterns.filter { !optional.contains($0) }
        }
        let newPermissions = Set(new.requestedPermissions.map(\.rawValue))
        let newPatterns = requiredPatterns(new)
        guard let previous else {
            return (newPermissions.sorted(), Set(newPatterns.map(\.string)).sorted())
        }
        let oldPatterns = requiredPatterns(previous)
        let oldStrings = Set(oldPatterns.map(\.string))
        // ponytail: host coverage is exact string match or an old all-hosts pattern; a new narrower
        // pattern under an old broad wildcard (e.g. *.google.com) still prompts. Fine for rare updates.
        let oldCoversAllHosts = oldPatterns.contains { $0.matchesAllURLs || $0.matchesAllHosts }
        let addedHosts = oldCoversAllHosts ? [] : Set(newPatterns.map(\.string)).subtracting(oldStrings).sorted()
        let addedPermissions = newPermissions.subtracting(previous.requestedPermissions.map(\.rawValue)).sorted()
        return (addedPermissions, addedHosts)
    }

    /// Show the permission sheet and wait for the user's decision.
    private func confirmInstallation(
        of webExtension: WKWebExtension,
        name: String,
        permissions: [String],
        hosts: [String],
        isUpdate: Bool
    ) async -> Bool {
        guard let bm = browserManagerRef else { return false }
        return await withCheckedContinuation { continuation in
            let decide = ResumeOnce(fallback: false) { continuation.resume(returning: $0) }
            bm.showDialog {
                StandardDialog(
                    header: { EmptyView() },
                    content: {
                        ExtensionPermissionView(
                            extensionName: name,
                            requestedPermissions: permissions,
                            optionalPermissions: [],
                            requestedHostPermissions: hosts,
                            optionalHostPermissions: [],
                            isUpdate: isUpdate,
                            onGrant: {
                                bm.closeDialog()
                                decide(true)
                            },
                            onDeny: {
                                bm.closeDialog()
                                decide(false)
                            },
                            extensionLogo: webExtension.icon(for: .init(width: 64, height: 64)) ?? NSImage()
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
    ///   - interactive: when false (background updates), an update that needs new permissions
    ///     is skipped instead of prompting.
    func installExtension(
        from url: URL,
        store: ExtensionStore? = nil,
        extensionId: String? = nil,
        interactive: Bool = true,
        completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        guard isExtensionSupportAvailable else {
            completionHandler(.failure(.unsupportedOS))
            return
        }

        Task { @MainActor in
            do {
                let installed = try await performInstallation(
                    from: url, store: store, extensionId: extensionId, interactive: interactive
                )
                if let index = installedExtensions.firstIndex(where: { $0.id == installed.id }) {
                    installedExtensions[index] = installed
                } else {
                    installedExtensions.append(installed)
                }
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
        interactive: Bool
    ) async throws -> InstalledExtension {
        let fm = FileManager.default
        let extensionsDir = getExtensionsDirectory()
        try fm.createDirectory(at: extensionsDir, withIntermediateDirectories: true)

        // STEP 1: Stage the package in a temporary directory (removed on any failure).
        let tempDir = extensionsDir.appendingPathComponent("temp_\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tempDir) }

        switch sourceURL.pathExtension.lowercased() {
        case "zip":
            try await extractZip(from: sourceURL, to: tempDir)
        case "appex", "app":
            try fm.copyItem(at: try resolveSafariExtensionResources(at: sourceURL), to: tempDir)
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
        let hasStableId = callerId != nil || keyId != nil
        let extensionId = callerId ?? keyId ?? UUID().uuidString
        // Patch before parsing so the consent sheet sees Nook's bridge content script hosts too.
        patchManifestForWebKit(at: manifestURL, extensionId: extensionId)

        let staged = try await WKWebExtension(resourceBaseURL: tempDir)
        let name = staged.displayName ?? manifest["name"] as? String ?? "Unknown Extension"
        let version = manifest["version"] as? String ?? "1.0"

        // STEP 2: Decide between fresh install, in-place update, and duplicate.
        let existing = fetchEntity(id: extensionId)
        // ponytail: a copy installed before stable IDs existed (random UUID) with the same name is
        // treated as the same extension and replaced; its storage does not carry over.
        let legacyCopy = (existing == nil && hasStableId)
            ? installedExtensions.first { $0.name == name && UUID(uuidString: $0.id) != nil }
            : nil
        if let existing {
            guard existing.version != version else {
                throw ExtensionError.installationFailed("\(name) v\(version) is already installed")
            }
        } else if legacyCopy == nil,
                  installedExtensions.contains(where: { $0.name == name && $0.version == version }) {
            throw ExtensionError.installationFailed("\(name) v\(version) is already installed")
        }

        // STEP 3: Consent. Fresh installs always ask; updates ask only when permissions grow.
        var previous: WKWebExtension?
        if let existing {
            previous = extensionContexts[extensionId]?.webExtension
            if previous == nil {
                previous = try? await WKWebExtension(resourceBaseURL: URL(fileURLWithPath: existing.packagePath))
            }
        }
        let consent = Self.consentItems(for: staged, comparedTo: previous)
        let needsConsent = existing == nil || !consent.permissions.isEmpty || !consent.hosts.isEmpty
        if needsConsent {
            guard interactive else {
                Self.logger.info("Skipping update of '\(name, privacy: .public)': new version requests additional permissions")
                throw ExtensionError.cancelled
            }
            guard await confirmInstallation(
                of: staged, name: name,
                permissions: consent.permissions, hosts: consent.hosts,
                isUpdate: existing != nil
            ) else {
                throw ExtensionError.cancelled
            }
        }

        if let legacyCopy {
            Self.logger.info("Replacing legacy copy of '\(name, privacy: .public)' (\(legacyCopy.id, privacy: .public)) with \(extensionId, privacy: .public)")
            uninstallExtension(legacyCopy.id)
        }

        // STEP 4: Swap files into place. Unload the running version first.
        if let running = extensionContexts.removeValue(forKey: extensionId) {
            if running.isLoaded { try? extensionController?.unload(running) }
        }
        let finalDir = extensionsDir.appendingPathComponent(extensionId)
        if fm.fileExists(atPath: finalDir.path) {
            _ = try fm.replaceItemAt(finalDir, withItemAt: tempDir)
        } else {
            try fm.moveItem(at: tempDir, to: finalDir)
        }

        // STEP 5: Persist. Updates keep the entity, so enabled state and optional grants survive.
        let entity: ExtensionEntity
        if let existing {
            entity = existing
            entity.name = name
            entity.version = version
            entity.manifestVersion = manifest["manifest_version"] as? Int ?? 3
            entity.extensionDescription = staged.displayDescription ?? ""
            entity.lastUpdateDate = Date()
            entity.packagePath = finalDir.path
            entity.iconPath = findExtensionIcon(in: finalDir, manifest: manifest)
        } else {
            entity = ExtensionEntity(
                id: extensionId,
                name: name,
                version: version,
                manifestVersion: manifest["manifest_version"] as? Int ?? 3,
                extensionDescription: staged.displayDescription ?? "",
                isEnabled: true,
                packagePath: finalDir.path,
                iconPath: findExtensionIcon(in: finalDir, manifest: manifest)
            )
            context.insert(entity)
        }
        if let store { entity.sourceStore = store.rawValue }
        try context.save()

        // STEP 6: Load from the final location so resource URLs resolve to real files.
        if entity.isEnabled {
            let webExtension = try await WKWebExtension(resourceBaseURL: finalDir)
            registerContext(for: entity, webExtension: webExtension)
        }

        Self.logger.info("\(existing == nil ? "Installed" : "Updated", privacy: .public) '\(name, privacy: .public)' v\(version, privacy: .public) as \(extensionId, privacy: .public)")
        return InstalledExtension(from: entity, manifest: manifest)
    }

    /// Create a context for an installed extension, grant its manifest permissions, and load it.
    /// The externally_connectable bridge ships as the extension's own content scripts (see
    /// `patchManifestForWebKit`), so loading and unloading the context is all it needs.
    @discardableResult
    func registerContext(for entity: ExtensionEntity, webExtension: WKWebExtension) -> WKWebExtensionContext? {
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

        // Restore optional grants the user approved at runtime.
        let savedPerms = Set(entity.grantedOptionalPermissions ?? [])
        for p in webExtension.optionalPermissions where savedPerms.contains(String(describing: p)) {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
        }
        let savedMatches = Set(entity.grantedOptionalMatchPatterns ?? [])
        for m in optionalMatches where savedMatches.contains(String(describing: m)) {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
        }

        extensionContext.isInspectable = true
        extensionContexts[entity.id] = extensionContext

        do {
            try extensionController?.load(extensionContext)
        } catch {
            Self.logger.error("Failed to load extension '\(entity.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            return nil
        }

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

        // Tabs that navigated before this extension loaded missed their URL grants.
        if let bm = browserManagerRef {
            for session in bm.tabs.sessions where openedTabIDs.contains(session.itemID) {
                grantExtensionAccessToURL(session.url)
            }
        }

        Self.logger.info("Loaded '\(entity.name, privacy: .public)' MV\(Int(webExtension.manifestVersion)) (contexts: \(self.extensionController?.extensionContexts.count ?? 0))")
        return extensionContext
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

    /// Resolve the web extension resources directory from a Safari .appex or .app bundle.
    /// - .appex: look for `Contents/Resources/manifest.json`
    /// - .app: find the first `.appex` inside `Contents/PlugIns/` that contains web extension resources
    private func resolveSafariExtensionResources(at bundleURL: URL) throws -> URL {
        let ext = bundleURL.pathExtension.lowercased()

        if ext == "appex" {
            let resourcesDir = bundleURL.appendingPathComponent("Contents/Resources")
            let manifest = resourcesDir.appendingPathComponent("manifest.json")
            if FileManager.default.fileExists(atPath: manifest.path) {
                Self.logger.info("Found Safari extension resources at \(resourcesDir.path, privacy: .public)")
                return resourcesDir
            }
            throw ExtensionError.installationFailed(
                "No manifest.json found in .appex bundle at Contents/Resources"
            )
        }

        if ext == "app" {
            // Search PlugIns directory for .appex bundles containing web extension resources
            let plugInsDir = bundleURL.appendingPathComponent("Contents/PlugIns")
            if let items = try? FileManager.default.contentsOfDirectory(
                at: plugInsDir, includingPropertiesForKeys: nil
            ) {
                for item in items where item.pathExtension.lowercased() == "appex" {
                    let resourcesDir = item.appendingPathComponent("Contents/Resources")
                    let manifest = resourcesDir.appendingPathComponent("manifest.json")
                    if FileManager.default.fileExists(atPath: manifest.path) {
                        Self.logger.info("Found Safari extension in \(item.lastPathComponent): \(resourcesDir.path, privacy: .public)")
                        return resourcesDir
                    }
                }
            }
            throw ExtensionError.installationFailed(
                "No Safari Web Extension found in app bundle. Check Contents/PlugIns/ for .appex with manifest.json"
            )
        }

        throw ExtensionError.installationFailed("Unsupported bundle format: .\(ext)")
    }

    private func findExtensionIcon(in directory: URL, manifest: [String: Any])
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

    func enableExtension(_ extensionId: String) {
        guard let entity = fetchEntity(id: extensionId) else { return }
        updateExtensionEnabled(extensionId, enabled: true)

        if let context = extensionContexts[extensionId] {
            guard !context.isLoaded else { return }
            do {
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
                self?.registerContext(for: entity, webExtension: webExtension)
            } catch {
                Self.logger.error("Failed to enable extension '\(entity.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func disableExtension(_ extensionId: String) {
        if let context = extensionContexts[extensionId], context.isLoaded {
            do {
                try extensionController?.unload(context)
            } catch {
                Self.logger.error("Failed to disable extension: \(error.localizedDescription, privacy: .public)")
                return
            }
        }
        updateExtensionEnabled(extensionId, enabled: false)
    }

    func uninstallExtension(_ extensionId: String) {
        if let context = extensionContexts.removeValue(forKey: extensionId), context.isLoaded {
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
        let appPath: URL         // path to the parent .app
        let appexPath: URL       // path to the .appex bundle
        let resourcesPath: URL   // path to Contents/Resources with manifest.json
    }

    /// Discover Safari Web Extensions installed on this Mac by scanning application
    /// bundles for .appex plugins that contain a manifest.json (web extension resources).
    func discoverSafariExtensions() async -> [SafariExtensionInfo] {
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
                            if let data = try? Data(contentsOf: manifestPath),
                               let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                               let name = manifest["name"] as? String,
                               !name.hasPrefix("__MSG_") {
                                extName = name
                            }

                            // Get bundle identifier from Info.plist
                            let bundleId = Bundle(url: pluginURL)?.bundleIdentifier ?? pluginURL.lastPathComponent

                            results.append(SafariExtensionInfo(
                                id: bundleId,
                                name: extName,
                                appPath: appURL,
                                appexPath: pluginURL,
                                resourcesPath: resourcesDir
                            ))
                        }
                    }
                }

                continuation.resume(returning: results)
            }
        }
    }

    /// Install a discovered Safari extension by its resources path
    func installSafariExtension(_ info: SafariExtensionInfo, completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void) {
        installExtension(from: info.appexPath, extensionId: info.id, completionHandler: completionHandler)
    }

    // MARK: - File Picker

    func showExtensionInstallDialog() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Install Extension"
        openPanel.message = "Select an extension folder, ZIP file, or Safari extension (.app/.appex)"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [
            .zip,
            .directory,
            .application,
            .applicationExtension,
        ]

        if openPanel.runModal() == .OK, let url = openPanel.url {
            installExtension(from: url) { result in
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

    private func showErrorAlert(_ error: ExtensionError) {
        let alert = NSAlert()
        alert.messageText = "Extension Installation Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Persistence

    func loadInstalledExtensions() {
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
                patchManifestForWebKit(at: manifestURL, extensionId: entity.id)
                let manifest = try ExtensionUtils.validateManifest(at: manifestURL)
                // Re-resolve __MSG_ names that weren't properly resolved at install time
                if entity.name.hasPrefix("__MSG_") {
                    let packageDir = URL(fileURLWithPath: entity.packagePath)
                    if let resolved = Self.resolveLocaleString(entity.name, in: packageDir) {
                        entity.name = resolved
                        try? self.context.save()
                    }
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
                self.registerContext(for: entity, webExtension: webExtension)
            }

            Self.logger.info("All extensions loaded — signaling ready")
            self.extensionsLoaded = true
            self.checkForExtensionUpdatesIfDue()
        }
    }

    func getExtensionsDirectory() -> URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Nook").appendingPathComponent(
            "Extensions"
        )
    }

    // MARK: - Chrome Web Store Integration

    /// Install (or update) an extension from the Chrome Web Store or Edge Add-ons by store ID.
    func installFromWebStore(
        extensionId: String,
        store: ExtensionStore = .chrome,
        interactive: Bool = true,
        completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        WebStoreDownloader.downloadExtension(extensionId: extensionId, store: store) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let zipURL):
                self.installExtension(
                    from: zipURL, store: store, extensionId: extensionId, interactive: interactive
                ) { installResult in
                    try? FileManager.default.removeItem(at: zipURL)
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
