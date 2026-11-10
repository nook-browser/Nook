// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionCompatManagement.swift
//  Nook
//
//  `chrome.management`, read only: what is installed, and when that changes. Nothing here
//  enables, disables or removes an extension. Foundation and WebKit only.
//

import Foundation
import WebKit

@MainActor
final class ExtensionCompatManagement: ExtensionCompatAPI {
    let name = "management"
    let permission: String? = "management"
    private weak var bridge: ExtensionCompatBridge?

    /// One installed extension, as the app knows it.
    struct Info {
        var id: String
        var name: String
        var version: String
        var description: String
        var enabled: Bool
        /// The package's manifest. Permissions Nook added to it are named in `added`.
        var manifest: [String: Any]
        var added: Set<String> = []
        /// Where its pages load from. Nil while it is disabled.
        var baseURL: URL?
    }

    enum Change {
        case installed(Info), enabled(Info), disabled(Info), uninstalled(String)
    }

    /// Everything installed, enabled or not. The app supplies it.
    var installed: () -> [Info] = { [] }
    /// The loaded extensions, which are the ones that can be told of a change.
    var contexts: () -> [WKWebExtensionContext] = { [] }

    init(bridge: ExtensionCompatBridge) { self.bridge = bridge }

    /// Chrome's `ExtensionInfo`. The icons are left out: Chrome serves them from a URL of its own.
    static func extensionInfo(_ info: Info) -> [String: Any] {
        let manifest = info.manifest
        func text(_ key: String) -> String? {
            guard let value = manifest[key] as? String, !value.isEmpty, !value.hasPrefix("__MSG_") else { return nil }
            return value
        }
        // MV2 lists hosts among its permissions; MV3 keeps them apart.
        let listed = (manifest["permissions"] as? [Any] ?? []).compactMap { $0 as? String }.filter { !info.added.contains($0) }
        func isHost(_ value: String) -> Bool { value.contains("://") || value == "<all_urls>" }
        let options = (manifest["options_ui"] as? [String: Any])?["page"] as? String ?? manifest["options_page"] as? String
        var out: [String: Any] = [
            "id": info.id, "name": info.name, "shortName": text("short_name") ?? info.name, "description": info.description,
            "version": info.version, "enabled": info.enabled, "mayDisable": true, "mayEnable": true, "isApp": false,
            "type": manifest["theme"] != nil ? "theme" : "extension", "offlineEnabled": false, "installType": "normal",
            "permissions": listed.filter { !isHost($0) },
            "hostPermissions": listed.filter(isHost) + (manifest["host_permissions"] as? [Any] ?? []).compactMap { $0 as? String },
            "optionsUrl": options.flatMap { page in info.baseURL.flatMap { URL(string: page, relativeTo: $0.appendingPathComponent(""))?.absoluteString } } ?? "",
        ]
        out["homepageUrl"] = text("homepage_url")
        out["updateUrl"] = text("update_url")
        out["versionName"] = text("version_name")
        return out
    }

    func call(_ method: String, _ arguments: [Any], from context: WKWebExtensionContext,
              reply: @escaping (Result<Any?, ExtensionCompatError>) -> Void) {
        let all = installed()
        switch method {
        case "getAll":
            reply(.success(all.map(Self.extensionInfo)))
        case "get", "getSelf":
            let id = method == "getSelf" ? context.uniqueIdentifier : arguments.first as? String
            guard let found = all.first(where: { $0.id == id }) else {
                return reply(.failure(ExtensionCompatError("Failed to find extension with id \(id ?? "")")))
            }
            reply(.success(Self.extensionInfo(found)))
        case "getPermissionWarningById", "getPermissionWarningByManifest":
            reply(.success([String]()))
        default:
            // Nothing that changes what is installed: setEnabled, uninstall, uninstallSelf and the app calls.
            reply(.failure(ExtensionCompatError("management.\(method) is not available")))
        }
    }

    /// Tells every other extension that asked for `management` and listens.
    func changed(_ change: Change) {
        let event: String, argument: Any, subject: String
        switch change {
        case .installed(let info): (event, argument, subject) = ("onInstalled", Self.extensionInfo(info), info.id)
        case .enabled(let info): (event, argument, subject) = ("onEnabled", Self.extensionInfo(info), info.id)
        case .disabled(let info): (event, argument, subject) = ("onDisabled", Self.extensionInfo(info), info.id)
        case .uninstalled(let id): (event, argument, subject) = ("onUninstalled", id, id)
        }
        for context in contexts() where context.uniqueIdentifier != subject && ExtensionCompatBridge.declares("management", in: context) {
            bridge?.emit("management." + event, [argument], to: context)
        }
    }
}
