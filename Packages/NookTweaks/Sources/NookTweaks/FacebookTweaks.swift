//
//  FacebookTweaks.swift
//  Nook
//
//  Created by Claude on 16/09/2026.
//

import Foundation
import NookBlocker
import NookSettings
import OSLog
import WebKit

private let fbTweaksLog = Logger(subsystem: "com.baingurley.nook", category: "FacebookTweaks")

/// Hides the Reels carousel and suggested content in Facebook's news feed. Shares
/// `facebook-feed-prune.js` with the content blocker: this copy sets the reels and suggested flags,
/// the blocker's copy sets the ad flag, and whichever runs first installs the one JSON.parse hook.
@MainActor
public enum FacebookTweaks {
    private static let marker = "// Nook Facebook Tweaks"

    private static let filter: String? = {
        // Shared with the content blocker, so it lives in NookBlocker's resource bundle.
        guard let source = AdvancedRulesEngine.bundledSource("facebook-feed-prune") else {
            fbTweaksLog.warning("Failed to load facebook-feed-prune.js from NookBlocker")
            return nil
        }
        return source
    }()

    /// Main-frame navigation hook, next to YouTubeTweaks. Settings apply on the next page load.
    public static func apply(for url: URL, in webView: WKWebView, settings: NookSettingsService) {
        let source = isFacebook(url.host) ? userScriptSource(settings) : nil
        let ucc = webView.configuration.userContentController
        // Read everything from the lazily bridged array before removeAllUserScripts (Release-only trap).
        let all = ucc.userScripts
        let others = all.nookOwned.filter { !$0.source.hasPrefix(marker) }
        let current = all.first { $0.source.hasPrefix(marker) }?.source
        guard current != source else { return }
        ucc.removeAllUserScripts()
        others.forEach { ucc.addUserScript($0) }
        if let source {
            // Page world: the hook has to replace the JSON.parse Facebook's own code calls.
            ucc.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        }
    }

    private static func userScriptSource(_ settings: NookSettingsService) -> String? {
        guard let filter, settings.facebookHideReels || settings.facebookHideSuggested else { return nil }
        return """
        \(marker)
        (function(){ if (!/(^|\\.)facebook\\.com$/.test(location.hostname)) return;
        var f = window.__nookFBFilter = window.__nookFBFilter || {};
        f.reels = \(settings.facebookHideReels); f.suggested = \(settings.facebookHideSuggested);
        \(filter)
        })();
        """
    }

    private static func isFacebook(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "facebook.com" || host.hasSuffix(".facebook.com")
    }
}
