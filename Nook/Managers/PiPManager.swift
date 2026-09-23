// Licensed under GPL-3.0. See LICENSE.
//
//  PiPManager.swift
//  Nook
//
//  Picture-in-Picture implementation using WebKit APIs.
//  Supports web video PiP via standard WebKit presentation mode APIs.
//

import Foundation
import AppKit
import WebKit
import NookWeb

@MainActor
final class PiPManager: NSObject {
    static let shared = PiPManager()

    /// Pages whose system picture-in-picture Nook started on a tab switch, so coming back to the
    /// tab can end it.
    private var automaticItems: Set<UUID> = []

    private override init() {
        super.init()
    }

    // MARK: - Web Video PiP

    /// Toggles picture-in-picture for the page's video, deciding from the video's own state.
    /// Only a displayed page has a view, so this never creates one.
    func requestPiP(for session: PageSession, webView: WKWebView? = nil) {
        guard let webView = webView ?? session.assignedWebView else { return }
        automaticItems.remove(session.itemID)
        webView.evaluateJavaScript(Self.presentationScript(nil))
    }

    /// `hasPiPActive` follows WebKit's own events (`pipStateChange`), not this request, since
    /// WebKit can decline it.
    func setPiP(_ on: Bool, for session: PageSession, webView: WKWebView? = nil) {
        guard let webView = webView ?? session.assignedWebView else { return }
        if !on { automaticItems.remove(session.itemID) }
        webView.evaluateJavaScript(Self.presentationScript(on))
    }

    /// Entered for the user, so `leaveAutomatic` can undo it when they come back. `screened`
    /// applies the rules that keep feed autoplay and reels out.
    func enterAutomatically(_ session: PageSession, webView: WKWebView, screened: Bool) {
        automaticItems.insert(session.itemID)
        webView.evaluateJavaScript(Self.presentationScript(true, screened: screened))
    }

    func leaveAutomatic(_ session: PageSession) {
        guard automaticItems.contains(session.itemID) else { return }
        setPiP(false, for: session)
    }

    /// `on` nil toggles.
    static func presentationScript(_ on: Bool?, screened: Bool = false) -> String {
        let mode = on.map { $0 ? "'picture-in-picture'" : "'inline'" }
            ?? "(v.webkitPresentationMode === 'picture-in-picture' ? 'inline' : 'picture-in-picture')"
        return """
        (function() {
            \(SidebarPiPController.pickerScript)
            const v = nookPickVideo();
            if (!v || v.disablePictureInPicture || typeof v.webkitSetPresentationMode !== 'function'
                || !v.webkitSupportsPresentationMode('picture-in-picture')) return false;
            \(screened ? "if (nookRefusesAutomatic(v)) return false;" : "")
            v.webkitSetPresentationMode(\(mode));
            return true;
        })();
        """
    }
}
