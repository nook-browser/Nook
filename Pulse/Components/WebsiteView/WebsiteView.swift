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
    @State private var liveRatio: CGFloat = 0.5 // mirrors browserManager.splitRatio
    
    var body: some View {
        Group {
            if let left = browserManager.tabManager.currentTab {
                if browserManager.hasSplitView,
                   let right = browserManager.tabManager.currentSplittedTab {
                    
                    if #available(macOS 13.0, *) {
                        // Native macOS split; uses flexible sizing.
                        HSplitView {
                            pane(for: left)
                                .frame(minWidth: 260)
                            
                            pane(for: right)
                                .frame(minWidth: 260)
                        }
                        .onAppear { liveRatio = browserManager.splitRatio }
                        // If you want precise ratio control, wrap each pane in a sized container
                        // with GeometryReader and update `browserManager.updateSplitRatio(_:)`.
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        
                    } else {
                        // Fallback: manual drag with ratio
                        GeometryReader { geo in
                            let width = geo.size.width
                            HStack(spacing: 0) {
                                pane(for: left)
                                    .frame(width: max(260, width * liveRatio))
                                
                                Divider().frame(width: 1)
                                
                                pane(for: right)
                                    .frame(width: max(260, width * (1 - liveRatio)))
                            }
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let newRatio = (value.location.x / width)
                                        liveRatio = min(max(0.2, newRatio), 0.8)
                                        browserManager.updateSplitRatio(liveRatio)
                                    }
                            )
                            .onAppear { liveRatio = browserManager.splitRatio }
                        }
                    }
                    
                } else {
                    pane(for: left)
                }
            } else {
                EmptyWebsiteView()
            }
        }
    }
    
    @ViewBuilder
    private func pane(for tab: Tab) -> some View {
        TabWebViewWrapper(tab: tab)
            .id(tab.id) // critical: different tab == different WKWebView
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: {
                if #available(macOS 14.0, *) { return 12 } else { return 6 }
            }()))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
