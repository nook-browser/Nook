//
//  ExtensionManager.swift
//  Pulse
//
//  Created for WKWebExtension support
//

import Foundation
import WebKit
import SwiftData
import AppKit
import UniformTypeIdentifiers

// Check if WKWebExtensionController exists in this SDK version
#if canImport(WebKit)
import WebKit
#endif

@available(macOS 15.4, *)
@MainActor
final class ExtensionManager: NSObject, ObservableObject {
    static let shared = ExtensionManager()
    
    @Published var installedExtensions: [InstalledExtension] = []
    @Published var isExtensionSupportAvailable: Bool = false
    
    private var extensionController: WKWebExtensionController?
    private var extensionContexts: [String: WKWebExtensionContext] = [:]
    private let context: ModelContext
    
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
        guard isExtensionSupportAvailable else { return }
        
        // Initialize extension controller
        extensionController = WKWebExtensionController()
        
        print("ExtensionManager: WKWebExtensionController initialized")
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
        // Create extensions directory if it doesn't exist
        let extensionsDir = getExtensionsDirectory()
        try FileManager.default.createDirectory(at: extensionsDir, withIntermediateDirectories: true)
        
        let extensionId = ExtensionUtils.generateExtensionId()
        let destinationDir = extensionsDir.appendingPathComponent(extensionId)
        
        // Handle both .zip files and directories
        var manifestURL: URL
        
        if sourceURL.pathExtension.lowercased() == "zip" {
            // Extract ZIP file
            try await extractZip(from: sourceURL, to: destinationDir)
            manifestURL = destinationDir.appendingPathComponent("manifest.json")
        } else {
            // Copy directory
            try FileManager.default.copyItem(at: sourceURL, to: destinationDir)
            manifestURL = destinationDir.appendingPathComponent("manifest.json")
        }
        
        // Validate manifest
        let manifest = try ExtensionUtils.validateManifest(at: manifestURL)
        
        // Create WKWebExtension
        let webExtension = try await WKWebExtension(resourceBaseURL: destinationDir)
        let context = try WKWebExtensionContext(for: webExtension)
        
        // Store context
        extensionContexts[extensionId] = context
        
        // Load extension context
        do {
            try extensionController?.load(context)
        } catch {
            throw ExtensionError.installationFailed("Failed to load extension context: \(error.localizedDescription)")
        }
        
        // Create extension entity
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
        
        // Create runtime model
        let installedExtension = InstalledExtension(from: entity, manifest: manifest)
        
        print("ExtensionManager: Successfully installed extension '\(installedExtension.name)' with ID: \(extensionId)")
        
