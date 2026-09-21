// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  SidebarPiPPanel.swift
//  Nook
//
//  Picture-in-picture pinned to the sidebar: when a playing video's tab is left, its live web
//  view moves into the sidebar directly above the media controls bar, and can be dragged out
//  into a floating panel and back. The page is not cloned: one live view changes superview.
//

import AppKit
import SwiftUI
import WebKit
import os
import NookDesign
import NookUI
import NookWeb

// MARK: - Controller

/// One per window. Owns which page is showing in the sidebar and the page-side isolation that
/// makes the video fill it.
@MainActor
@Observable
final class SidebarPiPController {
    private static let logger = Logger(subsystem: "com.gstudios.nook", category: "SidebarPiP")

    private(set) var isFloating = false
    /// While the float panel is being dragged the sidebar shows its drop zone.
    private(set) var isDragging = false
    private(set) var isOverDock = false
    @ObservationIgnored private var floatWindow: NSPanel?
    @ObservationIgnored weak var dockZoneView: NSView?
    @ObservationIgnored private static var lastFloatWidth: CGFloat = 420

    private(set) var itemID: UUID?
    private(set) var webView: WKWebView?
    private(set) var aspect: CGFloat = 16 / 9
    private(set) var session: PageSession?

    /// Where the video sits inside the page, in CSS points, relative to the viewport. The host
    /// crops and scales to exactly this rect.
    private(set) var videoRect: CGRect = .zero

    /// The page the sidebar media surface is about, kept after minimising so the bar describes
    /// the same video the panel was showing. The bar cannot re-derive this on its own: it finds
    /// a tab by "is playing", which skips a paused video and leaves the previous one on screen.
    private(set) var barSession: PageSession?


    var isShowing: Bool { itemID != nil }

    /// Feeds that autoplay whatever scrolls past: leaving one is not leaving a video.
    private static let excludedHosts = ["instagram.com"]

