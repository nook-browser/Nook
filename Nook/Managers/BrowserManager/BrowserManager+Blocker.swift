// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserManager+Blocker.swift
//  Nook
//
//  Wires NookBlocker to the app: live pages, the web view that owns one, the
//  shared user content controller, and the hook BrowserConfiguration runs on
//  every controller it mints.
//

import WebKit
import NookBlocker
import NookWeb

extension BrowserManager: ContentBlockerHost {
    public var blockablePages: [any BlockablePage] { tabs.sessions }

    public func blockablePage(for webView: WKWebView) -> (any BlockablePage)? {
        tabs.session(for: webView)
    }

    public var sharedUserContentController: WKUserContentController {
        BrowserConfiguration.shared.webViewConfiguration.userContentController
    }

    public func onNewUserContentController(_ handler: @escaping @MainActor (WKUserContentController) -> Void) {
        BrowserConfiguration.shared.contentRuleListApplicator = { controller in
            MainActor.assumeIsolated { handler(controller) }
        }
    }
}
