// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionCompatBridgeCheck.swift
//  Nook
//
//  The rules of the extension bridge that need no running extension. Compiles the shipped sources:
//
//    swiftc Nook/Managers/ExtensionManager/ExtensionCompat[A-Z]*.swift \
//           scripts/tests/ExtensionCompatBridgeCheck.swift \
//           -o /tmp/extension-bridge-check && /tmp/extension-bridge-check
//

import Foundation
import Network
import WebKit

@main
struct ExtensionCompatBridgeCheck {
    @MainActor
    static func main() {
        wake()
        webNavigation()
        idle()
        notifications()
        management()
        identity()
        silentFlow()
        sidePanel()
        consent()
        print("ExtensionCompatBridgeCheck passed")
    }

    /// The consent sheet names a permission WebKit does not know when the manifest asks for it and Nook answers it.
    @MainActor
    static func consent() {
        typealias B = ExtensionCompatBridge
        let bridge = B()
        [ExtensionCompatIdentity(), ExtensionCompatOffscreen(), ExtensionCompatSidePanel()].forEach(bridge.register)
        precondition(bridge.gatedPermissions == ["identity", "offscreen", "sidePanel"])

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("nook-consent-check-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let manifest: [String: Any] = [
            "manifest_version": 3, "name": "Consent", "version": "1.0", "background": ["service_worker": "sw.js"],
            "permissions": ["storage", "management", "identity", "nativeMessaging", "notARealPermission"],
            "optional_permissions": ["idle"]]
        try! JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("manifest.json"))
        try! Data().write(to: folder.appendingPathComponent("sw.js"))
        var loaded: WKWebExtension?
        Task { @MainActor in loaded = try? await WKWebExtension(resourceBaseURL: folder) }
        let end = Date() + 10
        while loaded == nil && Date() < end { RunLoop.main.run(until: Date() + 0.02) }
        guard let loaded else { preconditionFailure("the test extension did not load") }

