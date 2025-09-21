//
//  MiniWindowWebView.swift
//  Nook
//
//  Created by Jonathan Caudill on 26/08/2025.
//

import SwiftUI
import WebKit

struct MiniWindowWebView: NSViewRepresentable {
    @ObservedObject var session: MiniWindowSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration: WKWebViewConfiguration
        if let profile = session.profile {
            configuration = BrowserConfiguration.shared.webViewConfiguration(for: profile)
        } else {
            configuration = BrowserConfiguration.shared.cacheOptimizedWebViewConfiguration()
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true

        context.coordinator.installProgressObservation(on: webView)
        context.coordinator.installAuthDetectionScript(on: webView)
        context.coordinator.loadInitialURLIfNeeded(on: webView)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.session = session
        context.coordinator.loadInitialURLIfNeeded(on: nsView)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var session: MiniWindowSession
        private var progressObservation: NSKeyValueObservation?
        private var didLoadInitialURL = false

        init(session: MiniWindowSession) {
            self.session = session
        }

        func installProgressObservation(on webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                guard let progress = change.newValue else { return }
                DispatchQueue.main.async {
                    self?.session.updateProgress(progress)
                }
            }
        }

        private static let themeColorExtractionScript = """
            (function() {
                function normalizeColor(value) {
                    if (!value) { return null; }
                    const input = String(value).trim();
                    if (!input) { return null; }

                    const canvas = document.createElement('canvas');
                    canvas.width = 1;
                    canvas.height = 1;
                    const ctx = canvas.getContext('2d');
                    if (!ctx) { return null; }

                    ctx.fillStyle = '#000000';
                    try {
                        ctx.fillStyle = input;
                    } catch (e) {
                        return null;
                    }

                    const normalized = ctx.fillStyle;
                    if (typeof normalized !== 'string') { return null; }

                    if (normalized.startsWith('#')) {
                        if (normalized.length === 4) {
                            const r = normalized.charAt(1);
                            const g = normalized.charAt(2);
                            const b = normalized.charAt(3);
                            return `#${r}${r}${g}${g}${b}${b}`;
                        }
                        if (normalized.length === 7) {
                            return normalized;
                        }
                        if (normalized.length === 9) {
                            return normalized.substring(0, 7);
                        }
                    }

                    if (normalized.startsWith('rgb')) {
                        const match = normalized.match(/rgba?\\(([^)]+)\\)/i);
                        if (!match) { return null; }
                        const parts = match[1].split(',').map(part => part.trim());
                        if (parts.length < 3) { return null; }

                        const r = Math.round(Number(parts[0]));
                        const g = Math.round(Number(parts[1]));
                        const b = Math.round(Number(parts[2]));
                        const a = parts.length > 3 ? Number(parts[3]) : 1;

                        if ([r, g, b, a].some(Number.isNaN)) { return null; }
                        if (a === 0) { return null; }

                        const toHex = (n) => n.toString(16).padStart(2, '0');
                        return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
                    }

                    return null;
                }

                function candidateColors() {
                    const metaNames = [
                        'theme-color',
                        'msapplication-navbutton-color',
                        'apple-mobile-web-app-status-bar-style'
                    ];

                    for (const name of metaNames) {
                        const element = document.querySelector(`meta[name="${name}"]`);
                        if (element) {
                            const normalized = normalizeColor(element.getAttribute('content'));
                            if (normalized) { return normalized; }
                        }
                    }

                    const topElement = document.elementFromPoint(window.innerWidth / 2, 1);
                    if (topElement) {
                        const normalized = normalizeColor(getComputedStyle(topElement).backgroundColor);
                        if (normalized) { return normalized; }
                    }

                    if (document.body) {
                        const normalized = normalizeColor(getComputedStyle(document.body).backgroundColor);
                        if (normalized && normalized !== '#000000') { return normalized; }
                    }

                    if (document.documentElement) {
                        const normalized = normalizeColor(getComputedStyle(document.documentElement).backgroundColor);
                        if (normalized) { return normalized; }
                    }

                    return null;
                }

                return candidateColors();
            })();
        """

        private func extractThemeColor(from webView: WKWebView) {
            webView.evaluateJavaScript(Self.themeColorExtractionScript) { [weak self] result, error in
                guard let self else { return }
                if let error {
                    print("🎨 [MiniWindow] Failed to evaluate theme color script: \(error.localizedDescription)")
                }

                var hexString = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if hexString?.isEmpty == true { hexString = nil }

                DispatchQueue.main.async {
                    self.session.updateToolbarColor(hexString: hexString)
                }
            }
        }