    static func allows(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        return !excludedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    var isDocked: Bool { isShowing && !isFloating }

    // MARK: - Enter

    /// Isolates the page's video and takes its live web view. `onFailure` runs when the page has
    /// no video to isolate, so the caller can fall back to system picture-in-picture.
    func enter(session: PageSession, webView: WKWebView, onFailure: @escaping () -> Void) {
        exit()
        // The view keeps the size it already had. Resizing it would reflow the page, which both
        // flashes white and invalidates the rect being measured in the same breath.
        webView.evaluateJavaScript(Self.measureScript) { [weak self] result, error in
            guard let self else { return }
            guard let rect = Self.rect(from: result), rect.width > 1, rect.height > 1 else {
                Self.logger.info("no measurable video: \(String(describing: error), privacy: .public)")
                onFailure()
                return
            }
            self.videoRect = rect
            self.aspect = max(rect.width / rect.height, 0.1)
            self.session = session
            self.barSession = session
            self.webView = webView
            self.itemID = session.itemID
        }
    }

    /// Re-measures after the page may have moved the video, e.g. a single-page navigation to the
    /// next video. Cheap enough to run whenever the host re-lays out.
    func remeasure() {
        guard let webView, itemID != nil else { return }
        webView.evaluateJavaScript(Self.measureScript) { [weak self] result, _ in
            guard let self, let rect = Self.rect(from: result), rect.width > 1, rect.height > 1,
                rect != self.videoRect
            else { return }
            Self.logger.notice("crop drifted: \(String(describing: self.videoRect), privacy: .public) -> \(String(describing: rect), privacy: .public)")
            self.videoRect = rect
            self.aspect = max(rect.width / rect.height, 0.1)
        }
    }

    private static func rect(from result: Any?) -> CGRect? {
        guard let info = result as? [String: Any], info["ok"] as? Bool == true,
            let x = info["x"] as? Double, let y = info["y"] as? Double,
            let width = info["w"] as? Double, let height = info["h"] as? Double
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Exit

    /// Nothing on the page was ever changed, so there is nothing to undo: the crop lived entirely
    /// in the host's layer. The compositor resizes the view when it takes it back.
    func exit() {
        guard itemID != nil else { return }
        closeFloat()
        clear()
    }

    private func clear() {
        isFloating = false
        itemID = nil
        webView = nil
        session = nil
        videoRect = .zero
    }

    /// Exits when the sidebar is showing `itemID`, and in either case stops the bar describing
    /// that page: reaching the tab again, or closing it, ends the sidebar's claim on it.
    func exitIfShowing(_ itemID: UUID) {
        if barSession?.itemID == itemID { barSession = nil }
        guard self.itemID == itemID else { return }
        exit()
    }

    // MARK: - Floating

    /// Called mid-drag from the sidebar: the panel appears under the pointer and keeps following.
    func popOut() {
        guard let webView, !isFloating else { return }
        let size = CGSize(width: Self.lastFloatWidth, height: Self.lastFloatWidth / aspect)
        let mouse = NSEvent.mouseLocation
        let origin = CGPoint(x: mouse.x - size.width / 2, y: mouse.y - size.height / 2)
        let panel = SidebarPiPFloatPanel(contentRect: CGRect(origin: origin, size: size))
        let root = FloatRootView(controller: self, frame: CGRect(origin: .zero, size: size))
        root.container.crop = videoRect
        panel.contentView = root
        // With the web view as first responder, YouTube's search box took focus within a second
        // of every pop-out and dropped its history over the video.
        panel.initialFirstResponder = root

        // Set before the move: the docked host must see it and leave the view alone.
        isFloating = true
        webView.removeFromSuperview()
        webView.autoresizingMask = []
        root.container.addSubview(webView)
        panel.orderFrontRegardless()
        floatWindow = panel
        DispatchQueue.main.async { self.trackDrag() }
    }

    /// Back into the sidebar: the docked host adopts the view once it is orphaned.
    func dock() {
        guard isFloating else { return }
        closeFloat()
        isFloating = false
    }

    private func closeFloat() {
        guard let floatWindow else { return }
        Self.lastFloatWidth = floatWindow.frame.width
        webView?.removeFromSuperview()
        floatWindow.close()
        self.floatWindow = nil
    }

    /// Moves the panel with the mouse until release, docking when released over the drop zone.
    func trackDrag() {
        guard let window = floatWindow, NSEvent.pressedMouseButtons & 1 == 1 else { return }
        let start = NSEvent.mouseLocation
        let grab = CGPoint(x: start.x - window.frame.minX, y: start.y - window.frame.minY)
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: NSEvent.foreverDuration,
                           mode: .eventTracking) { [weak self] event, stop in
            guard let self, let event, event.type == .leftMouseDragged else {
                stop.pointee = true
                guard let self else { return }
                let shouldDock = self.isOverDock
                self.isDragging = false
                self.isOverDock = false
                if shouldDock { self.dock() }
                return
            }
            let mouse = NSEvent.mouseLocation
            window.setFrameOrigin(CGPoint(x: mouse.x - grab.x, y: mouse.y - grab.y))
            if !self.isDragging { self.isDragging = true }
            let over = self.dockZone?.contains(mouse) == true
            if over != self.isOverDock { self.isOverDock = over }
        }
    }

    private var dockZone: CGRect? {
        guard let view = dockZoneView, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }

    /// Takes over another window's video, docked or floating, when this window gains focus.
    func adopt(from other: SidebarPiPController) {
        videoRect = other.videoRect
        aspect = other.aspect
        session = other.session
        barSession = other.barSession
        webView = other.webView
        floatWindow = other.floatWindow
        (floatWindow?.contentView as? FloatRootView)?.controller = self
        isFloating = other.isFloating
        itemID = other.itemID
        other.floatWindow = nil
        other.barSession = nil
        other.clear()
    }

    func togglePlay() {
        webView?.evaluateJavaScript(
            "(function(){const v=document.querySelector('video'); if(v){v.paused ? v.play() : v.pause();}})();")
    }

    // MARK: - Measurement

    /// Scrolls the video into view, then reports where it sits in the viewport so the host can
    /// crop to it. Nothing on the page is styled, hidden or moved: every previous
    /// attempt to isolate the video with CSS was defeated by the site's own stacking contexts.
    static let measureScript = """
    (function() {
        const video = document.querySelector('video');
        if (!video) return { ok: false };
        video.scrollIntoView({ block: 'center', inline: 'center' });
        const r = video.getBoundingClientRect();
        let x = r.x, y = r.y, w = r.width, h = r.height;
        // The element's box is the player's box: a video letterboxes its frame inside it, since
        // object-fit defaults to contain. Cropping to the element would keep those bars, so
        // narrow to the area the frame is actually painted in.
        const fit = getComputedStyle(video).objectFit || 'contain';
        if (video.videoWidth > 0 && video.videoHeight > 0
            && (fit === 'contain' || fit === 'scale-down' || fit === 'none')) {
            const scale = Math.min(w / video.videoWidth, h / video.videoHeight);
            const paintedWidth = video.videoWidth * scale;
            const paintedHeight = video.videoHeight * scale;
            x += (w - paintedWidth) / 2;
            y += (h - paintedHeight) / 2;
            w = paintedWidth;
            h = paintedHeight;
        }
        // A page reduced to its video must not hold text focus: a focused search box drops its
        // suggestions over the video.
        const a = document.activeElement;
        if (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.isContentEditable)) a.blur();
        return { ok: true, x: x, y: y, w: w, h: h };
    })();
    """

    /// Seeking has no equivalent on `MediaControlsManager`, whose next/previous change track.
    static func seekScript(_ seconds: Int) -> String {
        """
        (function() {
            const v = document.querySelector('video');
            if (!v) return false;
            v.currentTime = Math.max(0, Math.min(v.duration || Infinity, v.currentTime + (\(seconds))));
            return true;
        })();
        """
    }

    func seek(_ seconds: Int) {
        webView?.evaluateJavaScript(Self.seekScript(seconds))
    }
}

// MARK: - View

/// The video itself, sized to the real aspect ratio of the media so nothing letterboxes, sitting
/// directly above `MediaControlsView`.
struct SidebarPiPView: View {
    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) var windowState

