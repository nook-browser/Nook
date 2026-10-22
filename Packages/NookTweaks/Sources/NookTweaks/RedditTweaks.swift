// Licensed under GPL-3.0. See LICENSE.
//
//  RedditTweaks.swift
//  Nook
//
//  Created by Claude on 22/10/2026.
//

import Foundation
import NookBlocker
import NookSettings
import WebKit

/// Opens Reddit feeds sorted by Hot instead of Best. Full loads are redirected in
/// `decidePolicyFor`; Reddit's in-page navigations never reach it, so a click listener
/// rewrites feed links before Reddit's router reads them.
@MainActor
public enum RedditTweaks {
    private static let marker = "// Nook Reddit Tweaks"
    private static let world = WKContentWorld.world(name: "NookRedditTweaks")

    // Mirrors hotURL(for:settings:).
    private static let script = #"""
    // Nook Reddit Tweaks
    (() => {
      if (!/^(www\.)?reddit\.com$/.test(location.hostname)) return;
      const feed = /^\/(r\/[^/]+\/|user\/[^/]+\/m\/[^/]+\/)?$/;
      document.addEventListener('click', (e) => {
        const a = e.composedPath().find((n) => n instanceof HTMLAnchorElement && n.href);
        if (!a) return;
        const u = new URL(a.href);
        const path = u.pathname.endsWith('/') ? u.pathname : u.pathname + '/';
        if (u.host !== location.host || !feed.test(path)) return;
        u.pathname = path + 'hot/';
        a.href = u.href;
      }, true);
    })();
    """#

    /// The Hot version of a sortless Reddit feed URL: home, a subreddit, or a custom feed.
    public static func hotURL(for url: URL, settings: NookSettingsService) -> URL? {
        guard settings.redditSortHot,
              let host = url.host?.lowercased(), host == "reddit.com" || host == "www.reddit.com",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let parts = components.path.split(separator: "/")
        let isFeed = parts.isEmpty
            || (parts.count == 2 && parts[0] == "r")
            || (parts.count == 4 && parts[0] == "user" && parts[2] == "m")
        guard isFeed else { return nil }
        components.path = "/" + parts.map { "\($0)/" }.joined() + "hot/"
        return components.url
    }

    /// Main-frame navigation hook, next to FacebookTweaks. The script gates on hostname itself,
    /// so it is only rewritten when the setting changes.
    public static func apply(in webView: WKWebView, settings: NookSettingsService) {
        let ucc = webView.configuration.userContentController
        // Read everything from the lazily bridged array before removeAllUserScripts (Release-only trap).
        let all = ucc.userScripts
        let installed = all.contains { $0.source.hasPrefix(marker) }
        guard installed != settings.redditSortHot else { return }
        let others = all.nookOwned.filter { !$0.source.hasPrefix(marker) }
        ucc.removeAllUserScripts()
        others.forEach { ucc.addUserScript($0) }
        if settings.redditSortHot {
            ucc.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        }
    }
}
