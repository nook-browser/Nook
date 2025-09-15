//
//  WebsiteView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import WebKit
import AppKit

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
                            isSplit: splitManager.isSplit,
                            leftId: splitManager.leftTabId,
                            rightId: splitManager.rightTabId
                        )
                        .background(shouldShowSplit ? Color.clear : Color(nsColor: .windowBackgroundColor))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: {
                            if #available(macOS 26.0, *) {
                                return 12
                            } else {
                                return 6
                            }
                        }(), style: .continuous))
                        // Divider + pane close overlay
                        .overlay(alignment: .top) {
                            if shouldShowSplit {
                                SplitControlsOverlay()
                                    .environmentObject(browserManager)
                                    .environmentObject(splitManager)
                            }
                        }
                        // Restore visual margins around the web content card
                        // - Keep leading flush with the sidebar when visible
                        // - Add a leading margin when the sidebar is hidden
                        .padding(.trailing, 8)
                        .padding(.leading, browserManager.isSidebarVisible ? 0 : 8)
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
                    if let assist = browserManager.oauthAssist,
                       browserManager.tabManager.currentTab?.id == assist.tabId {
                        OAuthAssistBanner(host: assist.host)
                            .environmentObject(browserManager)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: browserManager.oauthAssist)
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
    var leftId: UUID?
    var rightId: UUID?

    class Coordinator {
        var lastIsSplit: Bool = false
        var lastLeftId: UUID? = nil
        var lastRightId: UUID? = nil
        var lastCurrentId: UUID? = nil
        var lastFraction: CGFloat = -1
        var lastSize: CGSize = .zero
        var frameObserver: NSObjectProtocol? = nil
        deinit {
            if let token = frameObserver {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.postsFrameChangedNotifications = true
        
        // Store reference to container view in browser manager
        browserManager.compositorContainerView = containerView
        
        // Install AppKit drag-capture overlay above all webviews
        let overlay = SplitDropCaptureView(frame: containerView.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.browserManager = browserManager
        overlay.splitManager = browserManager.splitManager
        overlay.layer?.zPosition = 10_000
        containerView.addSubview(overlay)

        // Observe size changes to recompute pane layout when available width changes
        let coord = context.coordinator
        coord.frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: containerView,
            queue: .main
        ) { [weak containerView] _ in
            guard let cv = containerView else { return }
            // Rebuild compositor to anchor left/right panes to new bounds
            updateCompositor(cv)
            coord.lastSize = cv.bounds.size
        }

        // Set up link hover callbacks for current tab
        if let currentTab = browserManager.tabManager.currentTab {
            setupHoverCallbacks(for: currentTab)
        }
        
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Only rebuild compositor when meaningful inputs change
        let size = nsView.bounds.size
        let currentId = browserManager.tabManager.currentTab?.id
        let needsRebuild =
            context.coordinator.lastIsSplit != isSplit ||
            context.coordinator.lastLeftId != leftId ||
            context.coordinator.lastRightId != rightId ||
            context.coordinator.lastCurrentId != currentId ||
            abs(CGFloat(context.coordinator.lastFraction) - CGFloat(splitFraction)) > 0.0001 ||
            context.coordinator.lastSize != size

        if needsRebuild {
            updateCompositor(nsView)
            context.coordinator.lastIsSplit = isSplit
            context.coordinator.lastLeftId = leftId
            context.coordinator.lastRightId = rightId
            context.coordinator.lastCurrentId = currentId
            context.coordinator.lastFraction = splitFraction
            context.coordinator.lastSize = size
        }
        
        // Mark current tab as accessed (resets unload timer)
        if let currentTab = browserManager.tabManager.currentTab {
            browserManager.compositorManager.markTabAccessed(currentTab.id)
            setupHoverCallbacks(for: currentTab)
        }
    }
    
    private func updateCompositor(_ containerView: NSView) {
        // Remove all existing webview subviews
        // Preserve the last overlay subview if present, then re-add
        let overlay = containerView.subviews.compactMap { $0 as? SplitDropCaptureView }.first
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
        let currentId = browserManager.tabManager.currentTab?.id
        let isCurrentPane = (currentId != nil) && (currentId == split.leftTabId || currentId == split.rightTabId)
        if split.isSplit && isCurrentPane {
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

            // Compute pane rects with a visible gap
            let gap: CGFloat = 8
            let fraction = max(split.minFraction, min(split.maxFraction, split.dividerFraction))
            let total = containerView.bounds
            let leftWidthRaw = floor(total.width * fraction)
            let rightWidthRaw = max(0, total.width - leftWidthRaw)
            let leftRect = NSRect(x: total.minX,
                                  y: total.minY,
                                  width: max(1, leftWidthRaw - gap/2),
                                  height: total.height)
            let rightRect = NSRect(x: total.minX + leftWidthRaw + gap/2,
                                   y: total.minY,
                                   width: max(1, rightWidthRaw - gap/2),
                                   height: total.height)

            let leftId = split.leftTabId
            let rightId = split.rightTabId

            // Add pane containers with rounded corners and background
            let activeId = browserManager.tabManager.currentTab?.id
            let accent = browserManager.gradientColorManager.displayGradient.primaryNSColor
            // Resolve pane tabs across ALL tabs (not just current space)
            let allKnownTabs = browserManager.tabManager.allTabs()

            if let lId = leftId, let leftTab = allKnownTabs.first(where: { $0.id == lId }) {
                // Force-create/ensure loaded when visible in split
                let lWeb = leftTab.activeWebView
                let pane = makePaneContainer(frame: leftRect, isActive: (activeId == lId), accent: accent)
                containerView.addSubview(pane)
                lWeb.frame = pane.bounds
                lWeb.autoresizingMask = [.width, .height]
                lWeb.isHidden = false
                pane.addSubview(lWeb)
            }

            if let rId = rightId, let rightTab = allKnownTabs.first(where: { $0.id == rId }) {
                // Force-create/ensure loaded when visible in split
                let rWeb = rightTab.activeWebView
                let pane = makePaneContainer(frame: rightRect, isActive: (activeId == rId), accent: accent)
                containerView.addSubview(pane)
                rWeb.frame = pane.bounds
                rWeb.autoresizingMask = [.width, .height]
                rWeb.isHidden = false
                pane.addSubview(rWeb)
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

        // Re-add overlay on top
        if let overlay = overlay {
            overlay.frame = containerView.bounds
            overlay.autoresizingMask = [.width, .height]
            containerView.addSubview(overlay)
            overlay.layer?.zPosition = 10_000
            overlay.browserManager = browserManager
            overlay.splitManager = browserManager.splitManager
        } else {
            let newOverlay = SplitDropCaptureView(frame: containerView.bounds)
            newOverlay.autoresizingMask = [.width, .height]
            newOverlay.browserManager = browserManager
            newOverlay.splitManager = browserManager.splitManager
            newOverlay.layer?.zPosition = 10_000
            containerView.addSubview(newOverlay)
        }
    }

    private func makePaneContainer(frame: NSRect, isActive: Bool, accent: NSColor) -> NSView {
        let v = NSView(frame: frame)
        v.wantsLayer = true
        if let layer = v.layer {
            layer.cornerRadius = {
                if #available(macOS 26.0, *) { return 12 } else { return 6 }
            }()
            layer.masksToBounds = true
            layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
            // Slim border around the active pane using the space accent color
            layer.borderWidth = isActive ? 1.0 : 0.0
            layer.borderColor = isActive ? accent.withAlphaComponent(0.9).cgColor : NSColor.clear.cgColor
        }
        // Allow the pane container to grow/shrink with its superview's size changes.
        // Width is always recomputed on frame changes via our observer above, but this
        // keeps the panes visually in sync during live resize.
        v.autoresizingMask = [.width, .height]
        return v
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

private extension WebsiteView {
    var shouldShowSplit: Bool {
        guard splitManager.isSplit else { return false }
        guard let current = browserManager.tabManager.currentTab?.id else { return false }
        return current == splitManager.leftTabId || current == splitManager.rightTabId
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
                    Button(action: { closeSide(.left) }) {
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

                    Button(action: { closeSide(.right) }) {
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

                // Gap visuals and drag handle
                let gap: CGFloat = 8
                // Thin grey indicator line to suggest adjustability
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.7))
                    .frame(width: 1, height: totalHeight)
                    .position(x: x, y: totalHeight / 2)
                    .allowsHitTesting(false)
                // Invisible drag handle centered in the gap between panes
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.clear)
                    .contentShape(Rectangle())
                    .frame(width: gap, height: totalHeight)
                    .position(x: x, y: totalHeight / 2)
                    .onHover { hovering in
                        if hovering { NSCursor.resizeLeftRight.set() } else { NSCursor.arrow.set() }
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let width = max(totalWidth, 1)
                                let newX = min(max(value.location.x, splitManager.minFraction * width), splitManager.maxFraction * width)
                                splitManager.setDividerFraction(newX / width)
                            }
                    )
                    .zIndex(1000)
            }
        }
        .allowsHitTesting(true)
    }

    private func closeSide(_ side: SplitViewManager.Side) {
        let id: UUID? = (side == .left) ? splitManager.leftTabId : splitManager.rightTabId
        if let id = id {
            browserManager.tabManager.removeTab(id)
        } else {
            // Fallback: just exit split
            splitManager.exitSplit(keep: side == .left ? .right : .left)
        }
    }
}

// (Removed SwiftUI SplitDropOverlay; AppKit SplitDropCaptureView handles all drag capture.)

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
