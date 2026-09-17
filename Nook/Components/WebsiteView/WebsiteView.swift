//
//  WebsiteView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import WebKit
import AppKit
import NookDesign
import NookWeb
import NookUI

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
                .font(NookDesign.Font.secondary)
                .foregroundColor(textColor)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .padding(.vertical, 4)
                .background(.ultraThickMaterial)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(borderColor, lineWidth: 1)
                )
                .opacity(shouldShow ? 1 : 0)
                .animation(NookDesign.Motion.standard, value: shouldShow)
                .onChange(of: hoveredLink) {_,  newLink in
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
                .onChange(of: hoveredLink) {_,  newLink in
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
    
    private let dragCoordinateSpace = "splitPreview"

    private var cornerRadius: CGFloat {
        return NookDesign.Radius.md
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
            return AnyShape(NookDesign.Radius.shape(cornerRadius))
        }
    }

    var body: some View {
        // Read observable properties directly so SwiftUI tracks changes
        let _ = windowState.compositorVersion
        ZStack() {
            Group {
                if browserManager.tabs.selectedSession(in: windowState) != nil {
                    GeometryReader { proxy in
                        TabCompositorWrapper(
                            browserManager: browserManager,
                            hoveredLink: $hoveredLink,
                            isCommandPressed: $isCommandPressed,
                            splitFraction: splitManager.dividerFraction(for: windowState.id),
                            isSplit: splitManager.isSplit(for: windowState.id),
                            leftId: splitManager.leftTabId(for: windowState.id),
                            rightId: splitManager.rightTabId(for: windowState.id),
                            windowState: windowState,
                            compositorVersion: windowState.compositorVersion,
                            selectedItemID: windowState.selectedItemID
                        )
                        .coordinateSpace(name: dragCoordinateSpace)
                        .background(shouldShowSplit ? Color.clear : Color(nsColor: .windowBackgroundColor))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipShape(webViewClipShape)
                        // compositingGroup creates a rendering barrier so the shadow is
                        // computed from a flattened bitmap rather than recompositing the
                        // WKWebView's live GPU video layer, which caused black flashes.
                        .compositingGroup()
                        .nookElevation(.raised)
                        // Critical: Use allowsHitTesting to prevent SwiftUI from intercepting mouse events
                        // This allows right-clicks to pass through to the underlying NSView (WKWebView)
                        .allowsHitTesting(!browserManager.dialogManager.isVisible)
                        .contentShape(Rectangle())
                    }
                    // Removed SwiftUI contextMenu - it intercepts ALL right-clicks
                    // WKWebView's willOpenMenu will handle context menus for images
                } else {
                    EmptyWebsiteView()
                }
            }
            VStack {
                Spacer()
                if nookSettings.showLinkStatusBar {
                    HStack {
                        LinkStatusBar(
                            hoveredLink: hoveredLink,
                            isCommandPressed: isCommandPressed,
                            accentColor: browserManager.gradientColorManager.accentColor
                        )
                        .padding(10)
                        Spacer()
                    }
                }
                
            }
            
            // Split preview overlay - shows cards during drag operations
            if splitManager.getSplitState(for: windowState.id).isPreviewActive {
                SplitPreviewOverlay()
                    .environmentObject(splitManager)
                    .environmentObject(browserManager)
                    .environment(windowState)
                    .coordinateSpace(name: dragCoordinateSpace)
                    .animation(
                        NookDesign.Motion.spring,
                        value: splitManager.getSplitState(for: windowState.id).isPreviewActive
                    )
            }
            
        }
    }

}

// MARK: - Split Preview Overlay
private struct SplitPreviewOverlay: View {
    @EnvironmentObject var splitManager: SplitViewManager
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    
    var body: some View {
        GeometryReader { geometry in
            let splitState = splitManager.getSplitState(for: windowState.id)
            let previewSide = splitState.previewSide
            let dragLocation = splitState.dragLocation
            let cardPadding: CGFloat = 20
            let cardWidth: CGFloat = 315
            let cardHeight: CGFloat = 522
            
            HStack(spacing: 0) {
                // Left card - vertically centered with magnetic effect
                VStack {
                    Spacer()
                    MagneticCardView(
                        side: .left,
                        icon: "rectangle.lefthalf.filled",
                        text: "Add left split",
                        isTabHovered: previewSide == .left,
                        dragLocation: dragLocation,
                        cardFrame: CGRect(
                            x: cardPadding,
                            y: (geometry.size.height - cardHeight) / 2,
                            width: cardWidth,
                            height: cardHeight
                        ),
                        geometry: geometry,
                        accentColor: browserManager.gradientColorManager.accentColor
                    )
                    Spacer()
                }
                .padding(.leading, cardPadding)
                
                Spacer()
                
                // Right card - vertically centered with magnetic effect
                VStack {
                    Spacer()
                    MagneticCardView(
                        side: .right,
                        icon: "rectangle.righthalf.filled",
                        text: "Add right split",
                        isTabHovered: previewSide == .right,
                        dragLocation: dragLocation,
                        cardFrame: CGRect(
                            x: geometry.size.width - cardPadding - cardWidth,
                            y: (geometry.size.height - cardHeight) / 2,
                            width: cardWidth,
                            height: cardHeight
                        ),
                        geometry: geometry,
                        accentColor: browserManager.gradientColorManager.accentColor
                    )
                    Spacer()
                }
                .padding(.trailing, cardPadding)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false) // Don't intercept mouse events - let drag handling work
        }
    }
}

