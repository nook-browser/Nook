//
//  PeekWebView.swift
//  Nook
//
//  Created by Claude on 24/09/2025.
//

import SwiftUI
import WebKit

struct PeekWebView: NSViewRepresentable {
    @ObservedObject var session: PeekSession
    weak var peekManager: PeekManager?

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session, peekManager: peekManager)
    }

    func makeNSView(context: Context) -> WKWebView {
        // Use profile-specific WebView configuration if available
        let configuration: WKWebViewConfiguration
        if let profileId = session.sourceProfileId,
           let profile = peekManager?.browserManager?.profileManager.profiles.first(where: { $0.id == profileId }) {
            configuration = BrowserConfiguration.shared.cacheOptimizedWebViewConfiguration(for: profile)
        } else {
            // Fallback to default configuration
            configuration = BrowserConfiguration.shared.webViewConfiguration
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = false // Disable zoom for peek

        // Enable web inspector for debugging
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }

        context.coordinator.installProgressObservation(on: webView)
        context.coordinator.installThemeColorExtraction(on: webView)
        context.coordinator.loadInitialURLIfNeeded(on: webView)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.session = session
        context.coordinator.peekManager = peekManager
        context.coordinator.loadInitialURLIfNeeded(on: nsView)
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var session: PeekSession
        weak var peekManager: PeekManager?
        private var progressObservation: NSKeyValueObservation?
        private var didLoadInitialURL = false

        init(session: PeekSession, peekManager: PeekManager?) {
            self.session = session
            self.peekManager = peekManager
        }

        func installProgressObservation(on webView: WKWebView) {
            progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] _, change in
                guard let progress = change.newValue else { return }
                DispatchQueue.main.async {
                    self?.session.updateProgress(progress)
                }
            }
        }

        func installThemeColorExtraction(on webView: WKWebView) {
            // Use shared theme color extraction script
            let script = WKUserScript(
                source: WKWebView.themeColorExtractionScript,
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
            webView.configuration.userContentController.addUserScript(script)
        }

        func loadInitialURLIfNeeded(on webView: WKWebView) {
            guard didLoadInitialURL == false else { return }
            didLoadInitialURL = true
            let request = URLRequest(url: session.currentURL)
            webView.load(request)
        }

        private func extractThemeColor(from webView: WKWebView) {
            webView.evaluateJavaScript(WKWebView.themeColorExtractionScript) { [weak self] result, error in
                guard let self else { return }
                if let error {
                    print("🎨 [Peek] Failed to evaluate theme color script: \(error.localizedDescription)")
                }

                var hexString = (result as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                if hexString?.isEmpty == true { hexString = nil }

                DispatchQueue.main.async {
                    self.session.updateToolbarColor(hexString: hexString)
                }
            }
        }

        // MARK: - WKNavigationDelegate

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            session.updateLoading(isLoading: true)
            session.updateNavigationState(url: webView.url, title: nil)
            session.updateToolbarColor(hexString: nil)
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            session.updateLoading(isLoading: true)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            session.updateLoading(isLoading: false)
            session.updateNavigationState(url: webView.url, title: nil)

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

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            session.updateLoading(isLoading: false)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            session.updateLoading(isLoading: false)
        }

        // MARK: - WKUIDelegate

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // Handle external links in peek by opening in new tab
        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Let normal navigation proceed within the peek
            decisionHandler(.allow)
        }
    }
}