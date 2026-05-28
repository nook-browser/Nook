//
//  ExtensionManager+Installation.swift
//  Nook
//
//  Extension installation, management, persistence, and Safari extension discovery.
//

import AppKit
import Foundation
import os
import SwiftData
import UniformTypeIdentifiers
import WebKit

@available(macOS 15.4, *)
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

    // MARK: - MV3 Support Methods

    // Note: commonPermissions array removed - now using minimalSafePermissions for better security

    /// Grant all requested permissions at install time (matches Chrome behavior).
    /// Chrome auto-grants everything in the manifest `permissions` array on install.
    /// Only `optional_permissions` require a runtime `chrome.permissions.request()` call.
    private func grantRequestedPermissions(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension
    ) {
        for permission in webExtension.requestedPermissions {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: permission)
        }
        Self.logger.debug("Granted requested permissions: \(webExtension.requestedPermissions.map { String(describing: $0) }.joined(separator: ", "), privacy: .public)")
    }

    /// Backward-compatible alias used by the loadInstalledExtensions path.
    private func grantCommonPermissions(
        to extensionContext: WKWebExtensionContext,
        webExtension: WKWebExtension,
        isExisting: Bool = false
    ) {
        grantRequestedPermissions(to: extensionContext, webExtension: webExtension)
    }

    /// Validate MV3-specific requirements
    private func validateMV3Requirements(manifest: [String: Any], baseURL: URL)
        throws
    {
        // Check for service worker
        if let background = manifest["background"] as? [String: Any] {
            if let serviceWorker = background["service_worker"] as? String {
                let serviceWorkerPath = baseURL.appendingPathComponent(
                    serviceWorker
                )
                if !FileManager.default.fileExists(
                    atPath: serviceWorkerPath.path
                ) {
                    throw ExtensionError.installationFailed(
                        "MV3 service worker not found: \(serviceWorker)"
                    )
                }
                Self.logger.debug("MV3 service worker found: \(serviceWorker, privacy: .public)")
            }
        }

        // Validate content scripts with world parameter
        if let contentScripts = manifest["content_scripts"] as? [[String: Any]]
        {
            for script in contentScripts {
                if let world = script["world"] as? String, world == "MAIN" {
                    Self.logger.debug("MAIN world content script detected - requires macOS 15.5+ for full support")
                }
            }
        }

        // Validate host_permissions vs permissions
        if let hostPermissions = manifest["host_permissions"] as? [String] {
            Self.logger.debug("MV3 host_permissions: \(hostPermissions, privacy: .public)")
        }
    }

    /// Configure MV3-specific extension features
    private func configureMV3Extension(
        webExtension: WKWebExtension,
        context: WKWebExtensionContext,
        manifest: [String: Any]
    ) async throws {
        // MV3: Service worker background handling
        if webExtension.hasBackgroundContent {
            Self.logger.debug("MV3 service worker background detected")
        }

        // MV3: Enhanced content script injection support
        if webExtension.hasInjectedContent {
            Self.logger.debug("MV3 content scripts detected - ensuring MAIN/ISOLATED world support")
        }

        // MV3: Action popup validation
        if let action = manifest["action"] as? [String: Any] {
            if let popup = action["default_popup"] as? String {
                Self.logger.debug("MV3 action popup: \(popup, privacy: .public)")
            }
        }
    }

    // MARK: - Extension Installation

    func installExtension(
        from url: URL,
        completionHandler:
            @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        guard isExtensionSupportAvailable else {
            completionHandler(.failure(.unsupportedOS))
            return
        }

        Task {
            do {
                let installedExtension = try await performInstallation(
                    from: url
                )
                await MainActor.run {
                    self.installedExtensions.append(installedExtension)
                    completionHandler(.success(installedExtension))
                }
            } catch let error as ExtensionError {
                await MainActor.run {
                    completionHandler(.failure(error))
                }
            } catch {
                await MainActor.run {
                    completionHandler(
                        .failure(
                            .installationFailed(error.localizedDescription)
                        )
                    )
                }
            }
        }
    }

    private func performInstallation(from sourceURL: URL) async throws
        -> InstalledExtension
    {
        let extensionsDir = getExtensionsDirectory()
        try FileManager.default.createDirectory(
            at: extensionsDir,
            withIntermediateDirectories: true
        )

        // STEP 1: Extract to temporary location first
        let tempId = UUID().uuidString
        let tempDir = extensionsDir.appendingPathComponent("temp_\(tempId)")

        let ext = sourceURL.pathExtension.lowercased()
        if ext == "zip" {
            try await extractZip(from: sourceURL, to: tempDir)
        } else if ext == "appex" || ext == "app" {
            // Safari Web Extension bundle — resolve and copy web resources
            let resourcesDir = try resolveSafariExtensionResources(at: sourceURL)
            try FileManager.default.copyItem(at: resourcesDir, to: tempDir)
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: tempDir)
        }

        // Validate manifest exists
        let manifestURL = tempDir.appendingPathComponent("manifest.json")
        let manifest = try ExtensionUtils.validateManifest(at: manifestURL)

        // MV3 Validation: Ensure proper manifest version support
        if let manifestVersion = manifest["manifest_version"] as? Int {
            Self.logger.info("Installing MV\(manifestVersion) extension")
            if manifestVersion == 3 {
                try validateMV3Requirements(
                    manifest: manifest,
                    baseURL: tempDir
                )
            }
        }

        // Patch domain-specific content scripts to MAIN world for WebKit fetch compatibility
        patchManifestForWebKit(at: manifestURL)

        // STEP 2: Create a temporary WKWebExtension just to get the uniqueIdentifier
        Self.logger.debug("Initializing WKWebExtension from \(tempDir.path, privacy: .public)")

        let tempExtension = try await WKWebExtension(resourceBaseURL: tempDir)
        let tempContext = WKWebExtensionContext(for: tempExtension)
        let extensionId = tempContext.uniqueIdentifier
        let finalDestinationDir = extensionsDir.appendingPathComponent(extensionId)

        Self.logger.info("Extension ID: \(extensionId, privacy: .public), name: \(tempExtension.displayName ?? "Unknown", privacy: .public)")

        // STEP 2.5: Check for duplicate — same name and version already installed
        let newName = tempExtension.displayName
            ?? Self.resolveLocaleString(
                manifest["name"] as? String ?? "",
                in: tempDir
            )
            ?? manifest["name"] as? String
            ?? "Unknown"
        let newVersion = manifest["version"] as? String ?? ""

        if let existing = await MainActor.run(body: {
            installedExtensions.first(where: { $0.name == newName && $0.version == newVersion })
        }) {
            // Clean up temp directory
            try? FileManager.default.removeItem(at: tempDir)
            Self.logger.warning("Duplicate extension: '\(newName, privacy: .public)' v\(newVersion, privacy: .public) already installed as \(existing.id, privacy: .public)")
            throw ExtensionError.installationFailed(
                "\(newName) v\(newVersion) is already installed"
            )
        }

        // STEP 3: Move files to final directory named after the extension ID
        if FileManager.default.fileExists(atPath: finalDestinationDir.path) {
            try FileManager.default.removeItem(at: finalDestinationDir)
        }
        try FileManager.default.moveItem(at: tempDir, to: finalDestinationDir)

        // STEP 4: Re-create WKWebExtension from the FINAL location so the
        // resource base URL points to where the files actually live. This is
        // critical — the service worker, popup HTML, and all resources are
        // loaded from this path at runtime.
        let webExtension = try await WKWebExtension(resourceBaseURL: finalDestinationDir)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        configureContextIdentity(extensionContext, extensionId: extensionId)

        Self.logger.info("WKWebExtension created from final path: \(finalDestinationDir.path, privacy: .public)")
        Self.logger.debug("Requested permissions: \(webExtension.requestedPermissions.map { String(describing: $0) }.joined(separator: ", "), privacy: .public)")

        // Grant only explicitly requested permissions (shown in install dialog).
        // Optional permissions will be requested at runtime via chrome.permissions.request()
        // and the promptForPermissions delegate.
        for p in webExtension.requestedPermissions {
            extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
            Self.logger.info("Granted permission: \(String(describing: p), privacy: .public)")
        }
        // Grant required match patterns only (host_permissions + content_scripts matches),
        // excluding optional_host_permissions which should be requested at runtime.
        let optionalMatches = webExtension.optionalPermissionMatchPatterns
        for m in webExtension.allRequestedMatchPatterns {
            if !optionalMatches.contains(m) {
                extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
                Self.logger.info("Granted match pattern: \(String(describing: m), privacy: .public)")
            }
        }
        // Optional permissions/match patterns will be handled at runtime via
        // chrome.permissions.request() and the promptForPermissions delegate.

        // Enable Web Inspector for extension pages (background, popup)
        extensionContext.isInspectable = true

        // Store context and load into controller
        extensionContexts[extensionId] = extensionContext

        // Set up externally_connectable bridge BEFORE loading background
        setupExternallyConnectableBridge(
            for: extensionContext,
            extensionId: extensionId,
            packagePath: finalDestinationDir.path
        )

        try extensionController?.load(extensionContext)

        // Start the background service worker so it can handle
        // messages from popup and content scripts.
        Task { @MainActor [weak self] in
            do {
                try await extensionContext.loadBackgroundContent()
                Self.logger.info("Background content loaded for new extension")
                self?.probeBackgroundHealth(for: extensionContext, name: "new extension")
            } catch {
                Self.logger.error("Background load failed for new extension: \(error.localizedDescription, privacy: .public)")
            }
        }

        func getLocaleText(key: String) -> String? {
            guard let manifestValue = manifest[key] as? String else {
                return nil
            }

            if manifestValue.hasPrefix("__MSG_") {
                let localesDirectory = finalDestinationDir.appending(
                    path: "_locales"
                )
                guard
                    FileManager.default.fileExists(
                        atPath: localesDirectory.path(percentEncoded: false)
                    )
                else {
                    return nil
                }

                var pathToDirectory: URL? = nil

                do {
                    let items = try FileManager.default.contentsOfDirectory(
                        at: localesDirectory,
                        includingPropertiesForKeys: nil
                    )

                    // Build a priority list from the user's current locale
                    var localeCandidates: [String] = []
                    let current = Locale.current
                    if let langCode = current.language.languageCode?.identifier {
                        if let regionCode = current.language.region?.identifier {
                            // Full locale with underscore and hyphen variants (e.g. pt_BR, pt-BR)
                            localeCandidates.append("\(langCode)_\(regionCode)")
                            localeCandidates.append("\(langCode)-\(regionCode)")
                        }
                        // Language-only (e.g. pt)
                        localeCandidates.append(langCode)
                    }
                    // Always fall back to English
                    localeCandidates.append("en")

                    // Case-insensitive matching against available locale directories
                    for candidate in localeCandidates {
                        if let match = items.first(where: { $0.lastPathComponent.caseInsensitiveCompare(candidate) == .orderedSame }) {
                            pathToDirectory = match
                            break
                        }
                    }
                } catch {
                    return nil
                }

                guard let pathToDirectory = pathToDirectory else {
                    return nil
                }

                let messagesPath = pathToDirectory.appending(
                    path: "messages.json"
                )
                guard
                    FileManager.default.fileExists(
                        atPath: messagesPath.path(percentEncoded: false)
                    )
                else {
                    return nil
                }

                do {
                    let data = try Data(contentsOf: messagesPath)
                    guard
                        let messages = try JSONSerialization.jsonObject(
                            with: data
                        ) as? [String: Any]
                    else {
                        return nil
                    }

                    // Remove the __MSG_ from the start and the __ at the end
                    let formattedManifestValue = String(
                        manifestValue.dropFirst(6).dropLast(2)
                    )

                    // Look up the key (case-insensitive) and extract "message"
                    let entry = messages.first(where: { $0.key.caseInsensitiveCompare(formattedManifestValue) == .orderedSame })?.value
                    if let dict = entry as? [String: Any],
                       let messageText = dict["message"] as? String {
                        return messageText
                    }

                    return nil
                } catch {
                    return nil
                }

            }

            return nil
        }

        // Create extension entity for persistence
        let entity = ExtensionEntity(
            id: extensionId,
            name: getLocaleText(key: "name") ?? manifest["name"] as? String ?? "Unknown Extension",
            version: manifest["version"] as? String ?? "1.0",
            manifestVersion: manifest["manifest_version"] as? Int ?? 3,
            extensionDescription: getLocaleText(key: "description") ?? "",
            isEnabled: true,
            packagePath: finalDestinationDir.path,
            iconPath: findExtensionIcon(in: finalDestinationDir, manifest: manifest)
        )

        // Save to database
        self.context.insert(entity)
        try self.context.save()

        let installedExtension = InstalledExtension(
            from: entity,
            manifest: manifest
        )
        Self.logger.info("Successfully installed extension '\(installedExtension.name, privacy: .public)'")

        // Required permissions and match patterns were granted above.
        // Optional permissions will be handled at runtime via
        // chrome.permissions.request() and the promptForPermissions delegate.

        return installedExtension
    }

    private func extractZip(from zipURL: URL, to destinationURL: URL)
        async throws
    {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-q", zipURL.path, "-d", destinationURL.path]

        try task.run()
        task.waitUntilExit()

        if task.terminationStatus != 0 {
            throw ExtensionError.installationFailed(
                "Failed to extract ZIP file"
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
        guard let context = extensionContexts[extensionId] else { return }

        do {
            try extensionController?.load(context)
            updateExtensionEnabled(extensionId, enabled: true)

            // Start the background service worker
            context.loadBackgroundContent { error in
                if let error {
                    Self.logger.error("Background load failed on enable: \(error.localizedDescription, privacy: .public)")
                }
            }
        } catch {
            Self.logger.error("Failed to enable extension: \(error.localizedDescription, privacy: .public)")
        }
    }

    func disableExtension(_ extensionId: String) {
        guard let context = extensionContexts[extensionId] else { return }

        do {
            try extensionController?.unload(context)
            updateExtensionEnabled(extensionId, enabled: false)
        } catch {
            Self.logger.error("Failed to disable extension: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Disable all extensions (used when experimental extension support is disabled)
    func disableAllExtensions() {
        let enabledExtensions = installedExtensions.filter { $0.isEnabled }

        for ext in enabledExtensions {
            disableExtension(ext.id)
        }

        Self.logger.info("Disabled \(enabledExtensions.count) extensions")
    }

    /// Enable all previously enabled extensions (used when experimental extension support is re-enabled)
    func enableAllExtensions() {
        let disabledExtensions = installedExtensions.filter { !$0.isEnabled }

        for ext in disabledExtensions {
            // Only enable extensions that were previously enabled (check database)
            do {
                let id = ext.id
                let predicate = #Predicate<ExtensionEntity> { $0.id == id }
                let entities = try self.context.fetch(
                    FetchDescriptor<ExtensionEntity>(predicate: predicate)
                )

                if let entity = entities.first, entity.isEnabled {
                    enableExtension(ext.id)
                }
            } catch {
                Self.logger.error("Failed to check extension \(ext.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }

        Self.logger.info("Re-enabled extensions complete")
    }

    func uninstallExtension(_ extensionId: String) {
        if let context = extensionContexts[extensionId] {
            do {
                try extensionController?.unload(context)
            } catch {
                Self.logger.error("Failed to unload extension context: \(error.localizedDescription, privacy: .public)")
            }
            extensionContexts.removeValue(forKey: extensionId)
        }

        // Remove from database and filesystem
        do {
            let id = extensionId
            let predicate = #Predicate<ExtensionEntity> { $0.id == id }
            let entities = try self.context.fetch(
                FetchDescriptor<ExtensionEntity>(predicate: predicate)
            )

            for entity in entities {
                let packageURL = URL(fileURLWithPath: entity.packagePath)
                try? FileManager.default.removeItem(at: packageURL)
                self.context.delete(entity)
            }

            try self.context.save()

            installedExtensions.removeAll { $0.id == extensionId }
        } catch {
            Self.logger.error("Failed to uninstall extension: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func updateExtensionEnabled(_ extensionId: String, enabled: Bool) {
        do {
            let id = extensionId
            let predicate = #Predicate<ExtensionEntity> { $0.id == id }
            let entities = try self.context.fetch(
                FetchDescriptor<ExtensionEntity>(predicate: predicate)
            )

            if let entity = entities.first {
                entity.isEnabled = enabled
                try self.context.save()

                // Update UI
                if let index = installedExtensions.firstIndex(where: {
                    $0.id == extensionId
                }) {
                    let updatedExtension = InstalledExtension(
                        from: entity,
                        manifest: installedExtensions[index].manifest
                    )
                    installedExtensions[index] = updatedExtension
                }
            }
        } catch {
            Self.logger.error("Failed to update extension enabled state: \(error.localizedDescription, privacy: .public)")
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
        installExtension(from: info.appexPath, completionHandler: completionHandler)
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
                // Patch domain-specific content scripts to MAIN world on each load
                // (idempotent — skips entries that already have a world set)
                patchManifestForWebKit(at: manifestURL)
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
                let extensionContext = WKWebExtensionContext(for: webExtension)
                let extensionId = entity.id
                self.configureContextIdentity(
                    extensionContext,
                    extensionId: extensionId
                )

                Self.logger.info("Loading '\(webExtension.displayName ?? entity.name, privacy: .public)' MV\(webExtension.manifestVersion) hasBackground=\(webExtension.hasBackgroundContent)")

                // Grant explicitly requested permissions (shown at install time).
                for p in webExtension.requestedPermissions {
                    extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
                }
                // Grant required match patterns only (host_permissions + content_scripts matches),
                // excluding optional_host_permissions which should be requested at runtime.
                let optionalMatches = webExtension.optionalPermissionMatchPatterns
                let requiredMatches = webExtension.allRequestedMatchPatterns.filter { !optionalMatches.contains($0) }
                for m in requiredMatches {
                    extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
                }

                // Restore previously-granted optional permissions so the extension
                // doesn't re-prompt on every app launch.
                let savedPerms = Set(entity.grantedOptionalPermissions ?? [])
                var restoredPermCount = 0
                for p in webExtension.optionalPermissions {
                    if savedPerms.contains(String(describing: p)) {
                        extensionContext.setPermissionStatus(.grantedExplicitly, for: p)
                        restoredPermCount += 1
                    }
                }
                let savedMatches = Set(entity.grantedOptionalMatchPatterns ?? [])
                var restoredMatchCount = 0
                for m in optionalMatches {
                    if savedMatches.contains(String(describing: m)) {
                        extensionContext.setPermissionStatus(.grantedExplicitly, for: m)
                        restoredMatchCount += 1
                    }
                }
                Self.logger.debug("Granted \(webExtension.requestedPermissions.count) permissions and \(requiredMatches.count) match patterns for '\(entity.name, privacy: .public)' (restored \(restoredPermCount) optional permissions, \(restoredMatchCount) optional matches)")

                extensionContext.isInspectable = true

                self.extensionContexts[extensionId] = extensionContext

                // Set up externally_connectable bridge BEFORE loading background
                self.setupExternallyConnectableBridge(
                    for: extensionContext,
                    extensionId: extensionId,
                    packagePath: entity.packagePath
                )

                do {
                    try self.extensionController?.load(extensionContext)
                } catch {
                    Self.logger.error("Failed to register extension '\(entity.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                    continue
                }

                // Start background service worker if the extension has one
                if webExtension.hasBackgroundContent {
                    Task { @MainActor [weak self] in
                        do {
                            try await extensionContext.loadBackgroundContent()
                            Self.logger.info("Background content started for '\(entity.name, privacy: .public)'")
                            self?.probeBackgroundHealth(for: extensionContext, name: entity.name)
                        } catch {
                            Self.logger.error("Background content failed for '\(entity.name, privacy: .public)': \(error.localizedDescription, privacy: .public)")
                        }
                    }
                }

                Self.logger.info("Loaded '\(entity.name, privacy: .public)' — contexts: \(self.extensionController?.extensionContexts.count ?? 0, privacy: .public)")
            }

            Self.logger.info("All extensions loaded — signaling ready")
            self.extensionsLoaded = true
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

    /// Install extension from Chrome Web Store by extension ID
    func installFromWebStore(
        extensionId: String,
        completionHandler:
            @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        WebStoreDownloader.downloadExtension(extensionId: extensionId) {
            [weak self] result in
            guard let self = self else { return }

            switch result {
            case .success(let zipURL):
                // Install the downloaded extension
                self.installExtension(from: zipURL) { installResult in
                    // Clean up temporary file
                    try? FileManager.default.removeItem(at: zipURL)
                    completionHandler(installResult)
                }

            case .failure(let error):
                completionHandler(
                    .failure(.installationFailed(error.localizedDescription))
                )
            }
        }
    }
}