        // Nook's own channel stays hidden. A name nothing answers stays out, and so does an optional one.
        let bridged: Set = ["offscreen", "idle", "notifications", "management", "identity", "sidePanel", "webNavigation"]
        let shown = B.consentPermissions(of: loaded, hiding: ["nativeMessaging"], bridged: bridged)
        precondition(shown == ["storage", "management", "identity"], "\(shown.sorted())")
    }

    /// An event for a background that listens wakes it unless the event just reached the background's own port.
    @MainActor
    static func wake() {
        typealias B = ExtensionCompatBridge
        // A popup that listens is no stand-in for the sleeping worker.
        precondition(B.mustWake(backgroundListens: true, reachedBackground: false))
        precondition(!B.mustWake(backgroundListens: true, reachedBackground: true))
        // An event only a page asked for wakes nothing.
        precondition(!B.mustWake(backgroundListens: false, reachedBackground: false))
    }

    /// `idle`: the state an extension is told, and when Nook next has to look.
    @MainActor
    static func idle() {
        typealias Idle = ExtensionCompatIdle
        // A locked screen is `locked` however recent the last input.
        precondition(Idle.state(locked: true, idleFor: 0, interval: 60) == .locked)
        precondition(Idle.state(locked: false, idleFor: 59.9, interval: 60) == .active)
        precondition(Idle.state(locked: false, idleFor: 60, interval: 60) == .idle)
        // Chrome's bounds: nothing shorter than 15 seconds, so no extension can ask for a tight timer.
        precondition(Idle.interval(1) == 15 && Idle.interval(0.001) == 15 && Idle.interval(-5) == 15)
        precondition(Idle.interval(90) == 90 && Idle.interval(1e12) == 14_400)
        precondition(Idle.interval("60") == nil && Idle.interval(nil) == nil && Idle.interval(Double.nan) == nil)
        // An active watcher is read again when it would turn idle, the earliest of them first.
        precondition(Idle.nextCheck([(.active, 60), (.active, 15)], idleFor: 5) == 10.5)
        precondition(Idle.nextCheck([(.active, 15)], idleFor: 400) == 0.5)
        // Idle or locked, no timer runs: the input monitor ends one and the unlock notification the other.
        precondition(Idle.nextCheck([(.idle, 60), (.locked, 15)], idleFor: 500) == nil)
        precondition(Idle.nextCheck([(.idle, 15)], idleFor: 500) == nil)
        precondition(Idle.nextCheck([(.locked, 15)], idleFor: 500) == nil)
        // One active watcher among them keeps its own deadline.
        precondition(Idle.nextCheck([(.idle, 15), (.active, 60)], idleFor: 20) == 40.5)
        // No listener, no timer.
        precondition(Idle.nextCheck([], idleFor: 0) == nil)
    }

    /// `notifications`: whose notification an identifier names, what is shown, and how many may be posted.
    @MainActor
    static func notifications() {
        typealias N = ExtensionCompatNotifications
        // The extension's own id may hold anything. The extension it belongs to never changes with it.
        for id in ["plain", "with.dots", "line\nbreak", "\n\nnook.ext\nother\nx", ""] {
            let parsed = N.parse(N.identifier(id, in: "abcdef"))
            precondition(parsed?.contextID == "abcdef" && parsed?.id == id)
        }
        precondition(N.parse("focusable-webview-1") == nil && N.parse("nook.ext\n\nx") == nil && N.parse("other\nabc\nx") == nil)

        let made = N.notification(["type": "list", "title": "T", "message": "M", "contextMessage": "C",
                                   "items": [["title": "a", "message": "one"], ["title": "b"]],
                                   "buttons": [["title": "Yes"], ["title": "No"], ["title": "Third"], ["icon": "x"]]],
                                  identifier: "i", extensionName: "Ext")!
        precondition(made.title == "T" && made.subtitle == "Ext" && made.body == "M\nC\na one\nb")
        // Chrome shows two buttons at most.
        precondition(made.buttons == ["Yes", "No"] && !made.silent)
        // A new notification needs a title and a message.
        precondition(N.notification(["title": "T"], identifier: "i", extensionName: "Ext") == nil)
        precondition(N.notification(["message": "M"], identifier: "i", extensionName: "Ext") == nil)
        // An update changes what it names and keeps the rest.
        let updated = N.notification(["message": "New", "silent": true], identifier: "i", extensionName: "Ext", over: made)!
        precondition(updated.title == "T" && updated.body == "New" && updated.buttons == ["Yes", "No"] && updated.silent)
        // Nothing an extension sends is shown at any length.
        let long = N.notification(["title": String(repeating: "t", count: 5000), "message": String(repeating: "m", count: 50_000)],
                                  identifier: "i", extensionName: "Ext")!
        precondition(long.title.count == N.titleLimit && long.body.count == N.bodyLimit)

        // An id of any length is not kept, and one notification past the limit takes the oldest down.
        precondition(N.accepts(id: String(repeating: "i", count: N.idLimit)) && !N.accepts(id: String(repeating: "i", count: N.idLimit + 1)))
        precondition(N.overflow([("c", 3), ("a", 1), ("b", 2)], limit: 3).isEmpty)
        precondition(N.overflow([("c", 3), ("a", 1), ("d", 4), ("b", 2)], limit: 2) == ["a", "b"])
        precondition(N.overflow([("a", 1)], limit: 0) == ["a"])

        let now = Date()
        precondition(N.mayPost(after: [], now: now))
        precondition(N.mayPost(after: Array(repeating: now.addingTimeInterval(-5), count: N.postsPerMinute - 1), now: now))
        precondition(!N.mayPost(after: Array(repeating: now.addingTimeInterval(-5), count: N.postsPerMinute), now: now))
        // Posts older than a minute no longer count.
        precondition(N.mayPost(after: Array(repeating: now.addingTimeInterval(-61), count: 500), now: now))
    }

    /// `management`: what one extension is told about another.
    @MainActor
    static func management() {
        typealias M = ExtensionCompatManagement
        let mv3 = M.extensionInfo(M.Info(
            id: "abc", name: "Name", version: "1.2", description: "About", enabled: true,
            manifest: ["short_name": "__MSG_short__", "homepage_url": "https://example.com/", "options_ui": ["page": "options.html"],
                       "permissions": ["tabs", "nativeMessaging", "storage"], "host_permissions": ["https://*.example.com/*"]],
            added: ["nativeMessaging"], baseURL: URL(string: "webkit-extension://abc")))
        precondition(mv3["id"] as? String == "abc" && mv3["enabled"] as? Bool == true && mv3["type"] as? String == "extension")
        // A name still in its `__MSG_` form is not shown.
        precondition(mv3["shortName"] as? String == "Name")
        // The permission Nook added for its own channel is not the extension's.
        precondition(mv3["permissions"] as? [String] == ["tabs", "storage"])
        precondition(mv3["hostPermissions"] as? [String] == ["https://*.example.com/*"])
        precondition(mv3["optionsUrl"] as? String == "webkit-extension://abc/options.html")
        precondition(mv3["homepageUrl"] as? String == "https://example.com/" && mv3["updateUrl"] == nil)

        let mv2 = M.extensionInfo(M.Info(
            id: "def", name: "Old", version: "0.1", description: "", enabled: false,
            manifest: ["short_name": "O", "options_page": "o.html", "permissions": ["tabs", "<all_urls>", "*://*.test/*"]]))
        precondition(mv2["shortName"] as? String == "O" && mv2["enabled"] as? Bool == false)
        precondition(mv2["permissions"] as? [String] == ["tabs"])
        precondition(mv2["hostPermissions"] as? [String] == ["<all_urls>", "*://*.test/*"])
        // A disabled extension has no pages to open.
        precondition(mv2["optionsUrl"] as? String == "")
    }

    /// `identity`: where a flow may start, and the one address that ends it.
    @MainActor
    static func identity() {
        typealias I = ExtensionCompatIdentity
        func url(_ text: String) -> URL { URL(string: text)! }
        precondition(I.isRedirect(url("https://abcdef.chromiumapp.org/cb?code=1#x"), for: "abcdef"))
        precondition(I.isRedirect(url("https://ABCDEF.chromiumapp.org"), for: "abcdef"))
        // Another extension's address, a look-alike host, or plain http never ends the flow.
        precondition(!I.isRedirect(url("https://other.chromiumapp.org/cb"), for: "abcdef"))
        precondition(!I.isRedirect(url("https://abcdef.chromiumapp.org.evil.test/cb"), for: "abcdef"))
        precondition(!I.isRedirect(url("https://evil.test/abcdef.chromiumapp.org"), for: "abcdef"))
        precondition(!I.isRedirect(url("https://xabcdef.chromiumapp.org/"), for: "abcdef"))
        precondition(!I.isRedirect(url("http://abcdef.chromiumapp.org/cb"), for: "abcdef"))
        precondition(I.mayStart(at: url("https://accounts.example.com/o/oauth2/auth?x=1")))
        for bad in ["file:///etc/passwd", "javascript:alert(1)", "data:text/html,x", "webkit-extension://abcdef/page.html", "https:///nohost", "about:blank"] {
            precondition(!I.mayStart(at: url(bad)), bad)
        }
    }

    /// `identity` with no window: pages from a server on this Mac, in a real web view.
    @MainActor
    static func silentFlow() {
        typealias I = ExtensionCompatIdentity
        precondition(I.silentLimit(nil) == 60 && I.silentLimit(5000) == 5 && I.silentLimit(600_000) == 60)
        precondition(I.silentLimit(-1) == 60 && I.silentLimit("5000") == 60)
        // Unseen, a page loads over TLS only: no router, no plain-http port on this Mac.
        precondition(I.mayLoadUnseen(at: URL(string: "https://accounts.example.com/o/oauth2/auth")!))
        for bad in ["http://192.168.1.1/", "http://localhost:8080/", "http://accounts.example.com/", "file:///etc/passwd", "https:///nohost"] {
            precondition(!I.mayLoadUnseen(at: URL(string: bad)!), bad)
        }

        func spin(_ seconds: TimeInterval, until done: () -> Bool) {
            let end = Date() + seconds
            while !done() && Date() < end { RunLoop.main.run(until: Date() + 0.02) }
        }
        let back = "https://abcdef.chromiumapp.org/cb?code=1"
        let local = NWParameters.tcp
        local.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        let listener = try! NWListener(using: local)
        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let path = String(decoding: data ?? Data(), as: UTF8.self).split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                let moved = ["/go": back, "/hop": "/page", "/app": "nook://open?url=x"][path]
                let body = path == "/late" ? "<script>setTimeout(function () { location.href = '\(back)' }, 200)</script>" : "<body>Sign in"
                let answer = moved.map { "HTTP/1.1 302 Found\r\nLocation: \($0)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n" }
                    ?? "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(answer.utf8), completion: .contentProcessed { _ in connection.cancel() })
            }
        }
        listener.start(queue: .main)
        spin(5) { listener.state == .ready }
        guard listener.state == .ready, let port = listener.port?.rawValue else { preconditionFailure("no local server") }

        // The server here speaks plain http, so every case but `shipped` runs under the rule for a window.
        func expect(_ path: String, waits: Bool = false, limit: TimeInterval = 20, shipped: Bool = false,
                    atLimit: Bool = false, gives wanted: String) {
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = .nonPersistent()
            var got: String?
            let started = Date()
            let page = ExtensionCompatSilentPage(
                view: WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration),
                extensionID: "abcdef", waitsAfterLoad: waits, limit: limit, mayLoad: shipped ? I.mayLoadUnseen : I.mayStart
            ) { result in
                switch result {
                case .success(let value): got = value as? String ?? "no address"
                case .failure(let error): got = "error: " + error.message
                }
            }
            page.load(URL(string: "http://127.0.0.1:\(port)\(path)")!)
            spin(30) { got != nil }
            page.stop()
            precondition(got == wanted, "\(path): \(got ?? "no answer")")
            // The time limit gives the same answer as a page that stays, so say which of them answered.
            let waited = Date().timeIntervalSince(started)
            precondition(atLimit == (waited >= limit - 0.1), "\(path): answered after \(waited) s")
        }
        let needsPerson = "error: User interaction required."
        // The provider sends the person straight back: the flow ends at that address.
        expect("/go", gives: back)
        // A page that loads and stays wants the person, after a hop too.
        expect("/page", gives: needsPerson)
        expect("/hop", gives: needsPerson)
        // A provider that redirects from script is waited for only when the extension says so, and not for ever.
        expect("/late", gives: needsPerson)
        expect("/late", waits: true, gives: back)
        expect("/page", waits: true, limit: 1, atLimit: true, gives: needsPerson)
        // A redirect out of the web goes nowhere, and under the shipped rule neither does plain http.
        let notLoaded = "error: Authorization page could not be loaded."
        expect("/app", gives: notLoaded)
        expect("/go", shipped: true, gives: notLoaded)
        listener.cancel()
    }

    /// `sidePanel`: which page a tab's panel is, and that it is the extension's own.
    @MainActor
    static func sidePanel() {
        typealias P = ExtensionCompatSidePanel
        let manifest: [String: Any] = ["side_panel": ["default_path": "panel.html"]]
        var now = P.effective(tab: nil, defaults: P.Options(), manifest: manifest)
        precondition(now.path == "panel.html" && now.enabled)
        now = P.effective(tab: nil, defaults: P.Options(path: "other.html", enabled: false), manifest: manifest)
        precondition(now.path == "other.html" && !now.enabled)
        // A tab's own options win, each one by itself.
        now = P.effective(tab: P.Options(path: nil, enabled: true), defaults: P.Options(path: "other.html", enabled: false), manifest: manifest)
        precondition(now.path == "other.html" && now.enabled)
        now = P.effective(tab: P.Options(path: "tab.html", enabled: nil), defaults: P.Options(path: nil, enabled: false), manifest: manifest)
        precondition(now.path == "tab.html" && now.enabled)
        precondition(!P.effective(tab: P.Options(path: nil, enabled: false), defaults: P.Options(), manifest: manifest).enabled)
        precondition(P.effective(tab: nil, defaults: P.Options(), manifest: [:]).path == nil)

        let base = URL(string: "webkit-extension://abc")!
        precondition(P.panelURL("panel.html", base: base)?.absoluteString == "webkit-extension://abc/panel.html")
        precondition(P.panelURL("/dir/panel.html?x=1", base: base)?.absoluteString == "webkit-extension://abc/dir/panel.html?x=1")
        for bad in ["https://example.com/panel.html", "//example.com/panel.html", "webkit-extension://other/panel.html", "file:///etc/passwd", "javascript:alert(1)"] {
            precondition(P.panelURL(bad, base: base) == nil, bad)
        }
    }

    /// Chrome's split between its two same-document events.
    @MainActor
    static func webNavigation() {
        func event(_ old: String, _ new: String) -> String? {
            ExtensionCompatWebNavigation.event(from: URL(string: old)!, to: URL(string: new)!)
        }
        let history = "webNavigation.onHistoryStateUpdated", fragment = "webNavigation.onReferenceFragmentUpdated"
        precondition(event("https://a.test/x", "https://a.test/y") == history)
        precondition(event("https://a.test/x", "https://a.test/x?q=1") == history)
        precondition(event("https://a.test/x#one", "https://a.test/y#one") == history)
        precondition(event("https://a.test/x", "https://a.test/x#one") == fragment)
        precondition(event("https://a.test/x#one", "https://a.test/x#two") == fragment)
        precondition(event("https://a.test/x#one", "https://a.test/x") == fragment)
        // Nothing changed, nothing to report.
        precondition(event("https://a.test/x#one", "https://a.test/x#one") == nil)
    }
}
