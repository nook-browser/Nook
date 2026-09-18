// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
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

    private override init() {
        super.init()
    }

    // MARK: - Web Video PiP

    /// Toggles picture-in-picture for the page's first video. Only a displayed page has a view,
    /// so this never creates one.
    func requestPiP(for session: PageSession, webView: WKWebView? = nil) {
        guard let webView = webView ?? session.assignedWebView else { return }
        webView.evaluateJavaScript(Self.toggleScript) { [weak session] result, _ in
            guard let session, let mode = Self.mode(from: result) else { return }
            session.hasPiPActive = mode == "picture-in-picture"
        }
    }

    func isPiPActive(for session: PageSession) -> Bool {
        session.hasPiPActive
    }

    /// The presentation mode a successful toggle reports.
    static func mode(from result: Any?) -> String? {
        guard let dict = result as? [String: Any], dict["success"] as? Bool == true else { return nil }
        return dict["mode"] as? String
    }

    static let toggleScript = """
    (function() {
        const video = document.querySelector('video');
        if (!video) return { success: false, error: 'No video found' };
        try {
            // WebKit presentation mode (Safari/macOS)
            if (video.webkitSupportsPresentationMode && typeof video.webkitSetPresentationMode === 'function') {
                const currentMode = video.webkitPresentationMode || 'inline';
                const newMode = (currentMode === 'picture-in-picture') ? 'inline' : 'picture-in-picture';
                video.webkitSetPresentationMode(newMode);
                return { success: true, mode: newMode };
            }
            // Standard PiP API fallback
            if (document.pictureInPictureEnabled && video.requestPictureInPicture) {
                if (document.pictureInPictureElement) {
                    document.exitPictureInPicture();
                    return { success: true, mode: 'inline' };
                }
                video.requestPictureInPicture().catch(function() {});
                return { success: true, mode: 'picture-in-picture' };
            }
            return { success: false, error: 'PiP not supported on this page' };
        } catch (error) {
            return { success: false, error: error.message };
        }
    })();
    """
}
