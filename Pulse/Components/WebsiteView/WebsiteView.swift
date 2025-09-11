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
    @EnvironmentObject var splitManager: SplitViewManager
    @State private var hoveredLink: String?
    @State private var isCommandPressed: Bool = false
    @State private var isDropTargeted: Bool = false

    var body: some View {
        ZStack() {
            Group {
                if let currentTab = browserManager.tabManager.currentTab {
                    GeometryReader { proxy in
                        TabCompositorWrapper(
                            browserManager: browserManager,
                            hoveredLink: $hoveredLink,
                            isCommandPressed: $isCommandPressed,
                            splitFraction: splitManager.dividerFraction,
                            isSplit: splitManager.isSplit
                        )
                        .background(Color(nsColor: .windowBackgroundColor))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: {
                            if #available(macOS 26.0, *) {
                                return 12
                            } else {
                                return 6
                            }
                        }(), style: .continuous))
                        // Always-on-top split drop overlay for left/right hover & drops
                        .overlay {
                            SplitDropOverlay(containerWidthProvider: { proxy.size.width })
                                .environmentObject(browserManager)
                                .environmentObject(splitManager)
                        }
                        // Divider + pane close overlay
                        .overlay(alignment: .top) {
                            if splitManager.isSplit {
                                SplitControlsOverlay()
                                    .environmentObject(browserManager)
                                    .environmentObject(splitManager)
                            }
                        }
                    }
                    .contextMenu {
                        // Divider + close buttons overlay when split is active
                        if splitManager.isSplit {
                            Button("Exit Split View") { splitManager.exitSplit(keep: .left) }
                            Button("Swap Sides") { splitManager.swapSides() }
                        }
                    }
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
//                HStack {
//                    LinkStatusBar(hoveredLink: hoveredLink, isCommandPressed: isCommandPressed)
//                        .padding(10)
//                    Spacer()
//                }
                
            }
            
        }
    }

}

// MARK: - Tab Compositor Wrapper
struct TabCompositorWrapper: NSViewRepresentable {
    let browserManager: BrowserManager
    @Binding var hoveredLink: String?
    @Binding var isCommandPressed: Bool
    var splitFraction: CGFloat
    var isSplit: Bool

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
        
        // Mark current tab as accessed (resets unload timer)
        if let currentTab = browserManager.tabManager.currentTab {
            browserManager.compositorManager.markTabAccessed(currentTab.id)
            setupHoverCallbacks(for: currentTab)
        }
    }
    
    private func updateCompositor(_ containerView: NSView) {
        // Remove all existing webview subviews
        containerView.subviews.forEach { $0.removeFromSuperview() }

        // Add all loaded tabs to the compositor. If split view is active, show two panes;
        // otherwise show only the current tab.
        let currentSpacePinned: [Tab] = {
            if let space = browserManager.tabManager.currentSpace {
                return browserManager.tabManager.spacePinnedTabs(for: space.id)
            } else {
                return []
            }
        }()
        let allTabs = browserManager.tabManager.essentialTabs + currentSpacePinned + browserManager.tabManager.tabs
        
        let split = browserManager.splitManager
        if split.isSplit {
            // Auto-heal if one side is missing (tab closed etc.), but not during preview
            if !split.isPreviewActive {
                let leftResolved = split.resolveTab(split.leftTabId)
                let rightResolved = split.resolveTab(split.rightTabId)
                if leftResolved == nil && rightResolved == nil {
                    browserManager.splitManager.exitSplit(keep: .left)
                } else if leftResolved == nil, let _ = rightResolved {
                    browserManager.splitManager.exitSplit(keep: .right)
                } else if rightResolved == nil, let _ = leftResolved {
                    browserManager.splitManager.exitSplit(keep: .left)
                }
            }
            // Compute rects
            let fraction = max(split.minFraction, min(split.maxFraction, split.dividerFraction))
            let total = containerView.bounds
            let leftWidth = floor(total.width * fraction)
            let rightWidth = max(0, total.width - leftWidth)
            let leftRect = NSRect(x: total.minX, y: total.minY, width: leftWidth, height: total.height)
            let rightRect = NSRect(x: total.minX + leftWidth, y: total.minY, width: rightWidth, height: total.height)

            let leftId = split.leftTabId
            let rightId = split.rightTabId

            for tab in allTabs {
                guard !tab.isUnloaded, let webView = tab.webView else { continue }
                if tab.id == leftId {
                    webView.frame = leftRect
                    webView.autoresizingMask = [.height]
                    webView.isHidden = false
                    containerView.addSubview(webView)
                } else if tab.id == rightId {
                    webView.frame = rightRect
                    webView.autoresizingMask = [.height]
                    webView.isHidden = false
                    containerView.addSubview(webView)
                } else {
                    // Keep inactive webviews hidden
                    webView.frame = containerView.bounds
                    webView.autoresizingMask = [.width, .height]
                    webView.isHidden = true
                    containerView.addSubview(webView)
                }
            }
        } else {
            for tab in allTabs {
                // Only add tabs that are still in the tab manager (not closed)
                if !tab.isUnloaded, let webView = tab.webView {
                    webView.frame = containerView.bounds
                    webView.autoresizingMask = [.width, .height]
                    containerView.addSubview(webView)
                    webView.isHidden = tab.id != browserManager.tabManager.currentTab?.id
                }
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

// MARK: - Split Controls Overlay
private struct SplitControlsOverlay: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var splitManager: SplitViewManager

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let totalHeight = geo.size.height

            let x = CGFloat(splitManager.dividerFraction) * max(totalWidth, 1)
            // Divider bar
            ZStack {
                // Close buttons (small, top corners)
                HStack {
                    Button(action: { splitManager.closePane(.left) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .padding(.leading, 8)

                    Spacer()

                    Button(action: { splitManager.closePane(.right) }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .padding(6)
                    }
                    .buttonStyle(.plain)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.25), lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.2), radius: 2, x: 0, y: 1)
                    .padding(.trailing, 8)
                }
                .padding(.top, 8)

                // Draggable vertical divider handle
                Rectangle()
                    .fill(Color.white.opacity(0.75))
                    .frame(width: 2, height: totalHeight)
                    .position(x: x, y: totalHeight / 2)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.0001)) // hit target
                            .frame(width: 12, height: totalHeight)
                            .position(x: x, y: totalHeight / 2)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let width = max(totalWidth, 1)
                                        let newX = min(max(value.location.x, splitManager.minFraction * width), splitManager.maxFraction * width)
                                        splitManager.setDividerFraction(newX / width)
                                    }
                            )
                    }
            }
        }
        .allowsHitTesting(true)
    }
}

