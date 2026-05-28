//
//  PageLoadingProgressBar.swift
//  Nook
//
//  Thin glass-effect progress bar shown on the URL bar during page loads.
//  Observes WKWebView.estimatedProgress + isLoading via KVO.
//

import Combine
import SwiftUI
import WebKit

struct PageLoadingProgressBar: View {
    let tab: Tab?

    @StateObject private var observer = WebViewLoadingObserver()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(observer.isLoading ? 0.6 : 0)

                // Progress fill
                Rectangle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.7), .cyan.opacity(0.5)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geo.size.width * observer.progress)
                    .animation(.easeOut(duration: 0.15), value: observer.progress)
                    .opacity(observer.isLoading ? 1 : 0)
            }
        }
        .frame(height: 2.5)
        .animation(.easeInOut(duration: 0.15), value: observer.isLoading)
        .onChange(of: tab?.id) { _, _ in
            observer.attach(to: tab?.existingWebView)
        }
        .onAppear {
            observer.attach(to: tab?.existingWebView)
        }
        // React to tab's objectWillChange (fires when webview is created) instead of polling
        .onReceive(tab?.objectWillChange.eraseToAnyPublisher() ?? Empty().eraseToAnyPublisher()) { _ in
            if observer.webView == nil, let wv = tab?.existingWebView {
                observer.attach(to: wv)
            }
        }
        .allowsHitTesting(false)
    }
}

@MainActor
private class WebViewLoadingObserver: ObservableObject {
    @Published var progress: CGFloat = 0
    @Published var isLoading: Bool = false

    private(set) weak var webView: WKWebView?
    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?
    private var hideTask: Task<Void, Never>?

    func attach(to webView: WKWebView?) {
        guard webView !== self.webView else { return }

        progressObservation?.invalidate()
        loadingObservation?.invalidate()
        self.webView = webView

        guard let webView else {
            progress = 0
            isLoading = false
            return
        }

        progress = webView.estimatedProgress
        isLoading = webView.isLoading

        progressObservation = webView.observe(\.estimatedProgress, options: [.new]) { [weak self] wv, _ in
            // KVO for WKWebView properties fires on the main thread
            MainActor.assumeIsolated {
                self?.progress = wv.estimatedProgress
            }
        }

        loadingObservation = webView.observe(\.isLoading, options: [.new]) { [weak self] wv, _ in
            // KVO for WKWebView properties fires on the main thread
            MainActor.assumeIsolated {
                guard let self else { return }
                if wv.isLoading {
                    self.hideTask?.cancel()
                    self.isLoading = true
                } else {
                    // Brief delay to show completed state before hiding
                    self.progress = 1.0
                    self.hideTask = Task {
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        guard !Task.isCancelled else { return }
                        self.isLoading = false
                        self.progress = 0
                    }
                }
            }
        }
    }

    deinit {
        progressObservation?.invalidate()
        loadingObservation?.invalidate()
    }
}
