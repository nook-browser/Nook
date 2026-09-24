// Licensed under GPL-3.0. See LICENSE.
//
//  PageSession+PiP+macOS.swift
//  NookWeb
//
//  The system picture-in-picture window's return button. WebKit puts the video back into its
//  page on its own; without this the page could be a hidden tab in a background window.
//

#if os(macOS)
import AppKit
import WebKit

extension PageSession {
    /// Element fullscreen sends this too, so only a page in picture-in-picture acts on it.
    @objc(_webViewFullscreenMayReturnToInline:)
    func webViewFullscreenMayReturnToInline(_ webView: WKWebView) {
        guard hasPiPActive, !isDetached, let window = controller?.window(for: self) else { return }
        controller?.select(itemID, in: window)
        window.windowHandle?.bringToFront()
        NSApp.activate()
    }
}
#endif
