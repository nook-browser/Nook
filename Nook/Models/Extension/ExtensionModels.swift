// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionModels.swift
//  Nook
//
//  Simplified extension models using native WKWebExtension support
//

import AppKit
import Foundation
import SwiftData

@Model
final class ExtensionEntity {
    @Attribute(.unique) var id: String
    // Extensions are global: one install, one enabled state, and one storage namespace
    // shared by every profile. Private windows see only extensions allowed there.
    var name: String
    var version: String
    var manifestVersion: Int
    var extensionDescription: String?
    var isEnabled: Bool
    var installDate: Date
    var lastUpdateDate: Date
    var packagePath: String // Path to the extension package
    var iconPath: String?
    var grantedOptionalPermissions: [String]?
    var grantedOptionalMatchPatterns: [String]?
    var origin: String?
    var safariAppPath: String?
    /// Copy of a store `origin` for builds that predate `origin`; they read it to find updates.
    var sourceStore: String?
    /// Runs in private windows (`WKWebExtensionContext.hasAccessToPrivateData`). Off by default.
    var allowsPrivateBrowsing: Bool = false

    var source: ExtensionSource {
        get { ExtensionSource(origin: origin, appPath: safariAppPath) ?? .file }
        set {
            origin = newValue.origin
            safariAppPath = newValue.appPath
            sourceStore = newValue.store?.rawValue
        }
    }

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
        iconPath: String? = nil,
        grantedOptionalPermissions: [String] = [],
        grantedOptionalMatchPatterns: [String] = []
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
        self.grantedOptionalPermissions = grantedOptionalPermissions
        self.grantedOptionalMatchPatterns = grantedOptionalMatchPatterns
    }
}

enum ExtensionSource {
    case store(ExtensionStore)
    case safari(appPath: String?)
    case file

    init?(origin: String?, appPath: String?) {
        switch origin {
        case "safari": self = .safari(appPath: appPath)
        case "file": self = .file
        case let origin?:
            guard let store = ExtensionStore(rawValue: origin) else { return nil }
            self = .store(store)
        case nil: return nil
        }
    }

    /// For a row saved without `origin`: installed before it existed, or saved by an older build.
    init(inferredFrom entity: ExtensionEntity) {
        if let store = entity.sourceStore.flatMap(ExtensionStore.init(rawValue:)) {
            self = .store(store)
        } else if entity.safariAppPath != nil || entity.id.contains(".") {
            // A Safari extension's ID is its bundle identifier, the only kind of extension ID with a dot.
            self = .safari(appPath: entity.safariAppPath)
        } else {
            self = .file
        }
    }

    var origin: String {
        switch self {
        case .store(let store): store.rawValue
        case .safari: "safari"
        case .file: "file"
        }
    }

    var store: ExtensionStore? {
        guard case .store(let store) = self else { return nil }
        return store
    }

    var appPath: String? {
        guard case .safari(let appPath) = self else { return nil }
        return appPath
    }

    var isSafari: Bool {
        if case .safari = self { return true }
        return false
    }

    var appName: String? {
        appPath.map { URL(fileURLWithPath: $0).lastPathComponent }
    }

    var name: String {
        switch self {
        case .store(let store): store.name
        case .safari: "Safari"
        case .file: "From a file"
        }
    }

    var versionName: String {
        switch self {
        case .store(let store): store.name
        case .safari: "Safari"
        case .file: "file"
        }
    }

    var consentLine: String {
        switch self {
        case .store(let store): "From the \(store.name)"
        case .safari: appName.map { "From \($0)" } ?? "From a Safari extension"
        case .file: "From a file"
        }
    }

    func summary(version: String) -> String {
        [name, appName, version].compactMap { $0 }.joined(separator: " · ")
    }
}

enum ExtensionVersion {
    /// Chrome version strings are up to four dot-separated integers.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let lhs = a.split(separator: ".").map { Int($0) ?? 0 }
        let rhs = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(lhs.count, rhs.count) {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

/// An extension found in another browser or in an app on this Mac that Nook can install.
struct ExtensionOffer: Identifiable {
    enum Package {
        case store(ExtensionStore)
        case safari(ExtensionManager.SafariExtensionInfo)
    }

    let id: String
    let name: String
    let version: String
    let icon: NSImage?
    let package: Package

    var isSafari: Bool {
        if case .safari = package { true } else { false }
    }
}

extension ExtensionOffer {
    init(_ info: ExtensionManager.SafariExtensionInfo) {
        self.init(
            id: info.id, name: info.name, version: info.version,
            icon: NSWorkspace.shared.icon(forFile: info.appPath.path), package: .safari(info)
        )
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
    let allowsPrivateBrowsing: Bool
    let installDate: Date
    let lastUpdateDate: Date
    let packagePath: String
    let iconPath: String?
    let source: ExtensionSource
    let manifest: [String: Any]

    init(from entity: ExtensionEntity, manifest: [String: Any]) {
        self.id = entity.id
        self.name = entity.name
        self.version = entity.version
        self.manifestVersion = entity.manifestVersion
        self.description = entity.extensionDescription
        self.isEnabled = entity.isEnabled
        self.allowsPrivateBrowsing = entity.allowsPrivateBrowsing
        self.installDate = entity.installDate
        self.lastUpdateDate = entity.lastUpdateDate
        self.packagePath = entity.packagePath
        self.iconPath = entity.iconPath
        self.source = entity.source
        self.manifest = manifest
    }
}
