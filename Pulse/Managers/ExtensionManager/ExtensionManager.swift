//
//  ExtensionManager.swift
//  Pulse
//
//  Simplified ExtensionManager using native WKWebExtension APIs
//

import Foundation
import WebKit
import SwiftData
import AppKit
import SwiftUI

@available(macOS 15.4, *)
@MainActor
final class ExtensionManager: NSObject, ObservableObject, WKWebExtensionControllerDelegate, WKNavigationDelegate {
    static let shared = ExtensionManager()
    
    @Published var installedExtensions: [InstalledExtension] = []
    @Published var isExtensionSupportAvailable: Bool = false
    
    private var extensionController: WKWebExtensionController?
    private var extensionContexts: [String: WKWebExtensionContext] = [:]
    private var actionAnchors: [String: [WeakAnchor]] = [:]
    // Stable adapters for tabs/windows used when notifying controller events
    private var tabAdapters: [UUID: ExtensionTabAdapter] = [:]
    private var windowAdapter: ExtensionWindowAdapter?
    private weak var browserManagerRef: BrowserManager?
    
    let context: ModelContext
    
    private override init() {
        self.context = Persistence.shared.container.mainContext
        self.isExtensionSupportAvailable = ExtensionUtils.isExtensionSupportAvailable
        super.init()
        
        if isExtensionSupportAvailable {
            setupExtensionController()
            loadInstalledExtensions()
        }
    }
    
    // MARK: - Setup
    
