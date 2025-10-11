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
    @Environment(BrowserManager.self) private var browserManager
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(SplitViewManager.self) private var splitManager
    @State private var hoveredLink: String?
    @State private var isCommandPressed: Bool = false
    @State private var isDropTargeted: Bool = false

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
                        .clipShape(RoundedRectangle(cornerRadius: {
                            if windowState.isFullScreen {
                                return 0
                            }
                            if #available(macOS 26.0, *) {
                                return 12
                            } else {
                                return 6
                            }
                        }(), style: .continuous))
                        .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 0)
                        // Divider + pane close overlay
                        .overlay(alignment: .top) {
                            if shouldShowSplit {
                                SplitControlsOverlay()
                                    .environment(browserManager)
                                    .environment(splitManager)
                                    .environment(windowState)
                            }
                        }
                    }
                    .contextMenu {
                        // Divider + close buttons overlay when split is active
                        if splitManager.isSplit(for: windowState.id) {
                            Button("Exit Split View") { splitManager.exitSplit(keep: .left, for: windowState.id) }
                            Button("Swap Sides") { splitManager.swapSides(for: windowState.id) }
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
                       browserManager.currentTab(for: windowState)?.id == assist.tabId {
                        OAuthAssistBanner(host: assist.host)
                            .environment(browserManager)
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
        let containerView = NSView()
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.clear.cgColor
        containerView.postsFrameChangedNotifications = true

        // Store reference to container view in browser manager
        browserManager.setCompositorContainerView(containerView, for: windowState.id)
        
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
        coordinator.browserManager?.removeCompositorContainerView(for: coordinator.windowState.id)
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
            let activeId = browserManager.currentTab(for: windowState)?.id
            let accent = browserManager.gradientColorManager.displayGradient.primaryNSColor
            // Resolve pane tabs across ALL tabs (not just current space)
            let allKnownTabs = browserManager.tabManager.allTabs()

            if let lId = leftId, let leftTab = allKnownTabs.first(where: { $0.id == lId }) {
                // Force-create/ensure loaded when visible in split
                let lWeb = webView(for: leftTab, windowId: windowState.id)
                let pane = makePaneContainer(frame: leftRect, isActive: (activeId == lId), accent: accent)
                containerView.addSubview(pane)
                lWeb.frame = pane.bounds
                lWeb.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
                lWeb.isHidden = false
                pane.addSubview(lWeb)
                
            }

            if let rId = rightId, let rightTab = allKnownTabs.first(where: { $0.id == rId }) {
                // Force-create/ensure loaded when visible in split
                let rWeb = webView(for: rightTab, windowId: windowState.id)
                let pane = makePaneContainer(frame: rightRect, isActive: (activeId == rId), accent: accent)
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

// MARK: - Split Controls Overlay
private struct SplitControlsOverlay: View {
    @Environment(BrowserManager.self) private var browserManager
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