    @State private var isHovering = false

    private var controller: SidebarPiPController? { windowState.sidebarPiPController }

    var body: some View {
        Group {
            if let controller, controller.isDocked, let webView = controller.webView {
                SidebarPiPWebViewHost(controller: controller, webView: webView, videoRect: controller.videoRect)
                    .aspectRatio(controller.aspect, contentMode: .fit)
                    .onAppear { controller.remeasure() }
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                    .nookElevation(.raised)
                    .overlay {
                        if isHovering { controls(controller) }
                    }
                    .onHoverTracking { hovering in
                        withAnimation(NookDesign.Motion.quick) { isHovering = hovering }
                        if hovering { controller.remeasure() }
                    }
                    .gesture(DragGesture(minimumDistance: NookDesign.Spacing.md)
                        .onChanged { _ in controller.popOut() })
                    .padding(.horizontal, 8)
                    .transition(.collapseIntoBar)
            } else if let controller, controller.isFloating, controller.isDragging {
                dropZone(controller)
            }
        }
        .animation(NookDesign.Motion.spring, value: controller?.itemID)
    }

    private func dropZone(_ controller: SidebarPiPController) -> some View {
        NookDesign.Radius.shape(NookDesign.Radius.md)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [NookDesign.Spacing.sm, NookDesign.Spacing.xs]))
            .overlay { Label("Dock video", systemImage: "pip.enter").font(NookDesign.Font.caption) }
            .foregroundStyle(controller.isOverDock ? .primary : .tertiary)
            .aspectRatio(controller.aspect, contentMode: .fit)
            .background(DockZoneReporter(controller: controller))
            .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func controls(_ controller: SidebarPiPController) -> some View {
        ZStack {
            Color.black.opacity(0.35)

            HStack(spacing: NookDesign.Spacing.xl) {
                Button("Rewind", systemImage: "gobackward.10") { controller.seek(-10) }
                Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    guard let session = controller.session else { return }
                    Task { _ = await mediaControls().playPause(tab: session) }
                }
                Button("Forward", systemImage: "goforward.10") { controller.seek(10) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NookIconButtonStyle(size: 24))
            .foregroundStyle(Color.white)

            // Sending the video back to its tab, still playing, is a minimise rather than a close.
            Button("Minimize", systemImage: "minus") {
                withAnimation(NookDesign.Motion.quick) { controller.exit() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NookIconButtonStyle(size: 20))
            .foregroundStyle(Color.white)
            .help("Return video to its tab")
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            .padding(NookDesign.Spacing.xs)
        }
        .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
        .transition(.opacity)
    }

    private var isPlaying: Bool {
        guard let session = controller?.session else { return false }
        return session.hasPlayingVideo || session.hasPlayingAudio
    }

    private func mediaControls() -> MediaControlsManager {
        let manager = MediaControlsManager(browserManager: browserManager, windowState: windowState)
        manager.windowRegistry = browserManager.windowRegistry
        return manager
    }
}

