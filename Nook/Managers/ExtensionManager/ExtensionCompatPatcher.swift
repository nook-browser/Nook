// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionCompatPatcher.swift
//  Nook
//
//  Loads Nook's compatibility shim first in every context of a store-built extension package.
//  Foundation only: scripts/tests/ExtensionCompatPatcherCheck.swift compiles this file directly.
//

import Foundation

enum ExtensionCompatPatcher {
    /// The browser a store build was made for, which the shim tells it it runs in.
    enum Identity: String {
        case chrome, edge, firefox
    }

    static let shimFile = "nook_compat.js"
    static let workerFile = "nook_compat_worker.js"
    static let stateFile = "nook_compat.json"
    static let identityToken = "__NOOK_IDENTITY__"
    static let channelToken = "__NOOK_OWNS_CHANNEL__"
    static let backgroundToken = "__NOOK_BACKGROUND_SHIM__"
    /// Quotes included: the shim holds it as a string, and gets a string holding a JSON list.
    static let emptyScriptsToken = "'__NOOK_EMPTY_SCRIPTS__'"
    private static let maxEmptyScripts = 64
    /// The permission the shim's channel to Nook rides on (`runtime.sendNativeMessage`).
    static let channelPermission = "nativeMessaging"
    /// Permissions whose APIs `ExtensionCompatBridge` answers natively. A package that declares
    /// one gets the channel; a package that declares none is left without it.
    static let bridgedPermissions: Set<String> = ["offscreen", "webNavigation", "idle", "notifications", "management", "identity", "sidePanel"]
    static let pageTag = "<script src=\"/\(shimFile)\"></script>"
    private static let maxPageBytes = 4 << 20

