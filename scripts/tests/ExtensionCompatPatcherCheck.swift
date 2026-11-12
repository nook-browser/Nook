// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionCompatPatcherCheck.swift
//  Nook
//
//  The package patcher loads the shim first in every context of a package, and a second run
//  changes nothing. Compiles the shipped source directly:
//
//    swiftc Nook/Managers/ExtensionManager/ExtensionCompatPatcher.swift \
//           scripts/tests/ExtensionCompatPatcherCheck.swift \
//           -o /tmp/extension-compat-check && /tmp/extension-compat-check
//

import Foundation

@main
struct ExtensionCompatPatcherCheck {
    static let shim = "/* shim */ var identity = '__NOOK_IDENTITY__';"
    static let tag = "<script src=\"/nook_compat.js\"></script>"

    static func main() throws {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("extension-compat-check-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: tmp) }

        /// A package directory holding `files`, each a relative path and its text.
        func package(_ name: String, _ files: [String: String]) throws -> URL {
            let root = tmp.appendingPathComponent(name)
            for (path, text) in files {
                let url = root.appendingPathComponent(path)
                try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
            return root
        }
        func read(_ root: URL, _ path: String) -> String? {
            try? String(contentsOf: root.appendingPathComponent(path), encoding: .utf8)
        }
        /// Every file called `name` anywhere under the folders the climbing-path packages sit in.
        func strays(named name: String, under folder: URL) -> [String] {
            (fm.enumerator(atPath: folder.appendingPathComponent("escape").path)?.compactMap { $0 as? String } ?? [])
                .filter { ($0 as NSString).lastPathComponent == name }
        }
        func patch(_ manifest: inout [String: Any], _ root: URL, shim: String = Self.shim,
                   as identity: ExtensionCompatPatcher.Identity = .chrome) -> Bool {
            ExtensionCompatPatcher.patch(manifest: &manifest, packageAt: root, shim: shim, identity: identity)
        }

        // A classic worker in a subdirectory: the wrapper sits beside it and loads the shim, then the worker.
        var classic: [String: Any] = ["background": ["service_worker": "bg/sw.js"]]
        let classicRoot = try package("classic", ["bg/sw.js": "self.original = 1;", "popup.html": "<html><head><title>p</title></head></html>"])
        precondition(patch(&classic, classicRoot))
        precondition((classic["background"] as? [String: Any])?["service_worker"] as? String == "bg/nook_compat_worker.js")
        let classicWrapper = read(classicRoot, "bg/nook_compat_worker.js") ?? ""
        precondition(classicWrapper == "try { importScripts(\"/nook_compat.js\"); } catch (e) {}\nimportScripts(\"./sw.js\");\n", classicWrapper)
        precondition(read(classicRoot, "bg/sw.js") == "self.original = 1;")
        precondition(read(classicRoot, "nook_compat.js") == "/* shim */ var identity = 'chrome';")
        precondition(read(classicRoot, "popup.html") == "<html><head>\(tag)<title>p</title></head></html>")

        // A second run changes neither the manifest nor a file.
        let before = classic as NSDictionary
        let files = ["bg/nook_compat_worker.js", "bg/sw.js", "nook_compat.js", "popup.html"]
        let contents = files.map { read(classicRoot, $0) }
        precondition(!patch(&classic, classicRoot))
        precondition(before.isEqual(to: classic))
        precondition(files.map { read(classicRoot, $0) } == contents)

        // A newer shim replaces the file and leaves the wrapper, the manifest and the pages alone.
        precondition(!patch(&classic, classicRoot, shim: "/* v2 */ '__NOOK_IDENTITY__'", as: .firefox))
        precondition(read(classicRoot, "nook_compat.js") == "/* v2 */ 'firefox'")
        precondition(read(classicRoot, "popup.html")?.components(separatedBy: tag).count == 2)
        precondition(before.isEqual(to: classic))

        // A module worker imports both; a path written as ./sw.js is the same file.
        var module: [String: Any] = ["background": ["service_worker": "./sw.js", "type": "module"]]
        let moduleRoot = try package("module", ["sw.js": "export {};"])
        precondition(patch(&module, moduleRoot))
        precondition((module["background"] as? [String: Any])?["service_worker"] as? String == "nook_compat_worker.js")
        precondition(read(moduleRoot, "nook_compat_worker.js") == "import \"/nook_compat.js\";\nimport \"./sw.js\";\n")
        precondition(!patch(&module, moduleRoot))

        // A worker's file name is written as a string literal, whatever it holds.
        var quoted: [String: Any] = ["background": ["service_worker": "we\"ird.js"]]
        let quotedRoot = try package("quoted", ["we\"ird.js": ""])
        precondition(patch(&quoted, quotedRoot))
        precondition(read(quotedRoot, "nook_compat_worker.js")?.contains("importScripts(\"./we\\\"ird.js\");") == true)

        // A worker path that climbs out of the package is the manifest's word and is not followed:
        // nothing is written outside, and that background is left as it was.
        _ = try package("escape/outside", ["sw.js": ""])
        _ = try package("escape/nested/outside", ["sw.js": ""])
        for climbing in ["../../outside/sw.js", "bg/../../outside/sw.js", "/../outside/sw.js"] {
            var escape: [String: Any] = ["background": ["service_worker": climbing],
                                         "content_scripts": [["js": ["c.js"], "matches": ["<all_urls>"]]]]
            let escapeRoot = try package("escape/nested/pkg-\(abs(climbing.hashValue))", ["bg/keep.txt": "", "c.js": ""])
            precondition(patch(&escape, escapeRoot))  // the content script entry still changed
            precondition((escape["background"] as? [String: Any])?["service_worker"] as? String == climbing)
            precondition(read(escapeRoot, "nook_compat.js") != nil)
        }
        precondition(strays(named: "nook_compat_worker.js", under: tmp).isEmpty)
        precondition(ExtensionCompatPatcher.location(of: "a/../../b.js", in: tmp) == nil)
        precondition(ExtensionCompatPatcher.location(of: "a/b.js", in: tmp) != nil)

        // A folder inside the package that is a link to somewhere else is not written through.
        var linked: [String: Any] = ["background": ["service_worker": "bg/sw.js"]]
        let linkedRoot = try package("linked", ["manifest.json": "{}"])
        let elsewhere = try package("elsewhere", ["sw.js": "", "page.html": "<html></html>"])
        try fm.createSymbolicLink(at: linkedRoot.appendingPathComponent("bg"), withDestinationURL: elsewhere)
        precondition(!patch(&linked, linkedRoot))
        precondition((linked["background"] as? [String: Any])?["service_worker"] as? String == "bg/sw.js")
        precondition(read(elsewhere, "nook_compat_worker.js") == nil)
        precondition(read(elsewhere, "page.html") == "<html></html>")

        // A worker in a folder that does not exist gets no wrapper, so the manifest keeps its own path.
        var missing: [String: Any] = ["background": ["service_worker": "gone/sw.js"]]
        let missingRoot = try package("missing", ["manifest.json": "{}"])
        precondition(!patch(&missing, missingRoot))
        precondition((missing["background"] as? [String: Any])?["service_worker"] as? String == "gone/sw.js")

        // MV2 background scripts: the shim is the first entry, once.
        var scripts: [String: Any] = ["background": ["scripts": ["a.js", "b.js"]]]
        let scriptsRoot = try package("scripts", ["a.js": "", "b.js": ""])
        precondition(patch(&scripts, scriptsRoot))
        precondition((scripts["background"] as? [String: Any])?["scripts"] as? [String] == ["nook_compat.js", "a.js", "b.js"])
        precondition(!patch(&scripts, scriptsRoot))
        precondition((scripts["background"] as? [String: Any])?["scripts"] as? [String] == ["nook_compat.js", "a.js", "b.js"])

        // An MV2 background page is an HTML page like any other; its manifest entry stays.
        var page: [String: Any] = ["background": ["page": "bg/index.html"]]
        let pageRoot = try package("page", [
            "bg/index.html": "<!DOCTYPE html>\n<html>\n<head lang=\"en\">\n<script src=\"bg.js\"></script></head></html>",
            "deep/options.HTM": "<HTML><HEAD></HEAD></HTML>",
            "notes.txt": "<head>",
        ])
        precondition(!patch(&page, pageRoot))
        precondition((page["background"] as? [String: Any])?["page"] as? String == "bg/index.html")
        precondition(read(pageRoot, "bg/index.html") == "<!DOCTYPE html>\n<html>\n<head lang=\"en\">\(tag)\n<script src=\"bg.js\"></script></head></html>")
        precondition(read(pageRoot, "deep/options.HTM") == "<HTML><HEAD>\(tag)</HEAD></HTML>")
        precondition(read(pageRoot, "notes.txt") == "<head>")

        // Where the tag goes when a page has no head, and never twice.
        precondition(ExtensionCompatPatcher.pageWithShim("<html><header>h</header></html>", named: false) == "<html>\(tag)<header>h</header></html>")
        precondition(ExtensionCompatPatcher.pageWithShim("<!doctype html><p>x", named: false) == "<!doctype html>\(tag)<p>x")
        precondition(ExtensionCompatPatcher.pageWithShim("<head>\(tag)</head>", named: true) == nil)
        // A file with no document tags is a page only when the manifest names it. Otherwise it
        // is a fragment the extension inserts somewhere, and a script tag would change it.
        precondition(ExtensionCompatPatcher.pageWithShim("<p>x", named: true) == "\(tag)<p>x")
        precondition(ExtensionCompatPatcher.pageWithShim("<p>x", named: false) == nil)

        // Every kind of page a manifest can name, with a query or fragment after the file name.
        var pages: [String: Any] = [
            "action": ["default_popup": "popup.html?tab=1#top"],
            "options_ui": ["page": "/ui/Options.html"],
            "devtools_page": "devtools.html",
            "side_panel": ["default_path": "./panel.html"],
            "chrome_url_overrides": ["newtab": "newtab.html"],
            "sandbox": ["pages": ["sandbox.html"]],
        ]
        precondition(ExtensionCompatPatcher.namedPages(pages) == ["popup.html", "ui/options.html", "devtools.html", "panel.html", "newtab.html", "sandbox.html"])
        precondition(ExtensionCompatPatcher.namedPages(["browser_action": ["default_popup": "p.html"], "options_page": "o.html",
                                                        "background": ["page": "bg.html"]]) == ["p.html", "o.html", "bg.html"])
        let bareMarkup = "<div id=\"app\"></div><script src=\"app.js\"></script>"
        let pagesRoot = try package("pages", [
            "popup.html": bareMarkup, "ui/Options.html": bareMarkup, "panel.html": bareMarkup,
            "templates/row.html": "<tr class=\"row\"><td></td></tr>",
            "templates/card.html": "<template><div></div></template>",
            "help/index.html": "<html><body>help</body></html>",
        ])
        precondition(!patch(&pages, pagesRoot))
        for named in ["popup.html", "ui/Options.html", "panel.html"] {
            precondition(read(pagesRoot, named) == tag + bareMarkup, named)
        }
        precondition(read(pagesRoot, "templates/row.html") == "<tr class=\"row\"><td></td></tr>")
        precondition(read(pagesRoot, "templates/card.html") == "<template><div></div></template>")
        precondition(read(pagesRoot, "help/index.html") == "<html>\(tag)<body>help</body></html>")

        // Content scripts: isolated entries get the shim first. The page's world, a stylesheet
        // entry and Nook's own bridge entries are left as they are.
        var content: [String: Any] = ["content_scripts": [
            ["js": ["content.js"], "matches": ["<all_urls>"]],
            ["js": ["page.js"], "matches": ["<all_urls>"], "world": "MAIN"],
            ["css": ["style.css"], "matches": ["<all_urls>"]],
            ["js": ["nook_bridge.js"], "matches": ["https://example.com/*"]],
            ["js": ["./nook_compat.js", "late.js"], "matches": ["<all_urls>"]],
        ]]
        let contentRoot = try package("content", ["content.js": ""])
        precondition(patch(&content, contentRoot))
        let entries = (content["content_scripts"] as? [[String: Any]] ?? []).map { $0["js"] as? [String] }
        precondition(entries == [["nook_compat.js", "content.js"], ["page.js"], nil, ["nook_bridge.js"], ["./nook_compat.js", "late.js"]])
        precondition(!patch(&content, contentRoot))

        // A package with nothing to patch still gets the shim file, and reports no manifest change.
        var bare: [String: Any] = ["name": "bare"]
        let bareRoot = try package("bare", ["readme.txt": ""])
        precondition(!patch(&bare, bareRoot, as: .edge))
        precondition(read(bareRoot, "nook_compat.js") == "/* shim */ var identity = 'edge';")

        // The channel to Nook rides on nativeMessaging. A package that declares an API the bridge
        // answers gets the permission, and Nook records that the package never asked for it.
        let channelShim = "owns:__NOOK_OWNS_CHANNEL__ as:__NOOK_IDENTITY__"
        var bridged: [String: Any] = ["permissions": ["storage", "offscreen", "https://example.com/*"]]
        let bridgedRoot = try package("bridged", ["readme.txt": ""])
        precondition(patch(&bridged, bridgedRoot, shim: channelShim))
        precondition(bridged["permissions"] as? [String] == ["storage", "offscreen", "https://example.com/*", "nativeMessaging"])
        precondition(ExtensionCompatPatcher.addedPermissions(packageAt: bridgedRoot) == ["nativeMessaging"])
        precondition(read(bridgedRoot, "nook_compat.js") == "owns:true as:chrome")
        // The second run finds the permission already there and still knows whose it is.
        precondition(!patch(&bridged, bridgedRoot, shim: channelShim))
        precondition(bridged["permissions"] as? [String] == ["storage", "offscreen", "https://example.com/*", "nativeMessaging"])
        precondition(ExtensionCompatPatcher.addedPermissions(packageAt: bridgedRoot) == ["nativeMessaging"])
        precondition(read(bridgedRoot, "nook_compat.js") == "owns:true as:chrome")

        // An extension that asked for nativeMessaging itself keeps it as its own.
        var declared: [String: Any] = ["permissions": ["offscreen", "nativeMessaging"]]
        let declaredRoot = try package("declared", ["readme.txt": ""])
        precondition(!patch(&declared, declaredRoot, shim: channelShim))
        precondition(declared["permissions"] as? [String] == ["offscreen", "nativeMessaging"])
        precondition(ExtensionCompatPatcher.addedPermissions(packageAt: declaredRoot).isEmpty)
        precondition(read(declaredRoot, "nook_compat.js") == "owns:false as:chrome")

        // No API the bridge answers, no channel.
        var plain: [String: Any] = ["permissions": ["storage", "tabs"]]
        let plainRoot = try package("plain", ["readme.txt": ""])
        precondition(!patch(&plain, plainRoot, shim: channelShim))
        precondition(plain["permissions"] as? [String] == ["storage", "tabs"])
        precondition(read(plainRoot, "nook_compat.js") == "owns:false as:chrome")

        // What the consent sheet lists is what the package requests, less `addedPermissions`. A package
        // gets no say in that: the record it ships under Nook's file name is gone before anything reads it.
        let fake = "{\"addedPermissions\":[\"cookies\",\"history\",\"webRequest\",\"nativeMessaging\"]}"
        /// The install path: `disown`, then the patcher for a store build, then the names the sheet shows.
        func listed(_ name: String, _ permissions: [String], files: [String: String], store: Bool) throws -> Set<String> {
            var manifest: [String: Any] = ["permissions": permissions]
            let root = try package(name, files)
            ExtensionCompatPatcher.disown(packageAt: root)
            if store { _ = patch(&manifest, root, shim: channelShim) }
            return Set(permissions).subtracting(ExtensionCompatPatcher.addedPermissions(packageAt: root))
        }
        let greedy = ["cookies", "history", "webRequest", "storage"]
        for store in [true, false] {
            // Every name it tried to hide is listed, from a store or from a file.
            let hidden = try listed("hides-\(store)", greedy, files: ["nook_compat.json": fake], store: store)
            precondition(hidden == Set(greedy))
            // So is nativeMessaging when the package asks for it itself, with or without a shim file of its own making.
            let own = ["offscreen", "nativeMessaging"]
            let record = try listed("own-\(store)", own, files: ["nook_compat.json": fake], store: store)
            let both = try listed("own-shim-\(store)", own, files: ["nook_compat.json": fake, "nook_compat.js": "mine"], store: store)
            precondition(record == Set(own) && both == Set(own))
        }
        // The one name Nook does hide is the one it added.
        let added = try listed("added", ["offscreen", "cookies"], files: [:], store: true)
        precondition(added == ["offscreen", "cookies"])
        precondition(ExtensionCompatPatcher.addedPermissions(packageAt: bridgedRoot) == ["nativeMessaging"])

        // A package installed before this layer is first patched at a launch, with no `disown`:
        // the patcher itself drops a record that is there ahead of its own shim file.
        var forged: [String: Any] = ["permissions": ["nativeMessaging", "cookies"]]
        let forgedRoot = try package("forged", ["nook_compat.json": fake])
        precondition(!patch(&forged, forgedRoot, shim: channelShim))
        precondition(ExtensionCompatPatcher.addedPermissions(packageAt: forgedRoot).isEmpty)
        precondition(!FileManager.default.fileExists(atPath: forgedRoot.appendingPathComponent("nook_compat.json").path))
        precondition(read(forgedRoot, "nook_compat.js") == "owns:false as:chrome")
        // Whatever a record says, by whatever hand, only the channel permission is ever read from it.
        try fake.write(to: forgedRoot.appendingPathComponent("nook_compat.json"), atomically: true, encoding: .utf8)
        precondition(ExtensionCompatPatcher.addedPermissions(packageAt: forgedRoot) == ["nativeMessaging"])

        // A script that holds nothing is listed for the shim, which leaves it out of a worker's imports.
        // The list is made on the first pass and kept in Nook's record.
        let listShim = "empty:'__NOOK_EMPTY_SCRIPTS__' owns:__NOOK_OWNS_CHANNEL__"
        var importer: [String: Any] = ["background": ["service_worker": "sw.js"], "permissions": ["offscreen"]]
        let importerRoot = try package("importer", [
            "sw.js": "importScripts('/test.js');", "test.js": "\n", "lib/blank.js": "", "we\"ird'.js": " \t",
            "lib/real.js": "var a = 1;", "padded.js": String(repeating: " ", count: 17), "notes.txt": "",
        ])
        precondition(patch(&importer, importerRoot, shim: listShim))
        let empties = ["lib/blank.js", "test.js", "we\"ird'.js"]
        precondition(ExtensionCompatPatcher.emptyScripts(packageAt: importerRoot) == empties)
        // The shim gets the list as a string literal holding JSON, whatever the file names hold.
        let written = read(importerRoot, "nook_compat.js") ?? ""
        precondition(written.hasPrefix("empty:\"[") && written.hasSuffix(" owns:true"), written)
        let literal = Data(written.dropFirst("empty:".count).dropLast(" owns:true".count).utf8)
        let inner = try JSONSerialization.jsonObject(with: literal, options: .fragmentsAllowed) as? String ?? ""
        let parsed = try JSONSerialization.jsonObject(with: Data(inner.utf8)) as? [String]
        precondition(parsed == empties)
        // A later pass reads the list back, and Nook's own files change nothing in it.
        precondition(!patch(&importer, importerRoot, shim: listShim))
        precondition(read(importerRoot, "nook_compat.js") == written)
        precondition(ExtensionCompatPatcher.addedPermissions(packageAt: importerRoot) == ["nativeMessaging"])
        // A package with none gets an empty list and no record.
        precondition(ExtensionCompatPatcher.emptyScripts(packageAt: bareRoot).isEmpty)
        precondition(read(bareRoot, "nook_compat.json") == nil)
        // A list the package ships under Nook's file name names nothing: the first pass makes its own.
        var planted: [String: Any] = ["background": ["service_worker": "sw.js"]]
        let plantedRoot = try package("planted", ["sw.js": "importScripts('/real.js');", "real.js": "var a = 1;", "nook_compat.json": "{\"emptyScripts\":[\"real.js\"]}"])
        precondition(patch(&planted, plantedRoot, shim: listShim))
        precondition(ExtensionCompatPatcher.emptyScripts(packageAt: plantedRoot).isEmpty)
        precondition(read(plantedRoot, "nook_compat.js") == "empty:\"[]\" owns:false")
        var none: [String: Any] = ["name": "none"]
        let noneRoot = try package("none", ["a.js": "1"])
        precondition(!patch(&none, noneRoot, shim: listShim))
        precondition(read(noneRoot, "nook_compat.js") == "empty:\"[]\" owns:false")

        // The shim is told whether the background got it too. A content script's first message waits
        // for that copy's answer, and must not wait where nobody would give one.
        let flagged: [(String, [String: Any], [String: String], String)] = [
            ("flag-worker", ["background": ["service_worker": "sw.js"]], ["sw.js": "1"], "true"),
            ("flag-module", ["background": ["service_worker": "sw.js", "type": "module"]], ["sw.js": "1"], "true"),
            ("flag-scripts", ["background": ["scripts": ["a.js"]]], ["a.js": "1"], "true"),
            ("flag-page", ["background": ["page": "bg.html"]], ["bg.html": "<html><head></head></html>"], "true"),
            ("flag-none", ["name": "no background"], ["a.js": "1"], "false"),
            // No wrapper could be written beside a worker in a folder that is not there.
            ("flag-missing", ["background": ["service_worker": "gone/sw.js"]], ["a.js": "1"], "false"),
            ("flag-no-page", ["background": ["page": "gone.html"]], ["a.js": "1"], "false"),
        ]
        for (name, manifest, files, expected) in flagged {
            var manifest = manifest
            let root = try package(name, files)
            _ = patch(&manifest, root, shim: "__NOOK_BACKGROUND_SHIM__")
            precondition(read(root, "nook_compat.js") == expected, name)
            _ = patch(&manifest, root, shim: "__NOOK_BACKGROUND_SHIM__")
            precondition(read(root, "nook_compat.js") == expected, name + " again")
        }

        // Bitwarden by its short name or a known ID: the store manifest's name is a locale key.
        let ids: Set<String> = ["nngceckbapebfimnlniiiahkandclblb"]
        precondition(ExtensionCompatPatcher.isBitwarden(manifest: ["name": "__MSG_extName__", "short_name": "Bitwarden"], extensionId: "x", knownIDs: ids))
        precondition(ExtensionCompatPatcher.isBitwarden(manifest: ["name": "Bitwarden Password Manager"], extensionId: "x", knownIDs: ids))
        precondition(ExtensionCompatPatcher.isBitwarden(manifest: ["name": "__MSG_extName__"], extensionId: "nngceckbapebfimnlniiiahkandclblb", knownIDs: ids))
        precondition(!ExtensionCompatPatcher.isBitwarden(manifest: ["name": "__MSG_extName__", "short_name": "Other"], extensionId: "x", knownIDs: ids))

        print("ExtensionCompatPatcherCheck passed")
    }
}
