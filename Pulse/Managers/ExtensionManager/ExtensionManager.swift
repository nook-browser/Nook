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

@available(macOS 15.4, *)
@MainActor
final class ExtensionManager: NSObject, ObservableObject, WKWebExtensionControllerDelegate {
    static let shared = ExtensionManager()
    
    @Published var installedExtensions: [InstalledExtension] = []
    @Published var isExtensionSupportAvailable: Bool = false
    
    private var extensionController: WKWebExtensionController?
    private var extensionContexts: [String: WKWebExtensionContext] = [:]
    
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
        extensionController = WKWebExtensionController()
        extensionController?.delegate = self
        print("ExtensionManager: Native WKWebExtensionController initialized with delegate")
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
    
    // MARK: - WKWebExtensionControllerDelegate
    
    func webExtensionController(_ controller: WKWebExtensionController, presentActionPopup action: WKWebExtension.Action, for extensionContext: WKWebExtensionContext, completionHandler: @escaping (Error?) -> Void) {
        print("🎉 DELEGATE: Extension wants to present popup!")
        print("   Action: \(action)")
        print("   Extension: \(extensionContext.webExtension.displayName ?? "Unknown")")
        
        // Get the native popover from the action
        if let popover = action.popupPopover {
            print("✅ DELEGATE: Native popover available - presenting!")
            
            // Show the popover
            DispatchQueue.main.async {
                if let window = NSApp.mainWindow,
                   let contentView = window.contentView {
                    
                    // Find a better position for the popover - maybe relative to the toolbar
                    let buttonRect = CGRect(x: 100, y: window.frame.height - 100, width: 20, height: 20)
                    popover.show(relativeTo: buttonRect, of: contentView, preferredEdge: .minY)
                    
                    // Complete successfully
                    completionHandler(nil)
                } else {
                    print("❌ DELEGATE: No window/contentView available")
                    completionHandler(NSError(domain: "ExtensionManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "No window available"]))
                }
            }
        } else {
            print("❌ DELEGATE: No popover available on action")
            completionHandler(NSError(domain: "ExtensionManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "No popover available"]))
        }
    }
}
