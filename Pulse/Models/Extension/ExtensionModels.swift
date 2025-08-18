//
//  ExtensionModels.swift
//  Pulse
//
//  Created for WKWebExtension support
//

import Foundation
import SwiftData

@Model
final class ExtensionEntity {
    @Attribute(.unique) var id: String
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

@Model
final class ExtensionPermissionEntity {
    @Attribute(.unique) var id: UUID
    var extensionId: String
    var permission: String
    var granted: Bool
    var grantDate: Date?
    
    init(
        id: UUID = UUID(),
        extensionId: String,
        permission: String,
        granted: Bool,
        grantDate: Date? = nil
    ) {
        self.id = id
        self.extensionId = extensionId
        self.permission = permission
        self.granted = granted
        self.grantDate = grantDate
    }
}

@Model
final class ExtensionHostPermissionEntity {
    @Attribute(.unique) var id: UUID
    var extensionId: String
    var host: String
    var granted: Bool
    var grantDate: Date?
    var isTemporary: Bool // For activeTab permissions
    
    init(
        id: UUID = UUID(),
        extensionId: String,
        host: String,
        granted: Bool,
        grantDate: Date? = nil,
        isTemporary: Bool = false
    ) {
        self.id = id
        self.extensionId = extensionId
        self.host = host
        self.granted = granted
        self.grantDate = grantDate
        self.isTemporary = isTemporary
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

struct ExtensionPermission {
    let permission: String
    let granted: Bool
    let grantDate: Date?
    
    init(from entity: ExtensionPermissionEntity) {
        self.permission = entity.permission
        self.granted = entity.granted
        self.grantDate = entity.grantDate
    }
}

struct ExtensionHostPermission {
    let host: String
    let granted: Bool
    let grantDate: Date?
    let isTemporary: Bool
    
    init(from entity: ExtensionHostPermissionEntity) {
        self.host = entity.host
        self.granted = entity.granted
        self.grantDate = entity.grantDate
        self.isTemporary = entity.isTemporary
    }
}