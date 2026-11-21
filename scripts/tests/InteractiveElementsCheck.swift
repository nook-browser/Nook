// Licensed under GPL-3.0. See LICENSE.
//
//  swiftc Nook/Managers/AIManager/Tools/InteractiveElementsScript.swift scripts/tests/InteractiveElementsCheck.swift -o /tmp/ie-check && /tmp/ie-check
//
//  The chat's getInteractiveElements list holds what the person is looking at before the rest
//  of a long page, up to its limit. Runs the shipped script in an off-screen web view.

import AppKit
import WebKit

@main
struct InteractiveElementsCheck {
    @MainActor static func main() async {
        _ = NSApplication.shared
        let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        let loaded = Loaded()
        web.navigationDelegate = loaded

        // 120 doc links of 40 px, then a block of 10 buttons, then 60 more links, then a button at the end.
        var html = "<body style='margin:0'>"
        for i in 0..<120 { html += "<a href='/doc/\(i)' style='display:block;height:40px'>Doc \(i)</a>" }
        for i in 0..<10 { html += "<button type='button' style='display:block;height:40px'>Here \(i)</button>" }
        for i in 0..<60 { html += "<a href='/more/\(i)' style='display:block;height:40px'>More \(i)</a>" }
        html += "<div><button type='button'>Nook test button</button></div>"
        html += "<button style='display:none'>Hidden</button></body>"
        await loaded.load(html, in: web)

        func run(filter: String = "", limit: Int = 50) async -> [[String: Any]] {
            let literal = String(data: try! JSONSerialization.data(withJSONObject: filter, options: [.fragmentsAllowed]), encoding: .utf8)!
            let json = try! await web.evaluateJavaScript(InteractiveElementsScript.source(filterJSON: literal, limit: limit)) as! String
            return try! JSONSerialization.jsonObject(with: Data(json.utf8)) as! [[String: Any]]
        }
        func texts(_ rows: [[String: Any]]) -> [String] { rows.compactMap { $0["text"] as? String } }

        // At the top of the page the list starts with the first links, as before.
        var rows = await run()
        precondition(rows.count == 50 && texts(rows).first == "Doc 0", "top of the page")

        // Scrolled to the buttons (4800 px down): they are on screen, so they lead, in page order.
        _ = try! await web.evaluateJavaScript("window.scrollTo(0, 4800); window.scrollY")
        rows = await run()
        let seen = texts(rows)
        precondition(rows.count == 50, "limit holds: \(rows.count)")
        precondition(seen.prefix(10).filter { $0.hasPrefix("Here") }.count == 10, "on-screen buttons lead: \(seen.prefix(12))")
        precondition(!seen.contains("Hidden"), "hidden controls never listed")

        // The limit still cuts the rest; a filter or a larger limit reaches the control at the very end.
        precondition(!seen.contains("Nook test button"), "below the fold and past the limit")
        let filtered = texts(await run(filter: "nook test"))
        precondition(filtered == ["Nook test button"], "filter")
        let wide = texts(await run(limit: 500))
        precondition(wide.contains("Nook test button"), "larger limit")

        print("InteractiveElementsCheck passed")
        exit(0)
    }
}

@MainActor
final class Loaded: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?

    func load(_ html: String, in web: WKWebView) async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            web.loadHTMLString(html, baseURL: URL(string: "https://example.test/"))
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }
}
