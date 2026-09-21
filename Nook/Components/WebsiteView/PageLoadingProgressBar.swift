// Licensed under GPL-3.0. See LICENSE.
//
//  PageLoadingProgressBar.swift
//  Nook
//
//  Thin progress bar shown on the URL bar during page loads.
//  Observes WKWebView.estimatedProgress + isLoading via KVO.
//

import SwiftUI
import WebKit
import NookDesign
import NookWeb

struct PageLoadingProgressBar: View {
    let session: PageSession?

    @StateObject private var observer = WebViewLoadingObserver()

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                // Track background
                Rectangle()
                    .fill(NookDesign.Surface.fillPressed)
                    .opacity(observer.isLoading ? 1 : 0)

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
                    .animation(NookDesign.Motion.quick, value: observer.progress)
                    .opacity(observer.isLoading ? 1 : 0)
            }
        }
        .frame(height: 2.5)
        .animation(NookDesign.Motion.quick, value: observer.isLoading)
        // Observation tracks the session's web view, so a view created later attaches too.
        .onChange(of: session?.webView) { _, webView in
            observer.attach(to: webView)
        }
        .onAppear {
            observer.attach(to: session?.webView)
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
