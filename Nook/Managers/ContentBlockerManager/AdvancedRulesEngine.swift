//
//  AdvancedRulesEngine.swift
//  Nook
//
//  Answers, per frame URL, which "advanced" filter rules apply: cosmetic CSS,
//  extended CSS, JS snippets and scriptlets. Lookup is done by SafariConverterLib's
//  FilterEngine (the same engine AdGuard for Safari uses), so domain, path and
//  exception semantics match the filter lists. The rules are applied in-page by
//  nook-advanced-blocking.js, a bundle of AdGuard's @adguard/safari-extension
//  content-script library (ExtendedCss + Scriptlets included).
//
//  Foundation + WebKit only; nothing here is AppKit-specific.
//

import Foundation
import WebKit
import OSLog
import ContentBlockerConverter
import FilterEngine

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "AdvancedRules")

@MainActor
final class AdvancedRulesEngine {

    /// Prefix on every user script Nook's content blocker owns.
    static let scriptMarker = "// Nook Content Blocker\n"
    /// Prefix on the per-navigation main-frame configuration script.
    static let configScriptMarker = "// Nook Content Blocker Config\n"
    /// WKScriptMessageHandlerWithReply name the runtime uses for subframe lookups.
    static let messageHandlerName = "nookAdvancedBlocking"

    private nonisolated(unsafe) var webExtension: WebExtension?

    private static var containerURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("io.browsewithnook.nook/ContentBlocker/AdvancedRules", isDirectory: true)
    }

    // MARK: - Build

    /// Build (or rebuild) the lookup engine from SafariConverterLib's advancedRulesText. Runs off the main actor.
    /// With `reuseSerialized`, the engine serialized by the previous build is opened instead (fast warm start);
    /// WebExtension falls back to a rebuild from its own copy of the rules if that is missing or stale.
    func build(rulesText: String?, reuseSerialized: Bool = false) async {
        guard let text = rulesText, !text.isEmpty else {
            webExtension = nil
            log.info("No advanced rules; engine cleared")
            return
        }
        let containerURL = Self.containerURL
        let start = CFAbsoluteTimeGetCurrent()
        let built: WebExtension? = await Task.detached(priority: .userInitiated) {
            do {
                let ext = try WebExtension(containerURL: containerURL)
                if reuseSerialized, ext.lookup(pageUrl: URL(string: "https://example.com/")!, topUrl: nil) != nil {
                    return ext
                }
                _ = try ext.buildFilterEngine(rules: text)
                return ext
            } catch {
                log.error("Failed to build advanced rules engine: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
        webExtension = built
        log.info("Advanced rules engine built in \(String(format: "%.2f", CFAbsoluteTimeGetCurrent() - start), privacy: .public)s")
    }

    // MARK: - Lookup

    /// JSON-ready configuration for a frame, or nil when nothing applies.
    /// `topUrl` is the top-level document URL; pass nil for the main frame.
    func configuration(for pageUrl: URL, topUrl: URL?) -> [String: Any]? {
        guard let ext = webExtension, let conf = ext.lookup(pageUrl: pageUrl, topUrl: topUrl) else { return nil }
        if conf.css.isEmpty && conf.extendedCss.isEmpty && conf.js.isEmpty && conf.scriptlets.isEmpty { return nil }
        return [
            "css": conf.css,
            "extendedCss": conf.extendedCss,
            "js": conf.js,
            "scriptlets": conf.scriptlets.map { ["name": $0.name, "args": $0.args] },
            "engineTimestamp": conf.engineTimestamp,
        ]
    }

    /// Main-frame fast path: embed the configuration so the runtime applies it synchronously
    /// at document start instead of round-tripping through the message handler.
    /// Always returns a script: `null` when nothing applies, so the runtime skips its async lookup.
    func configUserScript(for pageUrl: URL) -> WKUserScript {
        var json = "null"
        if let conf = configuration(for: pageUrl, topUrl: nil),
           let data = try? JSONSerialization.data(withJSONObject: conf),
           let text = String(data: data, encoding: .utf8) {
            json = text
        }
        return WKUserScript(
            source: Self.configScriptMarker + "window.__nookAdvancedBlockingConfig = \(json);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    // MARK: - Static scripts (identical for every webview)

    /// The AdGuard runtime (all frames) plus host-guarded site-specific blockers (main frame).
    static let staticUserScripts: [WKUserScript] = {
        var scripts: [WKUserScript] = []

        if let runtime = bundledSource("nook-advanced-blocking") {
            scripts.append(WKUserScript(source: scriptMarker + runtime, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        } else {
            log.error("nook-advanced-blocking.js missing from bundle; advanced rules disabled")
        }
        // Answers known ad URLs with an inert stub so a blocked request does not
        // read as a failure to anti-adblock scripts. All frames: detection runs in
        // subframes too. Removed with the other blocker scripts when a host is
        // allowlisted, so an exempt page is untouched.
        if let stealth = bundledSource("nook-stealth-redirects") {
            scripts.append(WKUserScript(source: scriptMarker + stealth, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        } else {
            log.error("nook-stealth-redirects.js missing from bundle; stealth redirects disabled")
        }
        let siteScripts: [(resource: String, hostPattern: String, setup: String)] = [
            // The feed pruners patch JSON.parse, so they must run before the page's own scripts.
            // facebook-feed-prune is shared with FacebookTweaks; this copy turns on its ad flag.
            ("facebook-feed-prune", #"(^|\.)facebook\.com$"#,
             "(window.__nookFBFilter = window.__nookFBFilter || {}).ads = true;"),
            ("facebook-sponsored-blocker", #"(^|\.)facebook\.com$"#, ""),
            ("instagram-feed-prune", #"(^|\.)instagram\.com$"#, ""),
            ("instagram-sponsored-blocker", #"(^|\.)instagram\.com$"#, ""),
            ("youtube-ad-blocker", #"(^|\.)(youtube\.com|youtubekids\.com|youtube-nocookie\.com)$"#, ""),
            ("twitter-ad-blocker", #"(^|\.)(twitter\.com|x\.com)$"#, ""),
        ]
        for entry in siteScripts {
            guard let source = bundledSource(entry.resource) else {
                log.warning("Site script missing from bundle: \(entry.resource, privacy: .public)")
                continue
            }
            let guarded = "\(scriptMarker)(function(){ if (!/\(entry.hostPattern)/.test(location.hostname)) return;\n\(entry.setup)\n\(source)\n})();"
            scripts.append(WKUserScript(source: guarded, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
        return scripts
    }()

    /// Distinct from `scriptMarker` (which ends in a newline) so the optional stats observer
    /// never satisfies `ensureStaticScripts`' check for the blocking scripts.
    static let requestStatsScriptMarker = "// Nook Content Blocker Stats\n"

    static func requestStatsScript(token: String) -> WKUserScript? {
        guard let source = bundledSource("nook-request-stats") else { return nil }
        let script = requestStatsScriptMarker + "window.__nookRequestStatsToken = '\(token)';\n" + source
        return WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: false)
    }

    private static func bundledSource(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
