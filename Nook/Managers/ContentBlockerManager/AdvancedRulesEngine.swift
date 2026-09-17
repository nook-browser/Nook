//
//  AdvancedRulesEngine.swift
//  Nook
//
//  Answers, per frame URL, which cosmetic filter rules apply that a compiled
//  WKContentRuleList cannot express, chiefly procedural filters. Lookup is done
//  by BlockerEngine over adblock-rust (MPL-2.0). The rules are applied in-page
//  by nook-cosmetic.js, which is Nook's own script and needs no build step.
//
//  Plain cosmetic filters do not come through here: the converter turns them
//  into css-display-none entries in the compiled rule list.
//
//  Foundation + WebKit only; nothing here is AppKit-specific.
//

import Foundation
import WebKit
import OSLog

private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Nook", category: "AdvancedRules")

@MainActor
final class AdvancedRulesEngine {

    /// Prefix on every user script Nook's content blocker owns.
    static let scriptMarker = "// Nook Content Blocker\n"
    /// Prefix on the per-navigation main-frame configuration script.
    static let configScriptMarker = "// Nook Content Blocker Config\n"
    /// WKScriptMessageHandlerWithReply name the runtime uses for subframe lookups.
    static let messageHandlerName = "nookAdvancedBlocking"

    /// One adblock-rust engine, shared by cosmetic lookup and the dev MCP
    /// check_urls tool. Actor-isolated because the engine pointer is Send but
    /// not Sync.
    let engine = BlockerEngine()

    // MARK: - Build

    /// Build (or rebuild) the lookup engine from the raw filter rules.
    /// adblock-rust parses filter syntax directly, so there is no intermediate
    /// "advanced rules text" of the kind SafariConverterLib produced, and no
    /// serialized warm start to reuse.
    func build(rules: [String]) async {
        await engine.build(rules: rules)
    }

    // MARK: - Lookup

    /// JSON-ready configuration for a frame, or nil when nothing applies.
    /// `topUrl` is the top-level document URL; pass nil for the main frame.
    func configuration(for pageUrl: URL, topUrl: URL?) -> [String: Any]? {
        engine.configuration(for: pageUrl, topUrl: topUrl)
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
            source: Self.configScriptMarker + "window.__nookCosmeticConfig = \(json);",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )
    }

    // MARK: - Static scripts (identical for every webview)

    /// The AdGuard runtime (all frames) plus host-guarded site-specific blockers (main frame).
    static let staticUserScripts: [WKUserScript] = {
        var scripts: [WKUserScript] = []

        if let runtime = bundledSource("nook-cosmetic") {
            scripts.append(WKUserScript(source: scriptMarker + runtime, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        } else {
            log.error("nook-cosmetic.js missing from bundle; cosmetic filtering disabled")
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

    private static func bundledSource(_ name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}
