// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  SidebarPiPPanel.swift
//  Nook
//
//  Picture-in-picture pinned to the sidebar: when a playing video's tab is left, its live web
//  view moves into the sidebar directly above the media controls bar. The page is not cloned,
//  and the view never leaves the window: the compositor hands it over and takes it back, which
//  is the same move it makes on every tab switch.
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

    // MARK: - Measurement

    /// Read-only. Scrolls the video into view, then reports where it sits in the viewport so the
    /// host can crop to it. Nothing on the page is styled, hidden or moved: every previous
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
            if let controller, controller.isShowing, let webView = controller.webView {
                SidebarPiPWebViewHost(webView: webView, videoRect: controller.videoRect)
                    .aspectRatio(controller.aspect, contentMode: .fit)
                    .onAppear { controller.remeasure() }
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                    .nookElevation(.raised)
                    .overlay {
                        if isHovering { controls(controller) }
                    }
                    .onHoverTracking { hovering in
                        withAnimation(NookDesign.Motion.quick) { isHovering = hovering }
                    }
                    .padding(.horizontal, 8)
                    .transition(.collapseIntoBar)
            }
        }
        .animation(NookDesign.Motion.spring, value: controller?.itemID)
    }

    @ViewBuilder
    private func controls(_ controller: SidebarPiPController) -> some View {
        ZStack {
            Color.black.opacity(0.35)

            HStack(spacing: NookDesign.Spacing.sm) {
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
    var crop: CGRect = .zero

    override var isFlipped: Bool { true }

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