// MARK: - Web view host

/// Crops the web view down to the video's rectangle. The page lays out at a normal desktop size
/// and renders untouched; a layer transform on the clipping container scales the video's rect to
/// fill the sidebar slot. Nothing is injected, so no site's CSS can defeat it.
private struct SidebarPiPWebViewHost: NSViewRepresentable {
    let controller: SidebarPiPController
    let webView: WKWebView
    let videoRect: CGRect

    func makeNSView(context: Context) -> NSView {
        let container = CropContainerView(frame: .zero)
        container.wantsLayer = true
        container.layer?.masksToBounds = true
        container.layer?.backgroundColor = NSColor.black.cgColor
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        // A host on its way out still gets updates; it must not take back a view that floated.
        guard !controller.isFloating, controller.webView === webView else { return }
        if webView.superview !== container {
            webView.removeFromSuperview()
            // No autoresizing and no frame change: the page must keep the layout it was measured
            // in. Cropping needs no particular size, and reflowing costs a white repaint.
            webView.autoresizingMask = []
            container.addSubview(webView)
        }
        (container as? CropContainerView)?.crop = videoRect
        container.needsLayout = true
    }

    static func dismantleNSView(_ container: NSView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}

/// Flipped so its coordinates match CSS pixels, which is what the measured rect is in.
private final class CropContainerView: NSView {
    var crop: CGRect = .zero { didSet { needsLayout = true } }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    // The page gets no clicks or scrolls: a click would select its tab, a scroll would move
    // the video out from under the crop.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func layout() {
        super.layout()
        guard crop.width > 1, crop.height > 1, bounds.width > 1, let layer else { return }
        let scale = bounds.width / crop.width
        // Scale about the top-left, then bring the video's origin to the container's origin.
        layer.sublayerTransform = CATransform3DConcat(
            CATransform3DMakeTranslation(-crop.minX, -crop.minY, 0),
            CATransform3DMakeScale(scale, scale, 1))
    }
}

/// Tells the controller where the sidebar's drop zone is on screen.
private struct DockZoneReporter: NSViewRepresentable {
    let controller: SidebarPiPController

    func makeNSView(context: Context) -> NSView { NSView() }
    func updateNSView(_ view: NSView, context: Context) { controller.dockZoneView = view }
}

// MARK: - Float panel

/// Above every app and on every space, fullscreen ones included, without taking focus.
private final class SidebarPiPFloatPanel: NSPanel {
    init(contentRect: CGRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel, .resizable],
                   backing: .buffered, defer: false)
        isReleasedWhenClosed = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        contentAspectRatio = contentRect.size
        contentMinSize = CGSize(width: 240, height: 240 * contentRect.height / contentRect.width)
    }
}

/// The panel's content: the cropped video, hover controls, and the mouse-down that starts a drag.
private final class FloatRootView: NSView {
    weak var controller: SidebarPiPController? { didSet { trackPlayState() } }
    let container = CropContainerView(frame: .zero)
    private let controls = NSView()
    private var playButton: NSButton?
    /// Same target as the media bar's buttons.
    private static let buttonSize: CGFloat = 24