    /// Puts the shim in the package at `root` and first in every context `manifest` declares, and
    /// returns true when `manifest` changed. Safe to repeat: it runs at install and at every launch.
    @discardableResult
    static func patch(manifest: inout [String: Any], packageAt root: URL, shim: String, identity: Identity) -> Bool {
        // The package is walked once: the shim file is written last and marks it done.
        var empty = emptyScripts(packageAt: root)
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent(shimFile).path) {
            // A record that is here before Nook's first pass is the package's own, and says nothing.
            if let record = location(of: stateFile, in: root) { try? FileManager.default.removeItem(at: record) }
            patchPages(in: root, named: namedPages(manifest))
            empty = findEmptyScripts(in: root)
        }
        var changed = patchBackground(&manifest, root: root)
        if patchContentScripts(&manifest) { changed = true }
        var ownsChannel = addedPermissions(packageAt: root).contains(channelPermission)
        if patchChannel(&manifest) {
            changed = true
            ownsChannel = true
        }
        var record: [String: Any] = [:]
        if ownsChannel { record["addedPermissions"] = [channelPermission] }
        if !empty.isEmpty { record["emptyScripts"] = empty }
        if !record.isEmpty { write(json(record), to: stateFile, in: root) }
        let text = shim.replacingOccurrences(of: identityToken, with: identity.rawValue)
            .replacingOccurrences(of: channelToken, with: ownsChannel ? "true" : "false")
            .replacingOccurrences(of: backgroundToken, with: backgroundHasShim(manifest, root: root) ? "true" : "false")
            .replacingOccurrences(of: emptyScriptsToken, with: jsString(json(empty)))
        write(text, to: shimFile, in: root)
        return changed
    }

    /// The scripts in the package at `root` that hold nothing, as Nook recorded them on its first
    /// pass. The shim leaves them out of a worker's imports.
    static func emptyScripts(packageAt root: URL) -> [String] {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(stateFile)),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return Array((state["emptyScripts"] as? [String] ?? []).filter { $0.count <= 512 }.prefix(maxEmptyScripts))
    }

    /// What Nook added to the package at `root`: the channel permission, or nothing. It stays out
    /// of the consent sheet, so no other name is ever taken from the record, whoever wrote it.
    static func addedPermissions(packageAt root: URL) -> Set<String> {
        guard let data = try? Data(contentsOf: root.appendingPathComponent(stateFile)),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [] }
        return Set(state["addedPermissions"] as? [String] ?? []).intersection([channelPermission])
    }

    /// A package that was just staged holds nothing of Nook's. A file under one of Nook's names
    /// is the package's own, and is removed before anything reads it.
    static func disown(packageAt root: URL) {
        for name in [stateFile, shimFile] {
            if let url = location(of: name, in: root) { try? FileManager.default.removeItem(at: url) }
        }
    }

    /// A store build's manifest names itself `__MSG_extName__`, so the short name and the
    /// known install IDs count too.
    static func isBitwarden(manifest: [String: Any], extensionId: String, knownIDs: Set<String>) -> Bool {
        knownIDs.contains(extensionId)
            || [manifest["name"], manifest["short_name"]].contains { ($0 as? String)?.contains("Bitwarden") == true }
    }

    // MARK: - Background

    /// A service worker is replaced by a wrapper beside it that loads the shim, then the worker.
    /// Background scripts get the shim as their first entry. A background page is an HTML page.
    private static func patchBackground(_ manifest: inout [String: Any], root: URL) -> Bool {
        guard var background = manifest["background"] as? [String: Any] else { return false }
        var changed = false
        if let worker = (background["service_worker"] as? String).map(packagePath), !worker.isEmpty,
           (worker as NSString).lastPathComponent != workerFile {
            let directory = (worker as NSString).deletingLastPathComponent
            let wrapper = directory.isEmpty ? workerFile : directory + "/" + workerFile
            let shim = jsString("/" + shimFile)
            let original = jsString("./" + (worker as NSString).lastPathComponent)
            // A classic worker survives a shim that fails to load. A module's imports are all or nothing.
            let source = (background["type"] as? String) == "module"
                ? "import \(shim);\nimport \(original);\n"
                : "try { importScripts(\(shim)); } catch (e) {}\nimportScripts(\(original));\n"
            // The manifest points at the wrapper only once it is on disk, inside the package.
            if write(source, to: wrapper, in: root) {
                background["service_worker"] = wrapper
                changed = true
            }
        }
        if var scripts = background["scripts"] as? [String], !scripts.isEmpty, packagePath(scripts[0]) != shimFile {
            scripts.insert(shimFile, at: 0)
            background["scripts"] = scripts
            changed = true
        }
        if changed { manifest["background"] = background }
        return changed
    }

    /// True when the background `manifest` names loads the shim. The shim in a content script
    /// then waits for the one in the background before the extension's first message.
    private static func backgroundHasShim(_ manifest: [String: Any], root: URL) -> Bool {
        guard let background = manifest["background"] as? [String: Any] else { return false }
        if let worker = background["service_worker"] as? String { return (packagePath(worker) as NSString).lastPathComponent == workerFile }
        if let scripts = background["scripts"] as? [String], let first = scripts.first { return packagePath(first) == shimFile }
        guard let page = background["page"] as? String, let url = location(of: packagePath(page), in: root) else { return false }
        return (try? String(contentsOf: url, encoding: .utf8))?.contains(pageTag) == true
    }

    // MARK: - Channel

    /// Adds the channel permission when the manifest declares an API the bridge answers and
    /// does not already require native messaging itself.
    private static func patchChannel(_ manifest: inout [String: Any]) -> Bool {
        var permissions = manifest["permissions"] as? [Any] ?? []
        let declared = Set(permissions.compactMap { $0 as? String })
        guard !declared.isDisjoint(with: bridgedPermissions), !declared.contains(channelPermission) else { return false }
        permissions.append(channelPermission)
        manifest["permissions"] = permissions
        return true
    }

    // MARK: - Content scripts

    private static func patchContentScripts(_ manifest: inout [String: Any]) -> Bool {
        guard var entries = manifest["content_scripts"] as? [[String: Any]] else { return false }
        var changed = false
        for index in entries.indices {
            guard var scripts = entries[index]["js"] as? [String], !scripts.isEmpty,
                  // The MAIN world is the site's own. The shim never runs there.
                  (entries[index]["world"] as? String)?.uppercased() != "MAIN",
                  // Nook's bridge entries are compared whole by the code that writes them.
                  !scripts.allSatisfy({ packagePath($0).hasPrefix("nook_") }),
                  packagePath(scripts[0]) != shimFile
            else { continue }
            scripts.insert(shimFile, at: 0)
            entries[index]["js"] = scripts
            changed = true
        }
        if changed { manifest["content_scripts"] = entries }
        return changed
    }

    // MARK: - Pages

    /// Adds the shim's script tag to the HTML pages in the package.
    private static func patchPages(in root: URL, named: Set<String>) {
        // Paths come back relative to the package, and a link to a folder is not followed.
        guard let files = FileManager.default.enumerator(atPath: root.path) else { return }
        for case let path as String in files where ["html", "htm"].contains((path as NSString).pathExtension.lowercased()) {
            guard files.fileAttributes?[.type] as? FileAttributeType == .typeRegular,
                  (files.fileAttributes?[.size] as? Int ?? 0) < maxPageBytes,
                  let html = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8),
                  let patched = pageWithShim(html, named: named.contains(path.lowercased()))
            else { continue }
            write(patched, to: path, in: root)
        }
    }

    /// Package paths of the scripts that hold only white space.
    private static func findEmptyScripts(in root: URL) -> [String] {
        guard let files = FileManager.default.enumerator(atPath: root.path) else { return [] }
        var found: [String] = []
        for case let path as String in files where (path as NSString).pathExtension.lowercased() == "js" {
            guard files.fileAttributes?[.type] as? FileAttributeType == .typeRegular,
                  (files.fileAttributes?[.size] as? Int ?? .max) <= 16, path.count <= 512,
                  let text = try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8),
                  text.allSatisfy(\.isWhitespace)
            else { continue }
            found.append(path)
        }
        return Array(found.sorted().prefix(maxEmptyScripts))
    }

    /// The HTML files the manifest itself loads as pages, as lowercased package paths.
    static func namedPages(_ manifest: [String: Any]) -> Set<String> {
        func entry(_ key: String) -> [String: Any] { manifest[key] as? [String: Any] ?? [:] }
        var pages: [Any?] = [
            entry("background")["page"], entry("action")["default_popup"], entry("browser_action")["default_popup"],
            entry("page_action")["default_popup"], manifest["options_page"], entry("options_ui")["page"],
            manifest["devtools_page"], entry("side_panel")["default_path"], entry("sidebar_action")["default_panel"],
        ]
        pages += Array(entry("chrome_url_overrides").values)
        pages += entry("sandbox")["pages"] as? [Any] ?? []
        // `popup.html?tab=1#x` names the file popup.html.
        return Set(pages.compactMap { $0 as? String }.map { page in
            packagePath(String(page.prefix { $0 != "?" && $0 != "#" })).lowercased()
        })
    }

    /// `html` with the shim as the first script its head runs. Nil leaves the file alone: it has
    /// the tag already, or it is a fragment, with no document tags and no mention in the manifest.
    static func pageWithShim(_ html: String, named: Bool) -> String? {
        guard !html.contains(pageTag) else { return nil }
        // Ahead of the doctype the tag would put the page in quirks mode, so that is the last resort.
        for pattern in ["<head(\\s[^>]*)?>", "<html(\\s[^>]*)?>", "<!doctype[^>]*>"] {
            if let tag = html.range(of: pattern, options: [.regularExpression, .caseInsensitive]) {
                return html.replacingCharacters(in: tag.upperBound..<tag.upperBound, with: pageTag)
            }
        }
        return named ? pageTag + html : nil
    }

    // MARK: - Helpers

    /// A manifest path as a plain relative path: no leading `./` or `/`.
    private static func packagePath(_ path: String) -> String {
        var path = path.replacingOccurrences(of: "\\", with: "/")
        while path.hasPrefix("./") { path.removeFirst(2) }
        while path.hasPrefix("/") { path.removeFirst() }
        return path
    }

    private static func jsString(_ value: String) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    /// Compact JSON with its keys in order, so the same value is always the same text.
    private static func json(_ value: Any) -> String {
        let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    /// Where `path` is inside the package, or nil when it leaves it through `..` or a symbolic
    /// link. The manifest is the package's own word and does not get to say where Nook writes.
    static func location(of path: String, in root: URL) -> URL? {
        guard !path.isEmpty, !path.split(separator: "/").contains("..") else { return nil }
        let url = root.appendingPathComponent(path)
        let package = root.resolvingSymlinksInPath().path
        let folder = url.deletingLastPathComponent().resolvingSymlinksInPath().path
        return folder == package || folder.hasPrefix(package + "/") ? url : nil
    }

    /// The one place the patcher writes. True when the file holds `text` afterwards; a file
    /// that already does is not touched, so a relaunch changes nothing.
    @discardableResult
    private static func write(_ text: String, to path: String, in root: URL) -> Bool {
        guard let url = location(of: path, in: root) else { return false }
        if (try? String(contentsOf: url, encoding: .utf8)) == text { return true }
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil
    }
}