// MARK: - Split Drop Overlay (always on top of web content)
private struct SplitDropOverlay: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var splitManager: SplitViewManager

    // Visual state driven via SplitViewManager.previewSide/isPreviewActive

    let containerWidthProvider: () -> CGFloat

    // Accept plain text UUID ids (AppKit drags also publish NSPasteboard string now)

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Visual side highlight during drag-over
                if splitManager.isPreviewActive, let side = splitManager.previewSide {
                    let w = proxy.size.width
                    let h = proxy.size.height
                    let rect = side == .left
                        ? CGRect(x: 0, y: 0, width: w/2, height: h)
                        : CGRect(x: w/2, y: 0, width: w/2, height: h)
                    Color.accentColor.opacity(0.08)
                        .frame(width: rect.width, height: rect.height)
                        .position(x: rect.midX, y: rect.midY)
                        .transition(.opacity)
                }
            }
            .contentShape(Rectangle())
            .onDrop(
                of: [.text],
                delegate: SplitOverlayDropDelegate(
                    browserManager: browserManager,
                    splitManager: splitManager,
                    containerWidth: proxy.size.width
                )
            )
        }
    }
}

private struct SplitOverlayDropDelegate: DropDelegate {
    let browserManager: BrowserManager
    let splitManager: SplitViewManager
    let containerWidth: CGFloat

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        updatePreview(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updatePreview(info)
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        splitManager.endPreview(cancel: false)
        guard let provider = info.itemProviders(for: [.text]).first else { return false }
        provider.loadObject(ofClass: NSString.self) { obj, _ in
            guard let s = obj as? String, let id = UUID(uuidString: s) else { return }
            DispatchQueue.main.async {
                let all = browserManager.tabManager.allTabs()
                guard let tab = all.first(where: { $0.id == id }) else { return }
                let side: SplitViewManager.Side = (info.location.x < containerWidth / 2) ? .left : .right
                splitManager.enterSplit(with: tab, placeOn: side)
            }
        }
        return true
    }

    func dropExited(info: DropInfo) {
        splitManager.endPreview(cancel: true)
    }

    private func updatePreview(_ info: DropInfo) {
        let side: SplitViewManager.Side = (info.location.x < containerWidth / 2) ? .left : .right
        splitManager.beginPreview(side: side)
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
