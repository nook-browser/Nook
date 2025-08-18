//
//  ExtensionUtils.swift
//  Pulse
//
//  Created for WKWebExtension support
//

import Foundation

@MainActor
struct ExtensionUtils {
    /// Check if the current OS supports WKWebExtension APIs
    /// Requires iOS/iPadOS 18.4+ or macOS 15.4+
    static var isExtensionSupportAvailable: Bool {
        if #available(iOS 18.4, macOS 15.4, *) {
            return true
        } else {
            return false
        }
    }
    
    /// Show an alert when extensions are not available on older OS versions
    static func showUnsupportedOSAlert() {
        // This will be implemented when we add alert functionality
        print("Extensions require iOS 18.4+ or macOS 15.4+")
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
            return "Extensions require iOS 18.4+ or macOS 15.4+"
        case .invalidManifest(let reason):
            return "Invalid manifest.json: \(reason)"
        case .installationFailed(let reason):
            return "Installation failed: \(reason)"
        case .permissionDenied:
            return "Permission denied"
        }
    }
}