        func installAuthDetectionScript(on webView: WKWebView) {
            // Add message handler for authentication completion
            webView.configuration.userContentController.add(self, name: "authCompletion")

            // Inject a simpler, less intrusive JavaScript to detect authentication completion
            let authDetectionScript = """
                (function() {
                    // Simple function to check for auth completion
                    function checkAuthCompletion() {
                        try {
                            const url = window.location.href;
                            const search = window.location.search;
                            const hash = window.location.hash;

                            // Check for common OAuth success patterns
                            if (search.match(/(code=|access_token=|id_token=|oauth_token=|oauth_verifier=|session_state=|samlresponse=|relaystate=|ticket=|assertion=|authuser=)/i) ||
                                hash.match(/(access_token=|id_token=|oauth_token=|session_state=)/i)) {

                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.authCompletion) {
                                    window.webkit.messageHandlers.authCompletion.postMessage({
                                        success: true,
                                        url: url
                                    });
                                }
                                return;
                            }

                            // Check for common OAuth error patterns
                            if (search.match(/(error=|denied|cancelled|abort|failed|unauthorized|access_denied|invalid_request|unsupported_response_type|invalid_scope|server_error|temporarily_unavailable)/i) ||
                                hash.match(/(error=|denied|cancelled|abort)/i)) {

                                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.authCompletion) {
                                    window.webkit.messageHandlers.authCompletion.postMessage({
                                        success: false,
                                        url: url
                                    });
                                }
                                return;
                            }
                        } catch (e) {
                            // Silently ignore errors to avoid interfering with the page
                            console.log('Auth detection error:', e);
                        }
                    }

                    // Run check when page loads
                    if (document.readyState === 'loading') {
                        document.addEventListener('DOMContentLoaded', checkAuthCompletion);
                    } else {
                        checkAuthCompletion();
                    }

                    // Also check on hash changes (common in OAuth flows)
                    window.addEventListener('hashchange', checkAuthCompletion);

                })();
            """

            let script = WKUserScript(source: authDetectionScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(script)
        }

        func loadInitialURLIfNeeded(on webView: WKWebView) {
            guard didLoadInitialURL == false else { return }
            didLoadInitialURL = true
            let request = URLRequest(url: session.currentURL)
            print("🔐 [MiniWindow] Loading URL: \(session.currentURL.absoluteString)")
            webView.load(request)
        }

        func checkForOAuthCompletion(url: URL) {
            // Skip if already completed
            guard !session.isAuthComplete else { return }

            // Check if this URL indicates OAuth completion
            let urlString = url.absoluteString.lowercased()
            let query = url.query?.lowercased() ?? ""
            let fragment = url.fragment?.lowercased() ?? ""

            // Common OAuth success indicators
            let successIndicators = [
                "code=", "access_token=", "id_token=", "oauth_token=", "oauth_verifier=",
                "session_state=", "samlresponse=", "relaystate=", "ticket=", "assertion=",
                "authuser=",
            ]

            // Common OAuth error indicators
            let errorIndicators = [
                "error=", "denied", "cancelled", "abort", "failed", "unauthorized",
                "access_denied", "invalid_request", "unsupported_response_type",
                "invalid_scope", "server_error", "temporarily_unavailable",
            ]

            // Check for success in URL, query, or fragment
            if successIndicators.contains(where: {
                urlString.contains($0) || query.contains($0) || fragment.contains($0)
            }) {
                print("🔐 [MiniWindow] OAuth success detected: \(url.absoluteString)")
                session.completeAuth(success: true, finalURL: url)
                return
            }

            // Check for error in URL, query, or fragment
            if errorIndicators.contains(where: {
                urlString.contains($0) || query.contains($0) || fragment.contains($0)
            }) {
                print("🔐 [MiniWindow] OAuth error detected: \(url.absoluteString)")
                session.completeAuth(success: false, finalURL: url)
                return
            }

            // Check for redirect back to original domain (common OAuth pattern)
            if let host = url.host?.lowercased(),
               !host.contains("google.com"), !host.contains("microsoft.com"),
               !host.contains("apple.com"), !host.contains("github.com"),
               !host.contains("auth0.com"), !host.contains("okta.com"),
               !host.contains("facebook.com"), !host.contains("twitter.com"),
               !host.contains("discord.com")
            {
                // This might be a redirect back to the original app
                print("🔐 [MiniWindow] Possible OAuth redirect detected: \(url.absoluteString)")
                session.completeAuth(success: true, finalURL: url)
            }
        }

        // MARK: - WKScriptMessageHandler

        func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "authCompletion",
                  let body = message.body as? [String: Any] else { return }

            let success = body["success"] as? Bool ?? false
            let shouldClose = body["shouldClose"] as? Bool ?? false
            let urlString = body["url"] as? String

            print("🔐 [MiniWindow] JavaScript auth completion detected: success=\(success), shouldClose=\(shouldClose), url=\(urlString ?? "nil")")

            let finalURL = urlString.flatMap { URL(string: $0) }
            session.completeAuth(success: success, finalURL: finalURL)

            // If the site expects the window to close, we could close it automatically
            // but for now, let's let the user decide when to close/adopt the window
            if shouldClose {
                print("🔐 [MiniWindow] Site requested window close, but keeping window open for user control")
            }
        }
    }
}

