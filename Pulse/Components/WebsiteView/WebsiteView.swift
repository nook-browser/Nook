//
//  WebsiteView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import WebKit

struct WebsiteView: View {
    @EnvironmentObject var browserManager: BrowserManager

    var body: some View {
        Group {
            if let currentTab = browserManager.tabManager.currentTab {
                // Add .id() modifier to force view recreation when tab changes
                TabWebViewWrapper(tab: currentTab)
                    .id(currentTab.id)  // This is crucial!
                    .background(Color(nsColor: .windowBackgroundColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            } else {
                EmptyWebsiteView()
            }
        }
    }
}

// MARK: - Tab WebView Wrapper
struct TabWebViewWrapper: NSViewRepresentable {
    let tab: Tab

    func makeNSView(context: Context) -> WKWebView {
        let webView = tab.webView
        print("Showing WebView for tab: \(tab.name)")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // The webView is managed by the Tab itself
        // No need to reload or recreate anything
    }
}
