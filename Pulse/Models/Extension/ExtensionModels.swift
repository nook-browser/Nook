//
//  ExtensionModels.swift
//  Pulse
//
//  Simplified extension models using native WKWebExtension support
//

import Foundation
import SwiftData

@Model
final class ExtensionEntity {
    @Attribute(.unique) var id: String
    // Installation scope note: Extensions are installed/enabled globally across profiles.
    // Storage/state for extensions is profile-isolated via ExtensionManager data stores.
    var name: String
    var version: String
    var manifestVersion: Int
    var extensionDescription: String?
    var isEnabled: Bool
    var installDate: Date
    var lastUpdateDate: Date
    var packagePath: String // Path to the extension package
    var iconPath: String?
    
    init(
        id: String,
        name: String,
        version: String,
        manifestVersion: Int,
        extensionDescription: String? = nil,
        isEnabled: Bool = true,
        installDate: Date = Date(),
        lastUpdateDate: Date = Date(),
        packagePath: String,
        iconPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.manifestVersion = manifestVersion
        self.extensionDescription = extensionDescription
        self.isEnabled = isEnabled
        self.installDate = installDate
        self.lastUpdateDate = lastUpdateDate
        self.packagePath = packagePath
        self.iconPath = iconPath
    }
}

// Runtime models (not persisted)
struct InstalledExtension {
    let id: String
    let name: String
    let version: String
    let manifestVersion: Int
    let description: String?
    let isEnabled: Bool
    let installDate: Date
    let lastUpdateDate: Date
    let packagePath: String
    let iconPath: String?
    let manifest: [String: Any]
    
    init(from entity: ExtensionEntity, manifest: [String: Any]) {
        self.id = entity.id
        self.name = entity.name
        self.version = entity.version
        self.manifestVersion = entity.manifestVersion
        self.description = entity.extensionDescription
        self.isEnabled = entity.isEnabled
        self.installDate = entity.installDate
        self.lastUpdateDate = entity.lastUpdateDate
        self.packagePath = entity.packagePath
        self.iconPath = entity.iconPath
        self.manifest = manifest
    }
}
