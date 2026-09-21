// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  PageSession+WindowFrame+macOS.swift
//  NookWeb
//
//  WebKit asks the UI delegate for the window frame behind window.outerWidth, outerHeight,
//  screenX and screenY. With no answer they all read 0.
//

#if os(macOS)
import AppKit
import WebKit

extension PageSession {
    /// Answers with the web view's own screen rect, not the window's: pages estimate zoom as
    /// outerWidth / innerWidth (Google Docs sizes its canvas from it), and the sidebar would skew it.
    @objc(_webView:getWindowFrameWithCompletionHandler:)
    func webView(_ webView: WKWebView, getWindowFrameWithCompletionHandler completionHandler: @escaping (CGRect) -> Void) {
        let inWindow = webView.convert(webView.bounds, to: nil)
        completionHandler(webView.window?.convertToScreen(inWindow) ?? webView.bounds)
    }
}
#endif