// MARK: - Magnetic Card View
private struct MagneticCardView: View {
    let side: SplitViewManager.Side
    let icon: String
    let text: String
    let isTabHovered: Bool
    let dragLocation: CGPoint?
    let cardFrame: CGRect
    let geometry: GeometryProxy
    let accentColor: Color
    
    @EnvironmentObject var splitManager: SplitViewManager
    @Environment(BrowserWindowState.self) private var windowState
    
    @State private var offset: CGSize = .zero
    @State private var isMagneticallyActive: Bool = false
    
    // Computed property: card is hovered if previewSide matches OR if magnetically active
    private var cardIsHovered: Bool {
        let splitState = splitManager.getSplitState(for: windowState.id)
        return splitState.previewSide == side || isMagneticallyActive
    }
    
    var body: some View {
        SplitCardView(
            icon: icon,
            text: text,
            isTabHovered: cardIsHovered,
            accentColor: accentColor
        )
        .offset(offset)
        .scaleEffect(1.0) // Cards appear at full size
        .animation(
            NookDesign.Motion.spring,
            value: offset
        )
        .transition(.asymmetric(
            insertion: .scale(scale: 0.7, anchor: .center),
            removal: .scale(scale: 0.5, anchor: .center).combined(with: .opacity)
        ))
        .onChange(of: dragLocation) { _, location in
            guard let location = location else {
                if isMagneticallyActive {
                    isMagneticallyActive = false
                    offset = .zero
                    // Clear preview side when drag ends
                    splitManager.updatePreviewSide(nil, for: windowState.id)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                }
                return
            }
            
            // dragLocation is in NSView coordinates (relative to container view, bottom-left origin)
            // cardFrame is in GeometryReader coordinates (top-left origin)
            // Convert NSView Y coordinate to SwiftUI coordinate space
            let geometryHeight = geometry.size.height
            let convertedLocation = CGPoint(x: location.x, y: geometryHeight - location.y)
            
            let cardCenter = CGPoint(x: cardFrame.midX, y: cardFrame.midY)
            
            // Check if drag is within card bounds (with some margin for magnetic effect)
            let margin: CGFloat = 50
            let expandedFrame = cardFrame.insetBy(dx: -margin, dy: -margin)
            
            if expandedFrame.contains(convertedLocation) {
                // Calculate magnetic offset (45% of distance to center)
                let dx = (convertedLocation.x - cardCenter.x) * 0.45
                let dy = (convertedLocation.y - cardCenter.y) * 0.45
                offset = CGSize(width: dx, height: dy)
                
                if !isMagneticallyActive {
                    isMagneticallyActive = true
                    // Update preview side to indicate this card is hovered
                    splitManager.updatePreviewSide(side, for: windowState.id)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                }
            } else {
                if isMagneticallyActive {
                    isMagneticallyActive = false
                    offset = .zero
                    // Clear preview side when leaving card
                    splitManager.updatePreviewSide(nil, for: windowState.id)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
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
    var compositorVersion: Int
    var selectedItemID: UUID?

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
        // Use windowBackgroundColor instead of clear to prevent black flashes during
        // video playback when the WKWebView's GPU compositing layer briefly shows through.
        containerView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
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
        // MEMORY LEAK FIX: Capture coord weakly to break potential retain cycle
        // Coordinator → frameObserver token → closure → Coordinator
        coord.frameObserver = NotificationCenter.default.addObserver(
            forName: NSView.frameDidChangeNotification,
            object: containerView,
            queue: .main
        ) { [weak containerView, weak coord] _ in
            guard let cv = containerView else { return }
            // Only rebuild when bounds size actually changed — spurious frame
            // notifications (e.g. from SwiftUI layout passes) should not trigger
            // a compositor rebuild that could interrupt video playback.
            let newSize = cv.bounds.size
            guard coord?.lastSize != newSize else { return }
            updateCompositor(cv)
            coord?.lastSize = newSize
        }

        // Set up link hover callbacks for the selected page
        if let session = browserManager.tabs.selectedSession(in: windowState) {
            setupHoverCallbacks(for: session)
        }
        
        return containerView
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Only rebuild compositor when meaningful inputs change
        let size = nsView.bounds.size
        let currentId = windowState.selectedItemID
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
            let previousCurrentId = context.coordinator.lastCurrentId
            updateCompositor(nsView)
            context.coordinator.lastIsSplit = isSplit
            context.coordinator.lastLeftId = leftId
            context.coordinator.lastRightId = rightId
            context.coordinator.lastCurrentId = currentId
            context.coordinator.lastFraction = splitFraction
            context.coordinator.lastSize = size
            context.coordinator.lastVersion = compositorVersion

            // Restore focus when tab changed (webview is now in hierarchy)
            if previousCurrentId != currentId {
                DispatchQueue.main.async {
                    guard let window = nsView.window else { return }
                    for subview in nsView.subviews.reversed() {
                        if subview is SplitDropCaptureView { continue }
                        if let webView = subview as? WKWebView, !webView.isHidden {
                            window.makeFirstResponder(webView)
                            return
                        }
                        // Check pane containers (split view)
                        for child in subview.subviews {
                            if let webView = child as? WKWebView, !child.isHidden {
                                window.makeFirstResponder(webView)
                                return
                            }
                        }
                    }
                }
            }
        }
        
        // Mark the selected page as accessed (resets its unload timer)
        if let session = browserManager.tabs.selectedSession(in: windowState) {
            browserManager.compositorManager.markTabAccessed(session.itemID)
            setupHoverCallbacks(for: session)
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.browserManager?.webViewCoordinator?.removeCompositorContainerView(for: coordinator.windowState.id)
    }

    private func updateCompositor(_ containerView: NSView) {
        // Non-destructive compositor: avoid removing/re-adding WKWebViews that are
        // already correctly positioned. Removing a WKWebView from its superview
        // disconnects its GPU video surface, causing black flashes during playback.

        let tabs = browserManager.tabs
        let selected = tabs.selectedSession(in: windowState)
        let split = browserManager.splitManager
        let splitState = split.getSplitState(for: windowState.id)

        // Identify overlay (always preserved)
        let overlay = containerView.subviews.compactMap { $0 as? SplitDropCaptureView }.first
        // Content subviews = everything except the overlay
        let contentSubviews = containerView.subviews.filter { !($0 is SplitDropCaptureView) }

        if splitState.isPreviewActive {
            // Preview mode: show current tab at full size
            if let session = selected, !session.isUnloaded {
                setSingleWebView(pageView(for: session, reusing: contentSubviews), in: containerView, replacing: contentSubviews)
            } else {
                removeContentViews(contentSubviews)
            }
        } else {
            let currentId = selected?.itemID
            let leftId = split.leftTabId(for: windowState.id)
            let rightId = split.rightTabId(for: windowState.id)
            let isCurrentPane = (currentId != nil) && (currentId == leftId || currentId == rightId)

            if split.isSplit(for: windowState.id) && isCurrentPane {
                // Split view — uses pane containers so we do a full rebuild here
                // (pane containers have dynamic styling that must be recreated)
                removeContentViews(contentSubviews)

                // Auto-heal if one side is missing (tab closed etc.)
                let leftResolved = leftId.flatMap { tabs.item($0) }
                let rightResolved = rightId.flatMap { tabs.item($0) }
                if leftResolved == nil && rightResolved == nil {
                    browserManager.splitManager.exitSplit(keep: .left, for: windowState.id)
                } else if leftResolved == nil, let _ = rightResolved {
                    browserManager.splitManager.exitSplit(keep: .right, for: windowState.id)
                } else if rightResolved == nil, let _ = leftResolved {
                    browserManager.splitManager.exitSplit(keep: .left, for: windowState.id)
                }

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

                let activeSide = split.activeSide(for: windowState.id)
                let accent = browserManager.gradientColorManager.accentNSColor

                if let lId = leftId, let leftSession = tabs.ensureSession(for: lId) {
                    let lWeb = pageView(for: leftSession, reusing: [])
                    let pane = makePaneContainer(frame: leftRect, isActive: (activeSide == .left), accent: accent, side: .left)
                    containerView.addSubview(pane)
                    lWeb.frame = pane.bounds
                    lWeb.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
                    lWeb.isHidden = false
                    pane.addSubview(lWeb)
                }

                if let rId = rightId, let rightSession = tabs.ensureSession(for: rId) {
                    let rWeb = pageView(for: rightSession, reusing: [])
                    let pane = makePaneContainer(frame: rightRect, isActive: (activeSide == .right), accent: accent, side: .right)
                    containerView.addSubview(pane)
                    rWeb.frame = pane.bounds
                    rWeb.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
                    rWeb.isHidden = false
                    pane.addSubview(rWeb)
                }
            } else {
                // Single tab (most common path during video playback)
                if let session = selected, !session.isUnloaded {
                    setSingleWebView(pageView(for: session, reusing: contentSubviews), in: containerView, replacing: contentSubviews)
                } else {
                    removeContentViews(contentSubviews)
                }
            }
        }

        // Ensure overlay is on top
        if let overlay = overlay {
            overlay.frame = containerView.bounds
            overlay.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
            overlay.browserManager = browserManager
            overlay.splitManager = browserManager.splitManager
            overlay.windowId = windowState.id
            // Re-order to top if needed
            if overlay !== containerView.subviews.last {
                overlay.removeFromSuperview()
                containerView.addSubview(overlay)
            }
            overlay.layer?.zPosition = 10_000
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

    /// Sets a single webview as the only content in the container without removing it
    /// if it's already the sole content subview. This prevents GPU video surface
    /// disconnection that causes black flashes during playback.
    private func setSingleWebView(_ desired: NSView, in containerView: NSView, replacing contentSubviews: [NSView]) {
        let isAlreadyCorrect = contentSubviews.count == 1 && contentSubviews.first === desired

        if !isAlreadyCorrect {
            // Remove stale content views
            for subview in contentSubviews where subview !== desired {
                subview.removeFromSuperview()
            }
            // Add the desired webview if not already a direct child
            if desired.superview !== containerView {
                containerView.addSubview(desired)
            }
        }

        desired.frame = containerView.bounds
        desired.autoresizingMask = [NSView.AutoresizingMask.width, NSView.AutoresizingMask.height]
        desired.isHidden = false
    }

    /// Removes all non-overlay content subviews
    private func removeContentViews(_ contentSubviews: [NSView]) {
        for subview in contentSubviews {
            subview.removeFromSuperview()
        }
    }

    private func makePaneContainer(frame: NSRect, isActive: Bool, accent: NSColor, side: SplitViewManager.Side) -> NSView {
        let cornerRadius: CGFloat = NookDesign.Radius.md
        
        let v = NSView(frame: frame)
        v.wantsLayer = true
        
        if let layer = v.layer {
            layer.backgroundColor = NSColor.windowBackgroundColor.cgColor
            
            // Create mask layer for uneven rounded corners
            let maskLayer = CAShapeLayer()
            let maskPath = createUnevenRoundedRectPath(
                rect: v.bounds,
                topLeadingRadius: side == .left ? 0 : cornerRadius,
                bottomLeadingRadius: cornerRadius,
                bottomTrailingRadius: cornerRadius,
                topTrailingRadius: side == .right ? 0 : cornerRadius
            )
            maskLayer.path = maskPath
            layer.mask = maskLayer
            
            // Add border layer
            if isActive {
                let borderLayer = CAShapeLayer()
                borderLayer.path = maskPath
                borderLayer.strokeColor = accent.withAlphaComponent(0.9).cgColor
                borderLayer.fillColor = NSColor.clear.cgColor
                borderLayer.lineWidth = 1.0
                layer.addSublayer(borderLayer)
            }
        }
        
        v.autoresizingMask = [.width, .height]
        return v
    }

    private func createUnevenRoundedRectPath(
        rect: CGRect,
        topLeadingRadius: CGFloat,
        bottomLeadingRadius: CGFloat,
        bottomTrailingRadius: CGFloat,
        topTrailingRadius: CGFloat
    ) -> CGPath {
        let path = CGMutablePath()
        
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY
        
        // Start from top-left, move clockwise
        path.move(to: CGPoint(x: minX + topLeadingRadius, y: maxY))
        
        // Top edge to top-right corner
        path.addLine(to: CGPoint(x: maxX - topTrailingRadius, y: maxY))
        if topTrailingRadius > 0 {
            path.addArc(tangent1End: CGPoint(x: maxX, y: maxY), tangent2End: CGPoint(x: maxX, y: maxY - topTrailingRadius), radius: topTrailingRadius)
        }
        
        // Right edge to bottom-right corner
        path.addLine(to: CGPoint(x: maxX, y: minY + bottomTrailingRadius))
        if bottomTrailingRadius > 0 {
            path.addArc(tangent1End: CGPoint(x: maxX, y: minY), tangent2End: CGPoint(x: maxX - bottomTrailingRadius, y: minY), radius: bottomTrailingRadius)
        }
        
        // Bottom edge to bottom-left corner
        path.addLine(to: CGPoint(x: minX + bottomLeadingRadius, y: minY))
        if bottomLeadingRadius > 0 {
            path.addArc(tangent1End: CGPoint(x: minX, y: minY), tangent2End: CGPoint(x: minX, y: minY + bottomLeadingRadius), radius: bottomLeadingRadius)
        }
        
        // Left edge to top-left corner
        path.addLine(to: CGPoint(x: minX, y: maxY - topLeadingRadius))
        if topLeadingRadius > 0 {
            path.addArc(tangent1End: CGPoint(x: minX, y: maxY), tangent2End: CGPoint(x: minX + topLeadingRadius, y: maxY), radius: topLeadingRadius)
        }
        
        path.closeSubpath()
        return path
    }

    private func setupHoverCallbacks(for session: PageSession) {
        // Set up link hover callback
        session.onLinkHover = { [self] href in
            DispatchQueue.main.async {
                self.hoveredLink = href
                if let href = href {
                }
            }
        }
        
        // Set up command hover callback
        session.onCommandHover = { [self] href in
            DispatchQueue.main.async {
                self.isCommandPressed = href != nil
            }
        }
    }

    /// The session's live view when this window holds it, else the "Open in another window"
    /// placeholder (reused from `existing` when it already stands in for this item).
    private func pageView(for session: PageSession, reusing existing: [NSView]) -> NSView {
        let tabs = browserManager.tabs
        guard tabs.isPageShownElsewhere(session.itemID, from: windowState) else {
            return webView(for: session, windowId: windowState.id)
        }
        if let host = existing.compactMap({ $0 as? PageElsewhereHostView }).first(where: { $0.itemID == session.itemID }) {
            return host
        }
        let itemID = session.itemID
        let window = windowState
        return PageElsewhereHostView(itemID: itemID, rootView: PageElsewhereView(
            title: session.title,
            onShowHere: { tabs.takeControl(itemID, in: window) },
            onGoToWindow: { tabs.showOwnerWindow(of: itemID) }
        ))
    }

    private func webView(for session: PageSession, windowId: UUID) -> WKWebView {
        // One view per window: the session's primary in the first window, clones elsewhere.
        guard let coordinator = browserManager.webViewCoordinator else { return session.activeWebView }
        return coordinator.createWebView(for: session, in: windowId)
    }


}

// MARK: - WebsiteView Extensions

private extension WebsiteView {
    var shouldShowSplit: Bool {
        guard splitManager.isSplit(for: windowState.id) else { return false }
        guard let current = windowState.selectedItemID else { return false }
        return current == splitManager.leftTabId(for: windowState.id) || current == splitManager.rightTabId(for: windowState.id)
    }
}

// MARK: - Container View that forwards right-clicks to webviews

private class ContainerView: NSView {
    // Don't intercept events - let them pass through to webviews
    override var acceptsFirstResponder: Bool { false }

    override func resetCursorRects() {
        // Empty: prevents NSHostingView and other ancestors from registering
        // arrow cursor rects over the webview. WKWebView uses NSCursor.set()
        // internally, which works correctly when cursor rects don't override it.
    }

    // Forward right-clicks to the webview below so context menus work
    override func rightMouseDown(with event: NSEvent) {
        // Find the webview at this point and forward the event
        let point = convert(event.locationInWindow, from: nil)
        // Use hitTest to find the actual view at this point (will skip overlay if hitTest returns nil)
        if let hitView = hitTest(point) {
            if let webView = hitView as? WKWebView {
                webView.rightMouseDown(with: event)
                return
            }
            // Check if hitView contains a webview
            if let webView = findWebView(in: hitView, at: point) {
                webView.rightMouseDown(with: event)
                return
            }
        }
        // Fallback: search all subviews
        for subview in subviews.reversed() {
            if let webView = findWebView(in: subview, at: point) {
                webView.rightMouseDown(with: event)
                return
            }
        }
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
