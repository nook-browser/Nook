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

        // Bitwarden by its short name or a known ID: the store manifest's name is a locale key.
        let ids: Set<String> = ["nngceckbapebfimnlniiiahkandclblb"]
        precondition(ExtensionCompatPatcher.isBitwarden(manifest: ["name": "__MSG_extName__", "short_name": "Bitwarden"], extensionId: "x", knownIDs: ids))
        precondition(ExtensionCompatPatcher.isBitwarden(manifest: ["name": "Bitwarden Password Manager"], extensionId: "x", knownIDs: ids))
        precondition(ExtensionCompatPatcher.isBitwarden(manifest: ["name": "__MSG_extName__"], extensionId: "nngceckbapebfimnlniiiahkandclblb", knownIDs: ids))
        precondition(!ExtensionCompatPatcher.isBitwarden(manifest: ["name": "__MSG_extName__", "short_name": "Other"], extensionId: "x", knownIDs: ids))

        print("ExtensionCompatPatcherCheck passed")
    }
}
