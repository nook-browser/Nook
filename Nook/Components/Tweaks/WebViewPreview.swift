//
//  WebViewPreview.swift
//  Nook
//
//  WebView preview for testing tweaks in real-time.
//

import SwiftUI
import WebKit

struct WebViewPreview: View {
    let url: URL?
    let tweak: TweakEntity?
    @State private var webView: WKWebView?
    @State private var isLoading = false
    @StateObject private var tweakManager = TweakManager.shared
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        VStack(spacing: 0) {
            // Preview toolbar
            HStack {
                if let url = url {
                    Text(url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }

                Button("Reload") {
                    reloadPage()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Reset") {
                    resetTweaks()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.controlBackgroundColor))

            Divider()

            // WebView
            ZStack {
                if let url = url, let tweak = tweak {
                    PreviewWebView(
                        url: url,
                        tweak: tweak,
                        webView: $webView,
                        isLoading: $isLoading
                    )
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "globe")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)

                        Text("Preview Not Available")
                            .font(.title2)
                            .fontWeight(.medium)

                        if url == nil {
                            Text("Enter a URL to see the live preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        } else if tweak == nil {
                            Text("Configure the tweak to see the preview")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onAppear {
            if let url = url, let tweak = tweak {
                setupWebView(url: url, tweak: tweak)
            }
        }
        .onChange(of: url) { _, newURL in
            if let newURL = newURL, let tweak = tweak {
                setupWebView(url: newURL, tweak: tweak)
            }
        }
        .onChange(of: tweak) { _, newTweak in
            if let url = url, let newTweak = newTweak {
                setupWebView(url: url, tweak: newTweak)
            }
        }
    }

    private func setupWebView(url: URL, tweak: TweakEntity) {
        isLoading = true

        // Create configuration with tweak support
        let config = BrowserConfiguration.shared.webViewConfigurationWithTweaks(
            for: browserManager.currentProfile ?? Profile()
        )

        // Create WebView
        webView = WKWebView(frame: .zero, configuration: config)
        webView?.navigationDelegate = WebViewCoordinator { isLoading in
            self.isLoading = isLoading
        }

        // Apply the tweak to this WebView
        Task {
            if let webView = webView {
                await applyTweakToWebView(webView, tweak: tweak)
                await MainActor.run {
                    webView.load(URLRequest(url: url))
                }
            }
        }
    }

    private func applyTweakToWebView(_ webView: WKWebView, tweak: TweakEntity) async {
        guard let url = webView.url else { return }

        // Get rules for the tweak
        let rules = TweakManager.shared.getRules(for: tweak)
        let appliedTweak = AppliedTweak(from: tweak, rules: rules)

        // Generate and inject scripts
        await TweakManager.shared.injectTweaksIntoWebView(webView, for: [appliedTweak])
    }

    private func reloadPage() {
        webView?.reload()
    }

    private func resetTweaks() {
        guard let webView = webView else { return }

        // Remove all tweak scripts
        Task {
            await TweakManager.shared.clearTweaksFromWebView(webView)
        }
    }
}

// MARK: - Preview WebView
private struct PreviewWebView: NSViewRepresentable {
    let url: URL
    let tweak: TweakEntity
    @Binding var webView: WKWebView?
    @Binding var isLoading: Bool
    @EnvironmentObject var browserManager: BrowserManager

    func makeNSView(context: Context) -> WKWebView {
        let config = BrowserConfiguration.shared.webViewConfigurationWithTweaks(
            for: browserManager.currentProfile ?? Profile()
        )

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        self.webView = webView

        // Apply tweak before loading
        Task {
            await applyTweakToWebView(webView, tweak: tweak)
            await MainActor.run {
                webView.load(URLRequest(url: url))
            }
        }

        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // URL and tweak are handled in makeNSView
    }

    func makeCoordinator() -> WebViewCoordinator {
        WebViewCoordinator { loading in
            DispatchQueue.main.async {
                isLoading = loading
            }
        }
    }

    private func applyTweakToWebView(_ webView: WKWebView, tweak: TweakEntity) async {
        let rules = TweakManager.shared.getRules(for: tweak)
        let appliedTweak = AppliedTweak(from: tweak, rules: rules)

        await TweakManager.shared.injectTweaksIntoWebView(webView, for: [appliedTweak])
    }
}

// MARK: - WebView Coordinator
private class WebViewCoordinator: NSObject, WKNavigationDelegate {
    let onLoadingChange: (Bool) -> Void

    init(onLoadingChange: @escaping (Bool) -> Void) {
        self.onLoadingChange = onLoadingChange
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        onLoadingChange(true)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onLoadingChange(false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onLoadingChange(false)
        print("WebView navigation failed: \(error)")
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onLoadingChange(false)
        print("WebView provisional navigation failed: \(error)")
    }
}

#Preview {
    WebViewPreview(
        url: URL(string: "https://example.com"),
        tweak: {
            let tweak = TweakEntity(name: "Test Tweak", urlPattern: "example.com")
            return tweak
        }()
    )
    .environmentObject(BrowserManager())
    .frame(width: 600, height: 400)
}