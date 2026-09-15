//
//  PiPManager+LegacyTab.swift
//  Nook
//
//  `Tab` entry points kept for Tab.swift until task Z deletes `Tab`.
//

import WebKit

extension PiPManager {
    func requestPiP(for tab: Tab, webView: WKWebView? = nil) {
        guard let webView = webView ?? tab.assignedWebView else { return }
        webView.evaluateJavaScript(Self.toggleScript) { [weak tab] result, _ in
            guard let tab, let mode = Self.mode(from: result) else { return }
            tab.hasPiPActive = mode == "picture-in-picture"
        }
    }

    func isPiPActive(for tab: Tab) -> Bool {
        tab.hasPiPActive
    }
}