    init(controller: SidebarPiPController, frame: CGRect) {
        self.controller = controller
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        layer?.cornerRadius = NookDesign.Radius.md
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true

        container.wantsLayer = true
        container.layer?.masksToBounds = true
        controls.wantsLayer = true
        controls.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.35).cgColor
        controls.isHidden = true
        for view in [container, controls] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }

        let play = button("pause.fill", "Play or Pause") { [weak self] in self?.controller?.togglePlay() }
        playButton = play
        let transport = NSStackView(views: [
            button("gobackward.10", "Rewind") { [weak self] in self?.controller?.seek(-10) },
            play,
            button("goforward.10", "Forward") { [weak self] in self?.controller?.seek(10) },
        ])
        let corner = NSStackView(views: [
            button("pip.enter", "Return to sidebar") { [weak self] in self?.controller?.dock() },
            button("xmark", "Return video to its tab") { [weak self] in self?.controller?.exit() },
        ])
        transport.spacing = NookDesign.Spacing.xl
        corner.spacing = NookDesign.Spacing.sm
        for stack in [transport, corner] {
            stack.translatesAutoresizingMaskIntoConstraints = false
            controls.addSubview(stack)
        }
        NSLayoutConstraint.activate([
            transport.centerXAnchor.constraint(equalTo: controls.centerXAnchor),
            transport.centerYAnchor.constraint(equalTo: controls.centerYAnchor),
            corner.topAnchor.constraint(equalTo: controls.topAnchor, constant: NookDesign.Spacing.xs),
            corner.trailingAnchor.constraint(equalTo: controls.trailingAnchor, constant: -NookDesign.Spacing.xs),
        ])
        trackPlayState()
    }

    /// Re-arms itself on each change, so the icon follows the session without a timer.
    private func trackPlayState() {
        let playing = withObservationTracking {
            controller?.session?.hasPlayingVideo == true
        } onChange: { [weak self] in
            DispatchQueue.main.async { self?.trackPlayState() }
        }
        playButton?.image = NSImage(systemSymbolName: playing ? "pause.fill" : "play.fill",
                                    accessibilityDescription: playing ? "Pause" : "Play")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func button(_ symbol: String, _ label: String, action: @escaping () -> Void) -> NSButton {
        let button = ClosureButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label)!,
                                   target: nil, action: nil)
        button.handler = action
        button.target = button
        button.action = #selector(ClosureButton.fire)
        button.isBordered = false
        button.contentTintColor = .white
        button.symbolConfiguration = .init(pointSize: 16, weight: .medium)
        button.toolTip = label
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: Self.buttonSize),
            button.heightAnchor.constraint(equalToConstant: Self.buttonSize),
        ])
        return button
    }

    override var acceptsFirstResponder: Bool { true }

    // The panel never becomes key, so every click is a first click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { controller?.dock() } else { controller?.trackDrag() }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        controls.isHidden = false
        controller?.remeasure()
    }

    override func mouseExited(with event: NSEvent) { controls.isHidden = true }
}

private final class ClosureButton: NSButton {
    var handler: (() -> Void)?
    @objc func fire() { handler?() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

// MARK: - Transition

private struct CollapseModifier: ViewModifier {
    let heightScale: CGFloat

    func body(content: Content) -> some View {
        // Height only, at full width, anchored to the bottom: the video flattens down into the
        // bar's shape rather than shrinking toward a point in the middle. scaleEffect is a
        // render transform, so the web view is never re-laid out mid-animation.
        content.scaleEffect(x: 1, y: heightScale, anchor: .bottom)
    }
}

extension AnyTransition {
    /// The video collapsing into the media bar that takes its place.
    static var collapseIntoBar: AnyTransition {
        .modifier(active: CollapseModifier(heightScale: 0.04),
                  identity: CollapseModifier(heightScale: 1))
    }
}