    private func setupExtensionController() {
        // Use a persistent controller configuration with a stable identifier
        let config: WKWebExtensionController.Configuration
        if let idString = UserDefaults.standard.string(forKey: "Pulse.WKWebExtensionController.Identifier"),
           let uuid = UUID(uuidString: idString) {
            config = WKWebExtensionController.Configuration(identifier: uuid)
        } else {
            let uuid = UUID()
            UserDefaults.standard.set(uuid.uuidString, forKey: "Pulse.WKWebExtensionController.Identifier")
            config = WKWebExtensionController.Configuration(identifier: uuid)
        }
        let controller = WKWebExtensionController(configuration: config)
        controller.delegate = self
        // Align controller config with the app's shared web configuration and data store
        controller.configuration.defaultWebsiteDataStore = WKWebsiteDataStore.default()
        controller.configuration.webViewConfiguration = BrowserConfiguration.shared.webViewConfiguration
        // Critical: Associate our app's browsing WKWebViews with this controller so content scripts inject.
        if #available(macOS 15.4, *) {
            BrowserConfiguration.shared.webViewConfiguration.webExtensionController = controller
        }
        extensionController = controller
        print("ExtensionManager: Native WKWebExtensionController initialized and configured")
    }
    
    // MARK: - Extension Installation
    
    func installExtension(from url: URL, completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void) {
        guard isExtensionSupportAvailable else {
            completionHandler(.failure(.unsupportedOS))
            return
        }
        
        Task {
            do {
                let installedExtension = try await performInstallation(from: url)
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
                    completionHandler(.failure(.installationFailed(error.localizedDescription)))
                }
            }
        }
    }
    
    private func performInstallation(from sourceURL: URL) async throws -> InstalledExtension {
        let extensionsDir = getExtensionsDirectory()
        try FileManager.default.createDirectory(at: extensionsDir, withIntermediateDirectories: true)
        
        let extensionId = ExtensionUtils.generateExtensionId()
        let destinationDir = extensionsDir.appendingPathComponent(extensionId)
        
        // Handle ZIP files and directories
        if sourceURL.pathExtension.lowercased() == "zip" {
            try await extractZip(from: sourceURL, to: destinationDir)
        } else {
            try FileManager.default.copyItem(at: sourceURL, to: destinationDir)
        }
        
        // Validate manifest exists
        let manifestURL = destinationDir.appendingPathComponent("manifest.json")
        let manifest = try ExtensionUtils.validateManifest(at: manifestURL)
        
        // Use native WKWebExtension for loading
        let webExtension = try await WKWebExtension(resourceBaseURL: destinationDir)
        let extensionContext = WKWebExtensionContext(for: webExtension)
        
        // Store context
        extensionContexts[extensionId] = extensionContext
        
        // Load with native controller
        try extensionController?.load(extensionContext)
        
        // Create extension entity for persistence
        let entity = ExtensionEntity(
            id: extensionId,
            name: manifest["name"] as? String ?? "Unknown Extension",
            version: manifest["version"] as? String ?? "1.0",
            manifestVersion: manifest["manifest_version"] as? Int ?? 3,
            extensionDescription: manifest["description"] as? String,
            isEnabled: true,
            packagePath: destinationDir.path,
            iconPath: findExtensionIcon(in: destinationDir, manifest: manifest)
        )
        
        // Save to database
        self.context.insert(entity)
        try self.context.save()
        
        let installedExtension = InstalledExtension(from: entity, manifest: manifest)
        print("ExtensionManager: Successfully installed extension '\(installedExtension.name)' with native WKWebExtension")

        // Prompt for requested/optional permissions on first install (if any)
        if #available(macOS 15.4, *),
           let displayName = extensionContext.webExtension.displayName {
            let requestedPermissions = extensionContext.webExtension.requestedPermissions
            let optionalPermissions = extensionContext.webExtension.optionalPermissions
            let requestedMatches = extensionContext.webExtension.requestedPermissionMatchPatterns
            let optionalMatches = extensionContext.webExtension.optionalPermissionMatchPatterns
            if !requestedPermissions.isEmpty || !requestedMatches.isEmpty || !optionalPermissions.isEmpty || !optionalMatches.isEmpty {
                self.presentPermissionPrompt(
                    requestedPermissions: requestedPermissions,
                    optionalPermissions: optionalPermissions,
                    requestedMatches: requestedMatches,
                    optionalMatches: optionalMatches,
                    extensionDisplayName: displayName,
                    onDecision: { grantedPerms, grantedMatches in
                        // Apply permission decisions
                        for p in requestedPermissions.union(optionalPermissions) {
                            extensionContext.setPermissionStatus(
                                grantedPerms.contains(p) ? .grantedExplicitly : .deniedExplicitly,
                                for: p
                            )
                        }
                        for m in requestedMatches.union(optionalMatches) {
                            extensionContext.setPermissionStatus(
                                grantedMatches.contains(m) ? .grantedExplicitly : .deniedExplicitly,
                                for: m
                            )
                        }
                    },
                    onCancel: {
                        // Default deny only for requested; optional remain unchanged
                        for p in requestedPermissions { extensionContext.setPermissionStatus(.deniedExplicitly, for: p) }
                        for m in requestedMatches { extensionContext.setPermissionStatus(.deniedExplicitly, for: m) }
                    }
                )
            }
        }

        return installedExtension
    }
    
    private func extractZip(from zipURL: URL, to destinationURL: URL) async throws {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        task.arguments = ["-q", zipURL.path, "-d", destinationURL.path]
        
        try task.run()
        task.waitUntilExit()
        
        if task.terminationStatus != 0 {
            throw ExtensionError.installationFailed("Failed to extract ZIP file")
        }
    }
    
    private func findExtensionIcon(in directory: URL, manifest: [String: Any]) -> String? {
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
        
        let commonIconNames = ["icon.png", "logo.png", "icon128.png", "icon64.png"]
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
        } catch {
            print("ExtensionManager: Failed to enable extension: \(error.localizedDescription)")
        }
    }
    
    func disableExtension(_ extensionId: String) {
        guard let context = extensionContexts[extensionId] else { return }
        
        do {
            try extensionController?.unload(context)
            updateExtensionEnabled(extensionId, enabled: false)
        } catch {
            print("ExtensionManager: Failed to disable extension: \(error.localizedDescription)")
        }
    }
    
    func uninstallExtension(_ extensionId: String) {
        if let context = extensionContexts[extensionId] {
            do {
                try extensionController?.unload(context)
            } catch {
                print("ExtensionManager: Failed to unload extension context: \(error.localizedDescription)")
            }
            extensionContexts.removeValue(forKey: extensionId)
        }
        
        // Remove from database and filesystem
        do {
            let predicate = #Predicate<ExtensionEntity> { $0.id == extensionId }
            let entities = try self.context.fetch(FetchDescriptor<ExtensionEntity>(predicate: predicate))
            
            for entity in entities {
                let packageURL = URL(fileURLWithPath: entity.packagePath)
                try? FileManager.default.removeItem(at: packageURL)
                self.context.delete(entity)
            }
            
            try self.context.save()
            installedExtensions.removeAll { $0.id == extensionId }
            
        } catch {
            print("ExtensionManager: Failed to uninstall extension: \(error)")
        }
    }
    
    private func updateExtensionEnabled(_ extensionId: String, enabled: Bool) {
        do {
            let predicate = #Predicate<ExtensionEntity> { $0.id == extensionId }
            let entities = try self.context.fetch(FetchDescriptor<ExtensionEntity>(predicate: predicate))
            
            if let entity = entities.first {
                entity.isEnabled = enabled
                try self.context.save()
                
                // Update UI
                if let index = installedExtensions.firstIndex(where: { $0.id == extensionId }) {
                    let updatedExtension = InstalledExtension(from: entity, manifest: installedExtensions[index].manifest)
                    installedExtensions[index] = updatedExtension
                }
            }
        } catch {
            print("ExtensionManager: Failed to update extension enabled state: \(error)")
        }
    }
    
    // MARK: - File Picker
    
    func showExtensionInstallDialog() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Install Extension"
        openPanel.message = "Select an extension folder or ZIP file to install"
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.allowedContentTypes = [.zip, .directory]
        
        if openPanel.runModal() == .OK, let url = openPanel.url {
            installExtension(from: url) { result in
                switch result {
                case .success(let ext):
                    print("Successfully installed extension: \(ext.name)")
                case .failure(let error):
                    print("Failed to install extension: \(error.localizedDescription)")
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
    
    private func loadInstalledExtensions() {
        do {
            let entities = try self.context.fetch(FetchDescriptor<ExtensionEntity>())
            var loadedExtensions: [InstalledExtension] = []
            
            for entity in entities {
                let manifestURL = URL(fileURLWithPath: entity.packagePath).appendingPathComponent("manifest.json")
                
                do {
                    let manifest = try ExtensionUtils.validateManifest(at: manifestURL)
                    let installedExtension = InstalledExtension(from: entity, manifest: manifest)
                    loadedExtensions.append(installedExtension)
                    
                    // Recreate native extension if enabled
                    if entity.isEnabled {
                        Task {
                            do {
                                let webExtension = try await WKWebExtension(resourceBaseURL: URL(fileURLWithPath: entity.packagePath))
                                let extensionContext = WKWebExtensionContext(for: webExtension)
                                
                                extensionContexts[entity.id] = extensionContext
                                try extensionController?.load(extensionContext)

                                // If extension defines requested/optional permissions but none decided yet, prompt.
                                if extensionContext.currentPermissions.isEmpty &&
                                   (extensionContext.webExtension.requestedPermissions.isEmpty == false ||
                                    extensionContext.webExtension.optionalPermissions.isEmpty == false ||
                                    extensionContext.webExtension.requestedPermissionMatchPatterns.isEmpty == false ||
                                    extensionContext.webExtension.optionalPermissionMatchPatterns.isEmpty == false),
                                   let displayName = extensionContext.webExtension.displayName {
                                    self.presentPermissionPrompt(
                                        requestedPermissions: extensionContext.webExtension.requestedPermissions,
                                        optionalPermissions: extensionContext.webExtension.optionalPermissions,
                                        requestedMatches: extensionContext.webExtension.requestedPermissionMatchPatterns,
                                        optionalMatches: extensionContext.webExtension.optionalPermissionMatchPatterns,
                                        extensionDisplayName: displayName,
                                        onDecision: { grantedPerms, grantedMatches in
                                            for p in extensionContext.webExtension.requestedPermissions.union(extensionContext.webExtension.optionalPermissions) {
                                                extensionContext.setPermissionStatus(grantedPerms.contains(p) ? .grantedExplicitly : .deniedExplicitly, for: p)
                                            }
                                            for m in extensionContext.webExtension.requestedPermissionMatchPatterns.union(extensionContext.webExtension.optionalPermissionMatchPatterns) {
                                                extensionContext.setPermissionStatus(grantedMatches.contains(m) ? .grantedExplicitly : .deniedExplicitly, for: m)
                                            }
                                        },
                                        onCancel: {
                                            for p in extensionContext.webExtension.requestedPermissions { extensionContext.setPermissionStatus(.deniedExplicitly, for: p) }
                                            for m in extensionContext.webExtension.requestedPermissionMatchPatterns { extensionContext.setPermissionStatus(.deniedExplicitly, for: m) }
                                        }
                                    )
                                }
                            } catch {
                                print("ExtensionManager: Failed to reload extension '\(entity.name)': \(error)")
                            }
                        }
                    }
                    
                } catch {
                    print("ExtensionManager: Failed to load manifest for extension '\(entity.name)': \(error)")
                }
            }
            
            self.installedExtensions = loadedExtensions
            print("ExtensionManager: Loaded \(loadedExtensions.count) extensions using native WKWebExtension")
            
        } catch {
            print("ExtensionManager: Failed to load installed extensions: \(error)")
        }
    }
    
    private func getExtensionsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Pulse").appendingPathComponent("Extensions")
    }
    
    // MARK: - Native Extension Access
    
    /// Get the native WKWebExtensionContext for an extension
    func getExtensionContext(for extensionId: String) -> WKWebExtensionContext? {
        return extensionContexts[extensionId]
    }
    
    /// Get the native WKWebExtensionController
    var nativeController: WKWebExtensionController? {
        return extensionController
    }

    /// Connect the browser manager so we can expose tabs/windows and present UI.
    func attach(browserManager: BrowserManager) {
        self.browserManagerRef = browserManager
        // Ensure a stable window adapter and notify controller about the window
        if #available(macOS 15.4, *), let controller = extensionController {
            let adapter = self.windowAdapter ?? ExtensionWindowAdapter(browserManager: browserManager)
            self.windowAdapter = adapter
            controller.didOpenWindow(adapter)
            controller.didFocusWindow(adapter)
        }
    }

    // MARK: - Controller event notifications for tabs
    @available(macOS 15.4, *)
    private func adapter(for tab: Tab, browserManager: BrowserManager) -> ExtensionTabAdapter {
        if let existing = tabAdapters[tab.id] { return existing }
        let created = ExtensionTabAdapter(tab: tab, browserManager: browserManager)
        tabAdapters[tab.id] = created
        return created
    }

    // Expose a stable adapter getter for window adapters
    @available(macOS 15.4, *)
    func stableAdapter(for tab: Tab) -> ExtensionTabAdapter? {
        guard let bm = browserManagerRef else { return nil }
        return adapter(for: tab, browserManager: bm)
    }

    @available(macOS 15.4, *)
    func notifyTabOpened(_ tab: Tab) {
        guard let bm = browserManagerRef, let controller = extensionController else { return }
        let a = adapter(for: tab, browserManager: bm)
        controller.didOpenTab(a)
    }

    @available(macOS 15.4, *)
    func notifyTabActivated(newTab: Tab, previous: Tab?) {
        guard let bm = browserManagerRef, let controller = extensionController else { return }
        let newA = adapter(for: newTab, browserManager: bm)
        let oldA = previous.map { adapter(for: $0, browserManager: bm) }
        controller.didActivateTab(newA, previousActiveTab: oldA)
        controller.didSelectTabs([newA])
        if let oldA { controller.didDeselectTabs([oldA]) }
    }

    @available(macOS 15.4, *)
    func notifyTabClosed(_ tab: Tab) {
        guard let bm = browserManagerRef, let controller = extensionController else { return }
        let a = adapter(for: tab, browserManager: bm)
        controller.didCloseTab(a, windowIsClosing: false)
        tabAdapters[tab.id] = nil
    }

    @available(macOS 15.4, *)
    func notifyTabPropertiesChanged(_ tab: Tab, properties: WKWebExtension.TabChangedProperties) {
        guard let bm = browserManagerRef, let controller = extensionController else { return }
        let a = adapter(for: tab, browserManager: bm)
        controller.didChangeTabProperties(properties, for: a)
    }

    /// Register a UI anchor view for an extension action button to position popovers.
    func setActionAnchor(for extensionId: String, anchorView: NSView) {
        let anchor = WeakAnchor(view: anchorView, window: anchorView.window)
        if actionAnchors[extensionId] == nil { actionAnchors[extensionId] = [] }
        // Remove stale anchors
        actionAnchors[extensionId]?.removeAll { $0.view == nil }
        if let idx = actionAnchors[extensionId]?.firstIndex(where: { $0.view === anchorView }) {
            actionAnchors[extensionId]?[idx] = anchor
        } else {
            actionAnchors[extensionId]?.append(anchor)
        }
        if anchor.window == nil {
            DispatchQueue.main.async { [weak self, weak anchorView] in
                guard let view = anchorView else { return }
                let updated = WeakAnchor(view: view, window: view.window)
                if let idx = self?.actionAnchors[extensionId]?.firstIndex(where: { $0.view === view }) {
                    self?.actionAnchors[extensionId]?[idx] = updated
                }
            }
        }
    }
    
    // MARK: - WKWebExtensionControllerDelegate
    
    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        print("🎉 DELEGATE: Extension wants to present popup!")
        print("   Action: \(action)")
        print("   Extension: \(extensionContext.webExtension.displayName ?? "Unknown")")
        
        // Debug permission context to help diagnose popup scripts relying on APIs
        let perms = extensionContext.currentPermissions.map { String(describing: $0) }.sorted()
        let reqPerms = extensionContext.webExtension.requestedPermissions.map { String(describing: $0) }.sorted()
        let optPerms = extensionContext.webExtension.optionalPermissions.map { String(describing: $0) }.sorted()
        let hostMatches = extensionContext.currentPermissionMatchPatterns.map { String(describing: $0) }.sorted()
        print("   Current perms: \(perms)")
        print("   Current host matches: \(hostMatches)")
        print("   Requested perms: \(reqPerms)")
        print("   Optional perms: \(optPerms)")
        
        // Get the native popover from the action
        if let popover = action.popupPopover {
            print("✅ DELEGATE: Native popover available - presenting!")
            
            // Show the popover
            DispatchQueue.main.async {
                if let webView = action.popupWebView {
                    // Attach basic navigation logging to detect resource/activation failures
                    webView.navigationDelegate = self
                    if #available(macOS 13.3, *) {
                        webView.isInspectable = true
                    }
                    // Attach console helper for manual JS evaluation
                    PopupConsole.shared.attach(to: webView)
                    let popupURL = webView.url?.absoluteString ?? "(nil)"
                    print("   Popup URL: \"\(popupURL)\"")
                    webView.evaluateJavaScript("document.readyState") { value, _ in
                        let state = (value as? String) ?? "(unknown)"
                        print("   Popup document.readyState: \"\(state)\"")
                    }
                } else {
                    print("   No popupWebView present on action (yet)")
                }
                let targetWindow = NSApp.keyWindow ?? NSApp.mainWindow
                if let extId = self.extensionContexts.first(where: { $0.value === extensionContext })?.key,
                   var anchors = self.actionAnchors[extId] {
                    anchors.removeAll { $0.view == nil }
                    self.actionAnchors[extId] = anchors
                    if let win = targetWindow, let match = anchors.first(where: { $0.window === win }), let view = match.view {
                        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
                        completionHandler(nil)
                        return
                    }
                    if let view = anchors.first?.view {
                        popover.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
                        completionHandler(nil)
                        return
                    }
                }
                if let window = targetWindow, let contentView = window.contentView {
                    let rect = CGRect(x: contentView.bounds.midX - 10, y: contentView.bounds.maxY - 10, width: 20, height: 20)
                    popover.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
                    completionHandler(nil)
                    return
                }

                print("❌ DELEGATE: No anchor or contentView available")
                completionHandler(NSError(domain: "ExtensionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No window available"]))
            }
        } else {
            print("❌ DELEGATE: No popover available on action")
            completionHandler(NSError(domain: "ExtensionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No popover available"]))
        }
}
    
    // MARK: - WKNavigationDelegate (popup diagnostics)
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        print("[Popup] didStartProvisionalNavigation: \"\(urlString)\"")
    }
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        print("[Popup] didCommit: \"\(urlString)\"")
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let urlString = webView.url?.absoluteString ?? "(nil)"
        print("[Popup] didFinish: \"\(urlString)\"")
        webView.evaluateJavaScript("document.title") { value, _ in
            let title = (value as? String) ?? "(unknown)"
            print("[Popup] document.title: \"\(title)\"")
        }
        // Quick capability probe for extension APIs commonly used by popups
        let probe = "(() => ({ href: location.href, title: document.title, hasBrowser: typeof browser, hasChrome: typeof chrome, hasRuntime: typeof (browser && browser.runtime), hasStorageGet: typeof (browser && browser.storage && browser.storage.local && browser.storage.local.get), hasTabsQuery: typeof (browser && browser.tabs && browser.tabs.query), bodyText: (document.body && document.body.innerText ? document.body.innerText.slice(0, 200) : '') }))()"
        webView.evaluateJavaScript(probe) { value, error in
            if let error = error {
                print("[Popup] probe error: \(error.localizedDescription)")
            } else if let dict = value as? [String: Any] {
                print("[Popup] probe: \(dict)")
            } else {
                print("[Popup] probe: (unexpected result)")
            }
        }
        // Try a live tabs.query from the popup context to catch mapping issues
        let tabsProbe = "(async () => { try { const r = await browser.tabs.query({active:true, currentWindow:true}); return {len:r.length, id:r[0] && r[0].id, url:r[0] && r[0].url, title:r[0] && r[0].title}; } catch(e) { return {error: (e && e.message) || String(e)} } })()"
        webView.evaluateJavaScript(tabsProbe) { value, _ in
            print("[Popup] tabs.query probe: \(String(describing: value))")
        }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[Popup] didFail: \(error.localizedDescription)")
    }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[Popup] didFailProvisional: \(error.localizedDescription)")
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        print("[Popup] content process terminated")
    }

    // MARK: - Windows exposure (tabs/windows APIs)
    @available(macOS 15.4, *)
    func webExtensionController(_ controller: WKWebExtensionController, focusedWindowFor extensionContext: WKWebExtensionContext) -> (any WKWebExtensionWindow)? {
        guard let bm = browserManagerRef else { return nil }
        if windowAdapter == nil { windowAdapter = ExtensionWindowAdapter(browserManager: bm) }
        return windowAdapter
    }

    @available(macOS 15.4, *)
    func webExtensionController(_ controller: WKWebExtensionController, openWindowsFor extensionContext: WKWebExtensionContext) -> [any WKWebExtensionWindow] {
        guard let bm = browserManagerRef else { return [] }
        if windowAdapter == nil { windowAdapter = ExtensionWindowAdapter(browserManager: bm) }
        return [windowAdapter!]
    }

    // MARK: - Permission prompting helper (invoked by delegate when needed)
    @available(macOS 15.4, *)
    func presentPermissionPrompt(
        requestedPermissions: Set<WKWebExtension.Permission>,
        optionalPermissions: Set<WKWebExtension.Permission>,
        requestedMatches: Set<WKWebExtension.MatchPattern>,
        optionalMatches: Set<WKWebExtension.MatchPattern>,
        extensionDisplayName: String,
        onDecision: @escaping (_ grantedPermissions: Set<WKWebExtension.Permission>, _ grantedMatches: Set<WKWebExtension.MatchPattern>) -> Void,
        onCancel: @escaping () -> Void
    ) {
        guard let bm = browserManagerRef else { onCancel(); return }

        // Convert enums to readable strings for UI
        let reqPerms = requestedPermissions.map { String(describing: $0) }.sorted()
        let optPerms = optionalPermissions.map { String(describing: $0) }.sorted()
        let reqHosts = requestedMatches.map { String(describing: $0) }.sorted()
        let optHosts = optionalMatches.map { String(describing: $0) }.sorted()

        bm.showCustomContentDialog(
            header: AnyView(DialogHeader(icon: "puzzlepiece.extension", title: "Extension Permissions", subtitle: nil)),
            content: ExtensionPermissionView(
                extensionName: extensionDisplayName,
                requestedPermissions: reqPerms,
                optionalPermissions: optPerms,
                requestedHostPermissions: reqHosts,
                optionalHostPermissions: optHosts,
                onGrant: { selectedPerms, selectedHosts in
                    // Map strings back using string description matching across both requested and optional
                    let allPerms = requestedPermissions.union(optionalPermissions)
                    let allHosts = requestedMatches.union(optionalMatches)
                    let grantedPermissions = Set(allPerms.filter { selectedPerms.contains(String(describing: $0)) })
                    let grantedMatches = Set(allHosts.filter { selectedHosts.contains(String(describing: $0)) })
                    bm.closeDialog()
                    onDecision(grantedPermissions, grantedMatches)
                },
                onDeny: {
                    bm.closeDialog()
                    onCancel()
                }
            ),
            footer: AnyView(EmptyView())
        )
    }

    // Delegate entry point for permission requests from extensions at runtime
    @available(macOS 15.4, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissions permissions: Set<WKWebExtension.Permission>,
        in window: (any WKWebExtensionWindow)? ,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let displayName = extensionContext.webExtension.displayName ?? "Extension"
        presentPermissionPrompt(
            requestedPermissions: permissions,
            optionalPermissions: extensionContext.webExtension.optionalPermissions,
            requestedMatches: extensionContext.webExtension.requestedPermissionMatchPatterns,
            optionalMatches: extensionContext.webExtension.optionalPermissionMatchPatterns,
            extensionDisplayName: displayName,
            onDecision: { grantedPerms, grantedMatches in
                for p in permissions.union(extensionContext.webExtension.optionalPermissions) {
                    extensionContext.setPermissionStatus(
                        grantedPerms.contains(p) ? .grantedExplicitly : .deniedExplicitly,
                        for: p
                    )
                }
                for m in extensionContext.webExtension.requestedPermissionMatchPatterns.union(extensionContext.webExtension.optionalPermissionMatchPatterns) {
                    extensionContext.setPermissionStatus(
                        grantedMatches.contains(m) ? .grantedExplicitly : .deniedExplicitly,
                        for: m
                    )
                }
                completionHandler(nil)
            },
            onCancel: {
                for p in permissions { extensionContext.setPermissionStatus(.deniedExplicitly, for: p) }
                for m in extensionContext.webExtension.requestedPermissionMatchPatterns { extensionContext.setPermissionStatus(.deniedExplicitly, for: m) }
                completionHandler(nil)
            }
        )
    }

    // Note: We can provide implementations for opening new tabs/windows once the
    // exact parameter types are finalized for the targeted SDK. These delegate
    // methods are optional; omitting them avoids type resolution issues across
    // SDK variations while retaining popup and permission handling.

    // MARK: - Opening tabs/windows requested by extensions
    @available(macOS 15.4, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewTabUsing configuration: WKWebExtension.TabConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let bm = browserManagerRef else { completionHandler(nil); return }

        let targetURL = configuration.url
        if let url = targetURL {
            let space = bm.tabManager.currentSpace
            let newTab = bm.tabManager.createNewTab(url: url.absoluteString, in: space)
            if configuration.shouldBePinned { bm.tabManager.pinTab(newTab) }
            if configuration.shouldBeActive { bm.tabManager.setActiveTab(newTab) }
            completionHandler(nil)
            return
        }
        // No URL specified — ignore per docs discretion
        completionHandler(nil)
    }

    @available(macOS 15.4, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        openNewWindowUsing configuration: WKWebExtension.WindowConfiguration,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        guard let bm = browserManagerRef else { completionHandler(nil); return }
        // Create a new space to emulate a separate window in our UI
        let newSpace = bm.tabManager.createSpace(name: "Window")
        if let firstURL = configuration.tabURLs.first {
            _ = bm.tabManager.createNewTab(url: firstURL.absoluteString, in: newSpace)
        } else {
            _ = bm.tabManager.createNewTab(in: newSpace)
        }
        bm.tabManager.setActiveSpace(newSpace)
        completionHandler(nil)
    }
    @available(macOS 15.4, *)
    func webExtensionController(
        _ controller: WKWebExtensionController,
        promptForPermissionMatchPatterns matchPatterns: Set<WKWebExtension.MatchPattern>,
        in window: (any WKWebExtensionWindow)?,
        for extensionContext: WKWebExtensionContext,
        completionHandler: @escaping (Error?) -> Void
    ) {
        let displayName = extensionContext.webExtension.displayName ?? "Extension"
        presentPermissionPrompt(
            requestedPermissions: [],
            optionalPermissions: [],
            requestedMatches: matchPatterns,
            optionalMatches: [],
            extensionDisplayName: displayName,
            onDecision: { _, grantedMatches in
                for m in matchPatterns {
                    extensionContext.setPermissionStatus(
                        grantedMatches.contains(m) ? .grantedExplicitly : .deniedExplicitly,
                        for: m
                    )
                }
                completionHandler(nil)
            },
            onCancel: {
                for m in matchPatterns { extensionContext.setPermissionStatus(.deniedExplicitly, for: m) }
                completionHandler(nil)
            }
        )
    }
}

// MARK: - Weak View Reference Helper
final class WeakAnchor {
    weak var view: NSView?
    weak var window: NSWindow?
    init(view: NSView?, window: NSWindow?) {
        self.view = view
        self.window = window
    }
}