// MARK: - WKNavigationDelegate

@MainActor
extension MiniWindowWebView.Coordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
        print("🔐 [MiniWindow] Navigation started: \(webView.url?.absoluteString ?? "nil")")
        session.updateLoading(isLoading: true)
        session.updateNavigationState(url: webView.url, title: nil)
        session.updateToolbarColor(hexString: nil)
    }

    func webView(_: WKWebView, didCommit _: WKNavigation!) {
        session.updateLoading(isLoading: true)
    }

    func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
        print("🔐 [MiniWindow] Navigation finished: \(webView.url?.absoluteString ?? "nil")")
        session.updateLoading(isLoading: false)
        session.updateNavigationState(url: webView.url, title: nil)

        // Check if this is an OAuth completion URL
        if let url = webView.url {
            checkForOAuthCompletion(url: url)
        }

        webView.evaluateJavaScript("document.title") { [weak self] result, _ in
            guard let self else { return }
            if let title = result as? String {
                DispatchQueue.main.async {
                    self.session.updateNavigationState(url: nil, title: title)
                }
            }
        }

        extractThemeColor(from: webView)
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: Error) {
        print("🔐 [MiniWindow] Navigation failed: \(error.localizedDescription)")
        session.updateLoading(isLoading: false)
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: Error) {
        print("🔐 [MiniWindow] Provisional navigation failed: \(error.localizedDescription)")
        session.updateLoading(isLoading: false)
    }
}

// MARK: - WKUIDelegate

@MainActor
extension MiniWindowWebView.Coordinator: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith _: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures _: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    // MARK: - Full-Screen Video Support

    @available(macOS 10.15, *)
    func webView(
        _ webView: WKWebView,
        enterFullScreenForVideoWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        print("🎬 [MiniWindowWebView] Entering full-screen for video")

        // Get the window containing this webView
        guard let window = webView.window else {
            print("❌ [MiniWindowWebView] No window found for full-screen")
            completionHandler(false, NSError(domain: "MiniWindowWebView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No window available for full-screen"]))
            return
        }

        // Enter full-screen mode
        window.toggleFullScreen(nil)

        // For now, assume success - the actual full-screen state will be handled by the window
        completionHandler(true, nil)
    }

    @available(macOS 10.15, *)
    func webView(
        _ webView: WKWebView,
        exitFullScreenWith completionHandler: @escaping (Bool, Error?) -> Void
    ) {
        print("🎬 [MiniWindowWebView] Exiting full-screen for video")

        // Get the window containing this webView
        guard let window = webView.window else {
            print("❌ [MiniWindowWebView] No window found for exiting full-screen")
            completionHandler(false, NSError(domain: "MiniWindowWebView", code: -1, userInfo: [NSLocalizedDescriptionKey: "No window available for exiting full-screen"]))
            return
        }

        // Exit full-screen mode
        window.toggleFullScreen(nil)

        // For now, assume success - the actual full-screen state will be handled by the window
        completionHandler(true, nil)
    }
}

// Note: We intentionally avoid previewing the live WKWebView here to keep Previews
// fast and stable. Use the preview on MiniBrowserWindowView instead.
