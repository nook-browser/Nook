//
//  ExtensionUtils.swift
//  Nook
//
//  Created for WKWebExtension support
//

import Foundation

@MainActor
struct ExtensionUtils {
    /// Check if the current OS supports WKWebExtension APIs we rely on
    /// We target the newest OS that includes `world` support for scripting/content scripts.
    /// Requires iOS/iPadOS 18.5+ or macOS 15.5+.
    static var isExtensionSupportAvailable: Bool {
        if #available(iOS 18.5, macOS 15.5, *) { return true }
        return false
    }

    /// Whether MAIN/ISOLATED execution worlds are supported for `chrome.scripting` and content scripts.
    /// Newer WebKit builds honor `world: 'MAIN'|'ISOLATED'` and `content_scripts[].world`.
    static var isWorldInjectionSupported: Bool {
        if #available(iOS 18.5, macOS 15.5, *) { return true }
        return false
    }
    
    /// Show an alert when extensions are not available on older OS versions
    static func showUnsupportedOSAlert() {
        // This will be implemented when we add alert functionality
        print("Extensions require iOS 18.5+ or macOS 15.5+")
    }
    
    /// Validate a manifest.json file structure
    static func validateManifest(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let manifest = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ExtensionError.invalidManifest("Invalid JSON structure")
        }
        
        // Basic manifest validation
        guard let _ = manifest["manifest_version"] as? Int else {
            throw ExtensionError.invalidManifest("Missing manifest_version")
        }
        
        guard let _ = manifest["name"] as? String else {
            throw ExtensionError.invalidManifest("Missing name")
        }
        
        guard let _ = manifest["version"] as? String else {
            throw ExtensionError.invalidManifest("Missing version")
        }
        
        return manifest
    }
    
    /// Generate a unique extension identifier
    static func generateExtensionId() -> String {
        return UUID().uuidString.lowercased()
    }
}

enum ExtensionError: LocalizedError {
    case unsupportedOS
    case invalidManifest(String)
    case installationFailed(String)
    case permissionDenied
    
    var errorDescription: String? {
        switch self {
        case .unsupportedOS:
            return "Extensions require iOS 18.5+ or macOS 15.5+"
        case .invalidManifest(let reason):
            return "Invalid manifest.json: \(reason)"
        case .installationFailed(let reason):
            return "Installation failed: \(reason)"
        case .permissionDenied:
            return "Permission denied"
        }
    }
}
