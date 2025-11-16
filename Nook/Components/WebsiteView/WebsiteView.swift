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
    let accentColor: Color
    @Environment(\.colorScheme) var colorScheme
    @State private var shouldShow: Bool = false
    @State private var hoverTask: Task<Void, Never>?
    @State private var displayedLink: String? = nil
    
    var body: some View {
        // Show the view if we have a link to display (current or last shown)
        if let link = displayedLink, !link.isEmpty {
            Text(displayText(for: link))
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(textColor)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 999))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .stroke(borderColor, lineWidth: 1)
                )
                .opacity(shouldShow ? 1 : 0)
                .animation(.easeOut(duration: 0.25), value: shouldShow)
                .onChange(of: hoveredLink) { newLink in
                    handleHoverChange(newLink: newLink)
                }
                .onAppear {
                    handleHoverChange(newLink: hoveredLink)
                }
                .onDisappear {
                    hoverTask?.cancel()
                    hoverTask = nil
                    shouldShow = false
                    displayedLink = nil
                }
        } else {
            Color.clear
                .onChange(of: hoveredLink) { newLink in
                    handleHoverChange(newLink: newLink)
                }
        }
    }
    
    private func displayText(for link: String) -> String {
        let truncatedLink = truncateLink(link)
        if isCommandPressed {
            return "Open \(truncatedLink) in a new tab and focus it"
        } else {
            return truncatedLink
        }
    }
    
    private func handleHoverChange(newLink: String?) {
        // Cancel any existing task
        hoverTask?.cancel()
        hoverTask = nil
        
        if let link = newLink, !link.isEmpty {
            // New link - update displayed link immediately
            displayedLink = link
            
            // Wait then show if not already showing
            if !shouldShow {
                hoverTask = Task {
                    try? await Task.sleep(nanoseconds: 500_000_000) // 500ms
                    if !Task.isCancelled {
                        await MainActor.run { shouldShow = true }
                    }
                }
            }
        } else {
            // Link cleared - wait then hide
            hoverTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s delay
                if !Task.isCancelled {
                    await MainActor.run {
                        shouldShow = false
                    }
                    // Clear displayed link after fade out animation completes
                    try? await Task.sleep(nanoseconds: 250_000_000) // 0.25s for fade out
                    if !Task.isCancelled {
                        await MainActor.run {
                            displayedLink = nil
                        }
                    }
                }
            }
        }
    }
    
    private func truncateLink(_ link: String) -> String {
        if link.count > 60 {
            let firstPart = String(link.prefix(30))
            let lastPart = String(link.suffix(30))
            return "\(firstPart)...\(lastPart)"
        }
        return link
    }
    
    private var backgroundColor: some View {
        Group {
            if colorScheme == .dark {
                // Dark mode: gradient background using accent color
                LinearGradient(
                    gradient: Gradient(colors: [
                        accentColor,
                        lighterAccentColor
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
            } else {
                // Light mode: white background
                Color.white
            }
        }
    }
    
    private var lighterAccentColor: Color {
        #if os(macOS)
        // Blend the accent color with white for lighter variant
        let nsColor = NSColor(accentColor)
        if let blended = nsColor.blended(withFraction: 0.35, of: .white) {
            return Color(nsColor: blended)
        } else {
            return accentColor
        }
        #else
        return accentColor
        #endif
    }
    
    private var textColor: Color {
        if colorScheme == .dark {
            return Color.white
        } else {
            // Light mode: colored text using accent color
            return accentColor
        }
    }
    
    private var borderColor: Color {
        if colorScheme == .dark {
            return .white.opacity(0.2)
        } else {
            return accentColor.opacity(0.3)
        }
    }
}

struct WebsiteView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(\.nookSettings) var nookSettings
    @State private var hoveredLink: String?
    @State private var isCommandPressed: Bool = false
    @State private var isDropTargeted: Bool = false

    private var cornerRadius: CGFloat {
        if #available(macOS 26.0, *) {
            return 12
        } else {
            return 6
        }
    }
    
    private var webViewClipShape: AnyShape {
        let hasTopBar = nookSettings.topBarAddressView
        
        if hasTopBar {
            return AnyShape(UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: 0,
                style: .continuous
            ))
        } else {
            return AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
    }

    var body: some View {
        ZStack() {
            Group {
                if browserManager.currentTab(for: windowState) != nil {
                    GeometryReader { proxy in
                        TabCompositorWrapper(
                            browserManager: browserManager,
                            hoveredLink: $hoveredLink,
                            isCommandPressed: $isCommandPressed,
                            splitFraction: splitManager.dividerFraction(for: windowState.id),
                            isSplit: splitManager.isSplit(for: windowState.id),
                            leftId: splitManager.leftTabId(for: windowState.id),
                            rightId: splitManager.rightTabId(for: windowState.id),
                            windowState: windowState
                        )
                        .background(shouldShowSplit ? Color.clear : Color(nsColor: .windowBackgroundColor))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(webViewClipShape)
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 0)
                        // Divider + pane close overlay
                        .overlay(alignment: .top) {
                            if shouldShowSplit {
                                SplitControlsOverlay()
                                    .environmentObject(browserManager)
                                    .environmentObject(splitManager)
                                    .environment(windowState)
                            }
                        }
                        // Critical: Use allowsHitTesting to prevent SwiftUI from intercepting mouse events
                        // This allows right-clicks to pass through to the underlying NSView (WKWebView)
                        .allowsHitTesting(true)
                        .contentShape(Rectangle())
                    }
                    // Removed SwiftUI contextMenu - it intercepts ALL right-clicks
                    // WKWebView's willOpenMenu will handle context menus for images
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
                       browserManager.currentTab(for: windowState)?.id == assist.tabId {
                        OAuthAssistBanner(host: assist.host)
                            .environmentObject(browserManager)
                            .animation(.spring(response: 0.5, dampingFraction: 0.8), value: browserManager.oauthAssist)
                            .padding(10)
                    }
                }
                Spacer()
                if nookSettings.showLinkStatusBar {
                    HStack {
                        LinkStatusBar(
                            hoveredLink: hoveredLink,
                            isCommandPressed: isCommandPressed,
                            accentColor: browserManager.gradientColorManager.primaryColor
                        )
                        .padding(10)
                        Spacer()
                    }
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
    var splitFraction: CGFloat
    var isSplit: Bool
    var leftId: UUID?
    var rightId: UUID?
    let windowState: BrowserWindowState

    class Coordinator {
        weak var browserManager: BrowserManager?
        let windowState: BrowserWindowState
        var lastIsSplit: Bool = false
        var lastLeftId: UUID? = nil
        var lastRightId: UUID? = nil
        var lastCurrentId: UUID? = nil
        var lastFraction: CGFloat = -1
        var lastSize: CGSize = .zero
        var lastVersion: Int = -1
        var frameObserver: NSObjectProtocol? = nil
        init(browserManager: BrowserManager?, windowState: BrowserWindowState) {
            self.browserManager = browserManager
            self.windowState = windowState
        }
        deinit {
            if let token = frameObserver {
                NotificationCenter.default.removeObserver(token)
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(browserManager: browserManager, windowState: windowState) }

    func makeNSView(context: Context) -> NSView {
        let containerView = ContainerView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.postsFrameChangedNotifications = true

        // Store reference to container view in WebViewCoordinator
        browserManager.webViewCoordinator?.setCompositorContainerView(containerView, for: windowState.id)
        
        // Install AppKit drag-capture overlay above all webviews
        let overlay = SplitDropCaptureView(frame: containerView.bounds)
        overlay.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
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
        if let currentTab = browserManager.currentTab(for: windowState) {
            setupHoverCallbacks(for: currentTab)
        }
        
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Only rebuild compositor when meaningful inputs change
        let size = nsView.bounds.size
        let currentId = browserManager.currentTab(for: windowState)?.id
        let compositorVersion = windowState.compositorVersion
        let needsRebuild =
            context.coordinator.lastIsSplit != isSplit ||
            context.coordinator.lastLeftId != leftId ||
            context.coordinator.lastRightId != rightId ||
            context.coordinator.lastCurrentId != currentId ||
            abs(CGFloat(context.coordinator.lastFraction) - CGFloat(splitFraction)) > 0.0001 ||
            context.coordinator.lastSize != size ||
            context.coordinator.lastVersion != compositorVersion

        if needsRebuild {
            updateCompositor(nsView)
            context.coordinator.lastIsSplit = isSplit
            context.coordinator.lastLeftId = leftId
            context.coordinator.lastRightId = rightId
            context.coordinator.lastCurrentId = currentId
            context.coordinator.lastFraction = splitFraction
            context.coordinator.lastSize = size
            context.coordinator.lastVersion = compositorVersion
        }
        
        // Mark current tab as accessed (resets unload timer)
        if let currentTab = browserManager.currentTab(for: windowState) {
            browserManager.compositorManager.markTabAccessed(currentTab.id)
            setupHoverCallbacks(for: currentTab)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.browserManager?.webViewCoordinator?.removeCompositorContainerView(for: coordinator.windowState.id)
    }

    private func updateCompositor(_ containerView: NSView) {
        // Remove all existing webview subviews
        // Preserve the last overlay subview if present, then re-add
        let overlay = containerView.subviews.compactMap { $0 as? SplitDropCaptureView }.first
        containerView.subviews.forEach { $0.removeFromSuperview() }
        
        // Add tabs that should be displayed in this window. If split view is active, show two panes;
        // otherwise show only the current tab.
        let allTabs = browserManager.tabsForDisplay(in: windowState)
        
        let split = browserManager.splitManager
        let currentId = browserManager.currentTab(for: windowState)?.id
        let leftId = split.leftTabId(for: windowState.id)
        let rightId = split.rightTabId(for: windowState.id)
        let isCurrentPane = (currentId != nil) && (currentId == leftId || currentId == rightId)
        if split.isSplit(for: windowState.id) && isCurrentPane {
            // Auto-heal if one side is missing (tab closed etc.), but not during preview
            let splitState = split.getSplitState(for: windowState.id)
            if !splitState.isPreviewActive {
                let leftResolved = split.resolveTab(leftId)
                let rightResolved = split.resolveTab(rightId)
                if leftResolved == nil && rightResolved == nil {
                    browserManager.splitManager.exitSplit(keep: .left, for: windowState.id)
                } else if leftResolved == nil, let _ = rightResolved {
                    browserManager.splitManager.exitSplit(keep: .right, for: windowState.id)
                } else if rightResolved == nil, let _ = leftResolved {
                    browserManager.splitManager.exitSplit(keep: .left, for: windowState.id)
                }
            }

            // Compute pane rects with a visible gap
            let gap: CGFloat = 8
            let fraction = max(split.minFraction, min(split.maxFraction, split.dividerFraction(for: windowState.id)))
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

            let leftId = split.leftTabId(for: windowState.id)
            let rightId = split.rightTabId(for: windowState.id)

            // Add pane containers with rounded corners and background
            let activeSide = split.activeSide(for: windowState.id)
            let accent = browserManager.gradientColorManager.displayGradient.primaryNSColor
            // Resolve pane tabs across ALL tabs (not just current space)
            let allKnownTabs = browserManager.tabManager.allTabs()

            if let lId = leftId, let leftTab = allKnownTabs.first(where: { $0.id == lId }) {
                // Force-create/ensure loaded when visible in split
                let lWeb = webView(for: leftTab, windowId: windowState.id)
                let pane = makePaneContainer(frame: leftRect, isActive: (activeSide == .left), accent: accent)
                containerView.addSubview(pane)
                lWeb.frame = pane.bounds
                lWeb.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
                lWeb.isHidden = false
                pane.addSubview(lWeb)
                
            }

            if let rId = rightId, let rightTab = allKnownTabs.first(where: { $0.id == rId }) {
                // Force-create/ensure loaded when visible in split
                let rWeb = webView(for: rightTab, windowId: windowState.id)
                let pane = makePaneContainer(frame: rightRect, isActive: (activeSide == .right), accent: accent)
                containerView.addSubview(pane)
                rWeb.frame = pane.bounds
                rWeb.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
                rWeb.isHidden = false
                pane.addSubview(rWeb)
                
            }
        } else {
            for tab in allTabs {
                // Only add tabs that are still in the tab manager (not closed)
                if !tab.isUnloaded {
                    let webView = webView(for: tab, windowId: windowState.id)
                    webView.frame = containerView.bounds
                    webView.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
                    containerView.addSubview(webView)
                    webView.isHidden = tab.id != browserManager.currentTab(for: windowState)?.id
                }
            }
            
        }

  
        // Re-add overlay on top
        if let overlay = overlay {
            overlay.frame = containerView.bounds
            overlay.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
            containerView.addSubview(overlay)
            overlay.layer?.zPosition = 10_000
            overlay.browserManager = browserManager
            overlay.splitManager = browserManager.splitManager
            overlay.windowId = windowState.id
        } else {
            let newOverlay = SplitDropCaptureView(frame: containerView.bounds)
            newOverlay.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
            newOverlay.browserManager = browserManager
            newOverlay.splitManager = browserManager.splitManager
            newOverlay.windowId = windowState.id
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
        v.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
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

    private func webView(for tab: Tab, windowId: UUID) -> WKWebView {
        if let existing = browserManager.getWebView(for: tab.id, in: windowId) {
            return existing
        }
        return browserManager.createWebView(for: tab.id, in: windowId)
    }


}

// MARK: - WebsiteView Extensions

private extension WebsiteView {
    var shouldShowSplit: Bool {
        guard splitManager.isSplit(for: windowState.id) else { return false }
        guard let current = browserManager.currentTab(for: windowState)?.id else { return false }
        return current == splitManager.leftTabId(for: windowState.id) || current == splitManager.rightTabId(for: windowState.id)
    }
}

// MARK: - Container View that forwards right-clicks to webviews

private class ContainerView: NSView {
    // Don't intercept events - let them pass through to webviews
    override var acceptsFirstResponder: Bool { false }
    
    // Forward right-clicks to the webview below so context menus work
    override func rightMouseDown(with event: NSEvent) {
        print("🔽 [ContainerView] rightMouseDown received, forwarding to webview")
        // Find the webview at this point and forward the event
        let point = convert(event.locationInWindow, from: nil)
        // Use hitTest to find the actual view at this point (will skip overlay if hitTest returns nil)
        if let hitView = hitTest(point) {
            if let webView = hitView as? WKWebView {
                print("🔽 [ContainerView] Found webview via hitTest, forwarding rightMouseDown")
                webView.rightMouseDown(with: event)
                return
            }
            // Check if hitView contains a webview
            if let webView = findWebView(in: hitView, at: point) {
                print("🔽 [ContainerView] Found nested webview, forwarding rightMouseDown")
                webView.rightMouseDown(with: event)
                return
            }
        }
        // Fallback: search all subviews
        for subview in subviews.reversed() {
            if let webView = findWebView(in: subview, at: point) {
                print("🔽 [ContainerView] Found webview in subviews, forwarding rightMouseDown")
                webView.rightMouseDown(with: event)
                return
            }
        }
        print("🔽 [ContainerView] No webview found, calling super")
        super.rightMouseDown(with: event)
    }
    
    private func findWebView(in view: NSView, at point: NSPoint) -> WKWebView? {
        let pointInView = view.convert(point, from: self)
        if view.bounds.contains(pointInView) {
            if let webView = view as? WKWebView {
                return webView
            }
            for subview in view.subviews {
                if let webView = findWebView(in: subview, at: point) {
                    return webView
                }
            }
        }
        return nil
    }
}

// Split view context menu is handled via buttons in SplitControlsOverlay
// We don't use SwiftUI's contextMenu modifier because it intercepts all right-clicks
// and prevents WKWebView's willOpenMenu from being called

// MARK: - Split Controls Overlay
private struct SplitControlsOverlay: View {
    @EnvironmentObject var browserManager: BrowserManager
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let totalWidth = geo.size.width
            let totalHeight = geo.size.height

            let x = CGFloat(splitManager.dividerFraction(for: windowState.id)) * max(totalWidth, 1)
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
                                splitManager.setDividerFraction(newX / width, for: windowState.id)
                            }
                    )
                    .zIndex(1000)
            }
        }
        .allowsHitTesting(true)
    }

    private func closeSide(_ side: SplitViewManager.Side) {
        let id: UUID? = (side == .left) ? splitManager.leftTabId(for: windowState.id) : splitManager.rightTabId(for: windowState.id)
        if let id = id {
            browserManager.tabManager.removeTab(id)
        } else {
            // Fallback: just exit split
            splitManager.exitSplit(keep: side == .left ? .right : .left, for: windowState.id)
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

