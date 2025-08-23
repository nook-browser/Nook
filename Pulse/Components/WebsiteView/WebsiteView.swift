//
//  WebsiteView.swift
//  Pulse
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import WebKit

// MARK: - Status Bar View
struct LinkStatusBar: View {
    let hoveredLink: String?
    let isCommandPressed: Bool
    
    var body: some View {
        if let link = hoveredLink, !link.isEmpty {
            Text(isCommandPressed ? "Open \(link) in a new tab and focus it" : link)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            Color(hex: "3E4D2E"),
                            Color(hex: "2E2E2E")
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: 999))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(.white.opacity(0.2), lineWidth: 1)
                )
                .opacity(hoveredLink != nil && !hoveredLink!.isEmpty ? 1 : 0)
                .animation(.easeInOut(duration: 0.2), value: hoveredLink)
        }
    }
}

struct WebsiteView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @State private var hoveredLink: String?
    @State private var isCommandPressed: Bool = false

    var body: some View {
        ZStack() {
            Group {
                if let currentTab = browserManager.tabManager.currentTab {
                    TabCompositorWrapper(
                        browserManager: browserManager,
                        hoveredLink: $hoveredLink,
                        isCommandPressed: $isCommandPressed
                    )
                    .background(Color(nsColor: .windowBackgroundColor))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: { 
                        if #available(macOS 26.0, *) {
                            return 12
                        } else {
                            return 6
                        }
                    }()))
                } else {
                    EmptyWebsiteView()
                }
            }
            VStack {
                HStack {
                    Spacer()
                    if browserManager.didCopyURL {
                        WebsitePopup()
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: browserManager.didCopyURL)
                            .padding(10)
                    }
                }
                Spacer()
                HStack {
                    LinkStatusBar(hoveredLink: hoveredLink, isCommandPressed: isCommandPressed)
                        .padding(10)
                    Spacer()
                }
                
            }
            
        }
    }
}

// MARK: - Tab Compositor Wrapper
struct TabCompositorWrapper: NSViewRepresentable {
    let browserManager: BrowserManager
    @Binding var hoveredLink: String?
    @Binding var isCommandPressed: Bool

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        
        // Store reference to container view in browser manager
        browserManager.compositorContainerView = containerView
        
        // Set up link hover callbacks for current tab
        if let currentTab = browserManager.tabManager.currentTab {
            setupHoverCallbacks(for: currentTab)
        }
        
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Update the compositor when tabs change
        updateCompositor(nsView)
        
        // Update hover callbacks for current tab
        if let currentTab = browserManager.tabManager.currentTab {
            setupHoverCallbacks(for: currentTab)
        }
    }
    
    private func updateCompositor(_ containerView: NSView) {
        // Remove all existing webview subviews
        containerView.subviews.forEach { $0.removeFromSuperview() }
        
        // Add all loaded tabs to the compositor
        let allTabs = browserManager.tabManager.pinnedTabs + browserManager.tabManager.tabs
        
        for tab in allTabs {
            if let webView = tab.webView {
                // Only add webviews that are actually loaded
                webView.frame = containerView.bounds
                webView.autoresizingMask = [.width, .height]
                containerView.addSubview(webView)
                
                // Simple visibility: hide inactive tabs for performance
                // Media should continue playing even when hidden (no more forced pause)
                webView.isHidden = tab.id != browserManager.tabManager.currentTab?.id
            }
        }
    }
    
    private func setupHoverCallbacks(for tab: Tab) {
        // Set up link hover callback
        tab.onLinkHover = { [self] href in
            DispatchQueue.main.async {
                self.hoveredLink = href
                if let href = href {
                    print("Hovering over link: \(href)")
                }
            }
        }
        
        // Set up command hover callback
        tab.onCommandHover = { [self] href in
            DispatchQueue.main.async {
                self.isCommandPressed = href != nil
            }
        }
    }
}

// MARK: - Tab WebView Wrapper with Hover Detection (Legacy)
struct TabWebViewWrapper: NSViewRepresentable {
    let tab: Tab
    @Binding var hoveredLink: String?
    @Binding var isCommandPressed: Bool

    func makeNSView(context: Context) -> WKWebView {
        let webView = tab.webView
        
        // Set up link hover callback
        tab.onLinkHover = { [self] href in
            DispatchQueue.main.async {
                self.hoveredLink = href
                if let href = href {
                    print("Hovering over link: \(href)")
                }
            }
        }
        
        // Set up command hover callback
        tab.onCommandHover = { [self] href in
            DispatchQueue.main.async {
                self.isCommandPressed = href != nil
            }
        }
        
        print("Showing WebView for tab: \(tab.name)")
        return tab.activeWebView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // The webView is managed by the Tab
    }
}
