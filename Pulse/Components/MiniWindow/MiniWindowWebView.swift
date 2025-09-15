//
//  MiniWindowWebView.swift
//  Pulse
//
//  Created by Codex on 26/08/2025.
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
        context.coordinator.loadInitialURLIfNeeded(on: webView)

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.session = session
        context.coordinator.loadInitialURLIfNeeded(on: nsView)
    }

    // MARK: - Coordinator
    @MainActor
    final class Coordinator: NSObject {
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

        func loadInitialURLIfNeeded(on webView: WKWebView) {
            guard didLoadInitialURL == false else { return }
            didLoadInitialURL = true
            let request = URLRequest(url: session.currentURL)
            webView.load(request)
        }
    }
}

// MARK: - WKNavigationDelegate
@MainActor
extension MiniWindowWebView.Coordinator: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        session.updateLoading(isLoading: true)
        session.updateNavigationState(url: webView.url, title: nil)
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
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        session.updateLoading(isLoading: false)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        session.updateLoading(isLoading: false)
    }
}

// MARK: - WKUIDelegate
@MainActor
extension MiniWindowWebView.Coordinator: WKUIDelegate {
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
}