        return installedExtension
    }
    
    private func extractZip(from zipURL: URL, to destinationURL: URL) async throws {
        // Use NSTask to extract zip (simple approach)
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
        // Look for icon in manifest
        if let icons = manifest["icons"] as? [String: String] {
            // Prefer larger icons
            for size in ["128", "64", "48", "32", "16"] {
                if let iconPath = icons[size] {
                    let fullPath = directory.appendingPathComponent(iconPath)
                    if FileManager.default.fileExists(atPath: fullPath.path) {
                        return fullPath.path
                    }
                }
            }
        }
        
        // Look for common icon files
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
        } catch {
            print("ExtensionManager: Failed to enable extension: \(error.localizedDescription)")
        }
        
        updateExtensionEnabled(extensionId, enabled: true)
    }
    
    func disableExtension(_ extensionId: String) {
        guard let context = extensionContexts[extensionId] else { return }
        
        do {
            try extensionController?.unload(context)
        } catch {
            print("ExtensionManager: Failed to disable extension: \(error.localizedDescription)")
        }
        updateExtensionEnabled(extensionId, enabled: false)
    }
    
    func uninstallExtension(_ extensionId: String) {
        // Remove from controller
        if let context = extensionContexts[extensionId] {
            do {
                try extensionController?.unload(context)
            } catch {
                print("ExtensionManager: Failed to unload extension context: \(error.localizedDescription)")
            }
            extensionContexts.removeValue(forKey: extensionId)
        }
        
        // Remove from database
        do {
            let predicate = #Predicate<ExtensionEntity> { $0.id == extensionId }
            let entities = try self.context.fetch(FetchDescriptor<ExtensionEntity>(predicate: predicate))
            
            for entity in entities {
                // Remove files
                let packageURL = URL(fileURLWithPath: entity.packagePath)
                try? FileManager.default.removeItem(at: packageURL)
                
                // Remove from database
                self.context.delete(entity)
            }
            
            try self.context.save()
            
            // Update UI
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
                    // Show success alert if needed
                case .failure(let error):
                    print("Failed to install extension: \(error.localizedDescription)")
                    // Show error alert
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
                // Try to load manifest
                let manifestURL = URL(fileURLWithPath: entity.packagePath).appendingPathComponent("manifest.json")
                
                do {
                    let manifest = try ExtensionUtils.validateManifest(at: manifestURL)
                    let installedExtension = InstalledExtension(from: entity, manifest: manifest)
                    loadedExtensions.append(installedExtension)
                    
                    // Recreate WKWebExtension if enabled
                    if entity.isEnabled {
                        Task {
                            do {
                                let webExtension = try await WKWebExtension(resourceBaseURL: URL(fileURLWithPath: entity.packagePath))
                                let webContext = try WKWebExtensionContext(for: webExtension)
                                
                                extensionContexts[entity.id] = webContext
                                do {
                                    try extensionController?.load(webContext)
                                } catch {
                                    print("ExtensionManager: Failed to load extension context on startup: \(error.localizedDescription)")
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
            print("ExtensionManager: Loaded \(loadedExtensions.count) extensions")
            
        } catch {
            print("ExtensionManager: Failed to load installed extensions: \(error)")
        }
    }
    
    private func getExtensionsDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Pulse").appendingPathComponent("Extensions")
    }
}

// MARK: - Permission Management
@available(macOS 15.4, *)
extension ExtensionManager {
    
    func requestPermissions(for extensionId: String, permissions: [String], hostPermissions: [String]) -> (Set<String>, Set<String>) {
        // For now, auto-grant safe permissions during development
        // In production, this would show the permission UI
        
        let safePermissions: Set<String> = ["storage", "activeTab"]
        let grantedPermissions = Set(permissions.filter { safePermissions.contains($0) })
        
        // Store granted permissions
        for permission in grantedPermissions {
            storePermission(extensionId: extensionId, permission: permission, granted: true)
        }
        
        // For development, allow localhost and common dev domains
        let devHostPermissions: Set<String> = hostPermissions.filter { host in
            host.contains("localhost") || host.contains("127.0.0.1") || host.contains("github.com")
        }.reduce(into: Set<String>()) { result, host in
            result.insert(host)
        }
        
        for host in devHostPermissions {
            storeHostPermission(extensionId: extensionId, host: host, granted: true)
        }
        
        return (grantedPermissions, devHostPermissions)
    }
    
    func showPermissionDialog(extensionName: String, permissions: [String], hostPermissions: [String], completion: @escaping (Set<String>, Set<String>) -> Void) {
        // This would show the permission UI dialog
        // For now, we'll use the auto-grant logic above
        let (grantedPerms, grantedHosts) = requestPermissions(for: "", permissions: permissions, hostPermissions: hostPermissions)
        completion(grantedPerms, grantedHosts)
    }
    
    private func storePermission(extensionId: String, permission: String, granted: Bool) {
        let permissionEntity = ExtensionPermissionEntity(
            extensionId: extensionId,
            permission: permission,
            granted: granted,
            grantDate: granted ? Date() : nil
        )
        
        self.context.insert(permissionEntity)
        try? self.context.save()
    }
    
    func storeHostPermission(extensionId: String, host: String, granted: Bool, isTemporary: Bool = false) {
        let hostPermissionEntity = ExtensionHostPermissionEntity(
            extensionId: extensionId,
            host: host,
            granted: granted,
            grantDate: granted ? Date() : nil,
            isTemporary: isTemporary
        )
        
        self.context.insert(hostPermissionEntity)
        try? self.context.save()
    }
    
    func getGrantedPermissions(for extensionId: String) -> [String] {
        do {
            let predicate = #Predicate<ExtensionPermissionEntity> { 
                $0.extensionId == extensionId && $0.granted == true 
            }
            let permissions = try self.context.fetch(FetchDescriptor<ExtensionPermissionEntity>(predicate: predicate))
            return permissions.map { $0.permission }
        } catch {
            print("ExtensionManager: Failed to fetch permissions: \(error)")
            return []
        }
    }
    
    func getGrantedHostPermissions(for extensionId: String) -> [String] {
        do {
            let predicate = #Predicate<ExtensionHostPermissionEntity> { 
                $0.extensionId == extensionId && $0.granted == true 
            }
            let hostPermissions = try self.context.fetch(FetchDescriptor<ExtensionHostPermissionEntity>(predicate: predicate))
            return hostPermissions.map { $0.host }
        } catch {
            print("ExtensionManager: Failed to fetch host permissions: \(error)")
            return []
        }
    }
}