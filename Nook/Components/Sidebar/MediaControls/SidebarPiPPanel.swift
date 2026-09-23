// Licensed under GPL-3.0. See LICENSE.
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
final class SidebarPiPController: PictureInPictureHolder {
    private static let logger = Logger(subsystem: "com.gstudios.nook", category: "SidebarPiP")
    /// Every PiP script runs here, out of the page's reach.
    static let world = WKContentWorld.world(name: "NookPiP")

    private(set) var isFloating = false
    /// While the float panel is being dragged the sidebar shows its drop zone.
    private(set) var isDragging = false
    private(set) var isOverDock = false
    @ObservationIgnored private var floatWindow: NSPanel?
    @ObservationIgnored weak var dockZoneView: NSView?
    @ObservationIgnored private static var lastFloatWidth: CGFloat = 420
    /// Bumped on every enter and exit, so a late script reply for an earlier video is dropped.
    @ObservationIgnored private var generation = 0
    /// Only the newest `next()` wait may act.
    @ObservationIgnored private var followToken = 0

    @ObservationIgnored private weak var windowState: BrowserWindowState?

    private(set) var itemID: UUID?
    private(set) var webView: WKWebView?
    private(set) var session: PageSession?
    /// False until the isolated video has been presented, so no frame from before is ever shown.
    private(set) var isReady = false

    /// Where the video is painted, in view points relative to the web view. The host crops and
    /// scales to exactly this rect.
    private(set) var videoRect: CGRect = .zero

    /// The page the sidebar media surface is about, kept after minimising so the bar describes
    /// the same video the panel was showing. The bar cannot re-derive this on its own: it finds
    /// a tab by "is playing", which skips a paused video and leaves the previous one on screen.
    private(set) var barSession: PageSession?

    var isShowing: Bool { itemID != nil }
    var isDocked: Bool { isShowing && !isFloating }
    var pictureInPictureItemID: UUID? { itemID }
    var aspect: CGFloat { videoRect.height > 1 ? max(videoRect.width / videoRect.height, 0.1) : 16 / 9 }

    init(windowState: BrowserWindowState) {
        self.windowState = windowState
    }

    /// Feeds play whatever scrolls past. Facebook serves long videos under /reel/ too, so its
    /// reels are told apart by the page script's portrait check.
    static func allowsAutomatic(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return true }
        func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
        if on("instagram.com") || on("tiktok.com") { return false }
        return !(on("youtube.com") && url.path.lowercased().hasPrefix("/shorts"))
    }

    // MARK: - Enter

    /// Moves the live view into the sidebar and isolates its video; `automatic` refuses paused,
    /// muted, looping or portrait video. `onFailure` lets the caller fall back to system PiP.
    func enter(session: PageSession, webView: WKWebView, automatic: Bool, onFailure: @escaping () -> Void) {
        // Only Nook's own view class stops the pointer and restores the page on the way back.
        guard webView is FocusableWKWebView else { return onFailure() }
        exit()
        generation += 1
        // Published before the compositor's pass, so the view moves between containers in one
        // update and the page never goes hidden. The slot stays clear until the video is ready.
        withAnimation(NookDesign.Motion.spring) {
            self.session = session
            barSession = session
            self.webView = webView
            itemID = session.itemID
        }
        if webView.window?.firstResponder === webView { webView.window?.makeFirstResponder(nil) }
        isolate(webView, automatic: automatic, onFailure: onFailure)
        followNavigation(of: session, generation: generation)
    }

    private func isolate(_ webView: WKWebView, automatic: Bool, onFailure: @escaping () -> Void) {
        let generation = generation
        // Before the script, so a reply dropped by a quick return still leaves a restore behind.
        (webView as? FocusableWKWebView)?.isPictureInPictureIsolated = true
        webView.callAsyncJavaScript(
            Self.pageScript + "return __nookPiP.isolate(zoom, automatic);",
            arguments: ["zoom": Double(webView.pageZoom), "automatic": automatic],
            in: nil, in: Self.world
        ) { [weak self] result in
            guard let self, self.generation == generation, self.webView === webView else { return }
            let info = (try? result.get()) as? [String: Any]
            guard let rect = Self.rect(from: info) else {
                Self.logger.notice("no video to isolate: \(String(describing: info), privacy: .public)")
                self.exit()
                if info?["skip"] as? Bool != true { onFailure() }
                return
            }
            self.setCrop(rect)
            guard !self.isReady else { return self.follow(webView) }
            Self.afterNextPresentation(of: webView) { [weak self] in
                guard let self, self.generation == generation else { return }
                withAnimation(NookDesign.Motion.spring) { self.isReady = true }
                self.follow(webView)
            }
        }
    }

    /// Keeps the crop on the video as the page changes: the next video, an ad, a resize.
    private func follow(_ webView: WKWebView) {
        followToken += 1
        let token = followToken, generation = generation
        webView.callAsyncJavaScript("return await __nookPiP.next();", arguments: [:], in: nil, in: Self.world) {
            [weak self] result in
            guard let self, self.generation == generation, self.followToken == token, self.webView === webView
            else { return }
            let info = (try? result.get()) as? [String: Any]
            if let rect = Self.rect(from: info) {
                self.setCrop(rect)
                self.follow(webView)
            } else if info?["ended"] as? Bool != true {
                // The document changed or the video left it: pick again, or end.
                self.refresh()
            }
        }
    }

    /// A navigation, even a single-page one to the next video, can replace the player.
    private func followNavigation(of session: PageSession, generation: Int) {
        withObservationTracking { _ = session.url } onChange: { [weak self, weak session] in
            DispatchQueue.main.async {
                guard let self, let session, self.generation == generation else { return }
                self.refresh()
                self.followNavigation(of: session, generation: generation)
            }
        }
    }

    private func refresh() {
        guard let webView else { return }
        isolate(webView, automatic: false) {}
    }

    private func setCrop(_ rect: CGRect) {
        guard rect != videoRect else { return }
        videoRect = rect
        guard let floatWindow, let root = floatWindow.contentView as? FloatRootView else { return }
        root.container.crop = rect
        floatWindow.contentAspectRatio = rect.size
        var frame = floatWindow.frame
        frame.size.height = frame.width / aspect
        floatWindow.setFrame(frame, display: true)
    }

    private static func rect(from info: [String: Any]?) -> CGRect? {
        guard let info, info["ok"] as? Bool == true,
            let x = info["x"] as? Double, let y = info["y"] as? Double,
            let width = info["w"] as? Double, let height = info["h"] as? Double,
            width > 1, height > 1
        else { return nil }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    /// Runs `body` once WebKit has put the page's latest frame on screen, or after a short wait
    /// for a page that is not presenting (an occluded window).
    private static func afterNextPresentation(of webView: WKWebView, _ body: @escaping () -> Void) {
        var done = false
        let once = { if !done { done = true; body() } }
        let selector = NSSelectorFromString("_doAfterNextPresentationUpdate:")
        if webView.responds(to: selector) {
            typealias Call = @convention(c) (AnyObject, Selector, @escaping @convention(block) () -> Void) -> Void
            unsafeBitCast(webView.method(for: selector), to: Call.self)(webView, selector) { once() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { once() }
    }

    // MARK: - Exit

    /// The page is restored when its view next lands outside a crop, in its tab or a split pane;
    /// minimising leaves it isolated off screen until then.
    func exit() {
        guard itemID != nil else { return }
        closeFloat()
        clear()
    }

    private func clear() {
        generation += 1
        isFloating = false
        isReady = false
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
        guard let webView, isReady, !isFloating else { return }
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
        webView.autoresizingMask = []
        root.container.addSubview(webView)
        panel.orderFrontRegardless()
        floatWindow = panel
        DispatchQueue.main.async { self.trackDrag() }
    }

    /// Back into the sidebar: the docked host adopts the view once it is orphaned. A hidden
    /// sidebar has no host, so the video stays afloat.
    func dock() {
        guard isFloating, windowState?.isSidebarVisible == true else { return }
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
        session = other.session
        barSession = other.barSession
        webView = other.webView
        floatWindow = other.floatWindow
        (floatWindow?.contentView as? FloatRootView)?.controller = self
        isFloating = other.isFloating
        itemID = other.itemID
        let ready = other.isReady
        other.floatWindow = nil
        other.barSession = nil
        other.clear()
        generation += 1
        isReady = ready
        if ready, let webView { follow(webView) }
        if let session { followNavigation(of: session, generation: generation) }
    }

    func togglePlay() {
        webView?.evaluateJavaScript(
            "(() => { const v = window.__nookPiP?.video(); if (v) v.paused ? v.play() : v.pause(); })();",
            in: nil, in: Self.world)
    }

    func seek(_ seconds: Int) {
        webView?.evaluateJavaScript(
            "(() => { const v = window.__nookPiP?.video(); if (v) v.currentTime = Math.max(0, Math.min(v.duration || Infinity, v.currentTime + (\(seconds)))); })();",
            in: nil, in: Self.world)
    }

    /// Undoes `pageScript` in a page whose view has left the crop.
    static func restorePage(in webView: WKWebView) {
        webView.evaluateJavaScript("window.__nookPiP?.restore(true);", in: nil, in: world)
    }

    // MARK: - Page script

    /// Picks the video a person is watching: in system PiP, then playing, audible, largest.
    /// Shared with `PiPManager`, which runs it in the page's world.
    static let pickerScript = """
    const nookPlaying = v => !v.paused && !v.ended && v.readyState >= 2;
    // Feed autoplay, shorts and reels: nobody chose to watch these.
    const nookRefusesAutomatic = v => !nookPlaying(v) || v.muted || v.volume === 0 || v.loop
        || v.videoHeight > v.videoWidth;
    function nookPickVideo() {
        const playing = nookPlaying;
        const area = v => { const r = v.getBoundingClientRect(); return r.width * r.height; };
        const found = [...document.querySelectorAll('video')];
        if (!found.some(playing)) {
            // Some players keep the video in an open shadow root.
            const roots = [document];
            while (roots.length) {
                for (const el of roots.pop().querySelectorAll('*')) {
                    if (!el.shadowRoot) continue;
                    roots.push(el.shadowRoot);
                    found.push(...el.shadowRoot.querySelectorAll('video'));
                }
            }
        }
        const score = v => (v.webkitPresentationMode === 'picture-in-picture' ? 8 : 0)
            + (playing(v) ? 4 : 0) + (!v.muted && v.volume > 0 ? 2 : 0);
        return found.filter(v => area(v) > 1 || v.webkitPresentationMode === 'picture-in-picture')
            .sort((a, b) => score(b) - score(a) || area(b) - area(a))[0] || null;
    }
    """

    /// Defines `__nookPiP`: hides the rest of the player and anything over the video, in place.
    /// Visibility is used because a descendant can override it and stacking contexts cannot.
    static let pageScript = """
    if (!window.__nookPiP) window.__nookPiP = (() => {
        \(pickerScript)
        const S = { styles: [], covers: [] };
        const css = '[data-nook-pip-root] *, [data-nook-pip-root]::before, [data-nook-pip-root]::after, '
            + '[data-nook-pip-cover] { visibility: hidden !important; } '
            + '[data-nook-pip-video] { visibility: visible !important; }';
        const parentOf = n => n.parentElement || (n.parentNode && n.parentNode.host) || null;

        // The video's painted frame in CSS pixels, which letterboxing makes smaller than its box.
        function painted(v) {
            const cs = getComputedStyle(v), r = v.getBoundingClientRect();
            const px = k => parseFloat(cs[k]) || 0;
            let x = r.x + px('borderLeftWidth') + px('paddingLeft');
            let y = r.y + px('borderTopWidth') + px('paddingTop');
            let w = r.width - px('borderLeftWidth') - px('borderRightWidth') - px('paddingLeft') - px('paddingRight');
            let h = r.height - px('borderTopWidth') - px('borderBottomWidth') - px('paddingTop') - px('paddingBottom');
            const vw = v.videoWidth, vh = v.videoHeight;
            const s = { contain: Math.min(w / vw, h / vh), 'scale-down': Math.min(1, w / vw, h / vh), none: 1 }[cs.objectFit];
            if (vw > 0 && vh > 0 && s) {
                const [ox, oy] = (cs.objectPosition || '').split(' ');
                const offset = (t, free) => t && t.endsWith('%') ? free * parseFloat(t) / 100
                    : t && t.endsWith('px') ? parseFloat(t) : free / 2;
                x += offset(ox, w - vw * s);
                y += offset(oy, h - vh * s);
                w = vw * s;
                h = vh * s;
            }
            return { x, y, w, h };
        }

        // Only what is inside the viewport is drawn.
        function clip(p) {
            const x = Math.max(p.x, 0), y = Math.max(p.y, 0);
            return { x, y, w: Math.min(p.x + p.w, innerWidth) - x, h: Math.min(p.y + p.h, innerHeight) - y };
        }

        function rect() {
            if (!S.video || !S.video.isConnected) return { ok: false };
            const p = clip(painted(S.video)), vv = visualViewport, k = S.zoom * (vv ? vv.scale : 1);
            const ox = vv ? vv.offsetLeft : 0, oy = vv ? vv.offsetTop : 0;
            return { ok: true, x: (p.x - ox) * k, y: (p.y - oy) * k, w: p.w * k, h: p.h * k };
        }

        // Scrolls only when the video is mostly out of view, and remembers where the page was.
        function bringIntoView(v) {
            const p = painted(v), c = clip(p);
            if (Math.max(0, c.w) * Math.max(0, c.h) >= 0.9 * p.w * p.h) return;
            // Every scroller the scroll may move, not only the window.
            if (!S.scroll) {
                S.scroll = { url: location.href, at: [] };
                for (let n = parentOf(v); n; n = parentOf(n)) S.scroll.at.push([n, n.scrollLeft, n.scrollTop]);
            }
            v.scrollIntoView({ block: 'center', inline: 'nearest', behavior: 'instant' });
        }

        // The highest ancestor that is still about the video's size: the player.
        function playerRoot(v) {
            const box = v.getBoundingClientRect();
            let root = v;
            for (let n = parentOf(v); n && n !== document.body && n !== document.documentElement; n = parentOf(n)) {
                const r = n.getBoundingClientRect();
                if (r.width > box.width * 1.25 + 8 || r.height > box.height * 1.5 + 8) break;
                root = n;
            }
            return root;
        }

        // Anything outside the player painted over the video: a sticky header, a banner.
        function markCovers() {
            const p = clip(painted(S.video)), stop = new Set();
            for (let n = S.root; n; n = parentOf(n)) stop.add(n);
            for (const fx of [0.02, 0.5, 0.98]) for (const fy of [0.02, 0.5, 0.98]) {
                for (const el of document.elementsFromPoint(p.x + p.w * fx, p.y + p.h * fy)) {
                    if (stop.has(el) || S.root.contains(el)) break;
                    if (el.hasAttribute('data-nook-pip-cover')) continue;
                    el.setAttribute('data-nook-pip-cover', '');
                    S.covers.push(el);
                }
            }
        }

        function isolate(zoom, automatic) {
            restore(false);
            const v = nookPickVideo();
            if (!v) return { ok: false };
            if (automatic && nookRefusesAutomatic(v)) return { ok: false, skip: true };
            S.zoom = zoom;
            S.video = v;
            bringIntoView(v);
            S.root = playerRoot(v);
            S.root.setAttribute('data-nook-pip-root', '');
            v.setAttribute('data-nook-pip-video', '');
            for (const node of new Set([document, S.root.getRootNode(), v.getRootNode()])) {
                const style = document.createElement('style');
                style.textContent = css;
                (node.head || node.documentElement || node).appendChild(style);
                S.styles.push(style);
            }
            if (v.controls) { S.controls = true; v.controls = false; }
            markCovers();
            // A page reduced to its video must not hold text focus: a focused search box drops
            // its suggestions over the video.
            const a = document.activeElement;
            if (a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.isContentEditable)) a.blur();
            watch();
            return rect();
        }

        // Reports the next change to the video's rect, re-isolating when the page swaps the
        // element out. Event driven: nothing runs while the page is still.
        function watch() {
            const bump = () => {
                if (S.queued) return;
                S.queued = true;
                requestAnimationFrame(() => {
                    S.queued = false;
                    if (!S.video) return;
                    if (!S.video.isConnected) {
                        isolate(S.zoom, false);
                    } else {
                        for (const el of S.covers) el.removeAttribute('data-nook-pip-cover');
                        S.covers = [];
                        markCovers();
                    }
                    S.dirty = true;
                    flush();
                });
            };
            const observer = new ResizeObserver(bump);
            observer.observe(S.video);
            const video = S.video;
            const events = ['resize', 'loadedmetadata', 'emptied'];
            events.forEach(e => video.addEventListener(e, bump));
            // Only scrollers that carry the video: a chat scrolling beside it moves nothing.
            const scrolled = e => {
                for (let n = video; n; n = parentOf(n)) if (n === e.target) return bump();
                if (e.target === document) bump();
            };
            addEventListener('resize', bump);
            addEventListener('scroll', scrolled, { capture: true, passive: true });
            S.unwatch = () => {
                observer.disconnect();
                events.forEach(e => video.removeEventListener(e, bump));
                removeEventListener('resize', bump);
                removeEventListener('scroll', scrolled, { capture: true });
            };
        }

        function flush() {
            if (!S.dirty || !S.waiter) return;
            S.dirty = false;
            const r = rect(), key = JSON.stringify(r);
            if (r.ok && key === S.sent) return;
            S.sent = key;
            const waiter = S.waiter;
            S.waiter = null;
            waiter(r);
        }

        function next() {
            if (S.waiter) S.waiter({ ok: false, ended: true });
            return new Promise(resolve => { S.waiter = resolve; flush(); });
        }

        function restore(finished) {
            if (S.unwatch) S.unwatch();
            if (S.root) S.root.removeAttribute('data-nook-pip-root');
            if (S.video) {
                S.video.removeAttribute('data-nook-pip-video');
                if (S.controls) S.video.controls = true;
            }
            for (const el of S.covers) el.removeAttribute('data-nook-pip-cover');
            for (const el of S.styles) el.remove();
            Object.assign(S, { root: null, video: null, controls: false, covers: [], styles: [], unwatch: null, sent: null });
            if (!finished) return;
            if (S.scroll && S.scroll.url === location.href) {
                for (const [n, x, y] of S.scroll.at) n.scrollTo({ left: x, top: y, behavior: 'instant' });
            }
            S.scroll = null;
            if (S.waiter) {
                const waiter = S.waiter;
                S.waiter = null;
                waiter({ ok: false, ended: true });
            }
        }

        return { isolate, next, restore, video: () => S.video };
    })();
    """
}

// MARK: - View

/// The video itself, sized to the real aspect ratio of the media so nothing letterboxes, sitting
/// directly above `MediaControlsView`.
struct SidebarPiPView: View {
    @Environment(BrowserWindowState.self) var windowState

    @State private var isHovering = false

    private var controller: SidebarPiPController? { windowState.sidebarPiPController }

    var body: some View {
        if let controller, controller.isDocked, let webView = controller.webView {
            SidebarPiPWebViewHost(controller: controller, webView: webView, videoRect: controller.videoRect)
                .aspectRatio(controller.aspect, contentMode: .fit)
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                .nookElevation(.raised)
                .overlay {
                    if isHovering, controller.isReady { controls(controller) }
                }
                .onHoverTracking { hovering in
                    withAnimation(NookDesign.Motion.quick) { isHovering = hovering }
                }
                .gesture(DragGesture(minimumDistance: NookDesign.Spacing.md)
                    .onChanged { _ in controller.popOut() })
                // The view is hosted from the start so the page never leaves the window; the video
                // rises out of the bar once its isolated frame is on screen.
                .modifier(CollapseModifier(heightScale: controller.isReady ? 1 : CollapseModifier.collapsed))
                .opacity(controller.isReady ? 1 : 0)
                .padding(.horizontal, NookDesign.Spacing.sidebarInset)
                .transition(.asymmetric(insertion: .identity, removal: .collapseIntoBar))
        } else if let controller, controller.isFloating, controller.isDragging {
            dropZone(controller)
        }
    }

    private func dropZone(_ controller: SidebarPiPController) -> some View {
        NookDesign.Radius.shape(NookDesign.Radius.md)
            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [NookDesign.Spacing.sm, NookDesign.Spacing.xs]))
            .overlay { Label("Dock video", systemImage: "pip.enter").font(NookDesign.Font.caption) }
            .foregroundStyle(controller.isOverDock ? .primary : .tertiary)
            .aspectRatio(controller.aspect, contentMode: .fit)
            .background(DockZoneReporter(controller: controller))
            .padding(.horizontal, NookDesign.Spacing.sidebarInset)
    }

    @ViewBuilder
    private func controls(_ controller: SidebarPiPController) -> some View {
        ZStack {
            Color.black.opacity(0.35)

            HStack(spacing: NookDesign.Spacing.xl) {
                Button("Rewind", systemImage: "gobackward.10") { controller.seek(-10) }
                Button(isPlaying ? "Pause" : "Play", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                    controller.togglePlay()
                }
                Button("Forward", systemImage: "goforward.10") { controller.seek(10) }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(NookIconButtonStyle(size: 24))
            .foregroundStyle(Color.white)

            // Sending the video back to its tab, still playing, is a minimise rather than a close.
            Button("Minimize", systemImage: "minus") {
                withAnimation(NookDesign.Motion.quick) {
                    isHovering = false
                    controller.exit()
                }
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
}

// MARK: - Web view host

/// Crops the web view down to the video's rectangle. The page lays out at a normal desktop size
/// and keeps it; a layer transform on the clipping container scales the video's rect to fill the
/// sidebar slot.
private struct SidebarPiPWebViewHost: NSViewRepresentable {
    let controller: SidebarPiPController
    let webView: WKWebView
    let videoRect: CGRect

    func makeNSView(context: Context) -> SidebarPiPCropView {
        SidebarPiPCropView(frame: .zero)
    }

    func updateNSView(_ container: SidebarPiPCropView, context: Context) {
        // A host on its way out still gets updates; it must not take back a view that floated.
        guard !controller.isFloating, controller.webView === webView else { return }
        if webView.superview !== container {
            // No autoresizing and no frame change: the page must keep the layout it was measured
            // in. Cropping needs no particular size, and reflowing costs a white repaint.
            webView.autoresizingMask = []
            container.addSubview(webView)
        }
        container.crop = videoRect
    }

    static func dismantleNSView(_ container: SidebarPiPCropView, coordinator: ()) {
        container.subviews.forEach { $0.removeFromSuperview() }
    }
}

/// Flipped so its coordinates match the page's. A web view inside one ignores the pointer
/// (`FocusableWKWebView`), since AppKit would map it without the crop's transform.
final class SidebarPiPCropView: NSView {
    var crop: CGRect = .zero { didSet { needsLayout = true } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }

    // The page gets no clicks or scrolls: a click would select its tab, a scroll would move
    // the video out from under the crop.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func layout() {
        super.layout()
        guard crop.width > 1, crop.height > 1, bounds.width > 1, bounds.height > 1, let layer else { return }
        // Fill on both axes, centred, so a rect whose aspect lags the slot trims video rather
        // than showing page around it.
        let scale = max(bounds.width / crop.width, bounds.height / crop.height)
        let inset = CGPoint(x: (bounds.width - crop.width * scale) / 2, y: (bounds.height - crop.height * scale) / 2)
        layer.sublayerTransform = CATransform3DConcat(
            CATransform3DConcat(CATransform3DMakeTranslation(-crop.minX, -crop.minY, 0),
                                CATransform3DMakeScale(scale, scale, 1)),
            CATransform3DMakeTranslation(inset.x, inset.y, 0))
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
    let container = SidebarPiPCropView(frame: .zero)
    /// Only the newest observation re-arms, so handing the panel between windows adds no chains.
    private var playStateToken = 0
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
        playStateToken += 1
        let token = playStateToken
        let playing = withObservationTracking {
            controller?.session?.hasPlayingVideo == true
        } onChange: { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playStateToken == token else { return }
                self.trackPlayState()
            }
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
    /// The bar's height as a share of the video's: where the video rises from and returns to.
    static let collapsed: CGFloat = 0.04
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
        .modifier(active: CollapseModifier(heightScale: CollapseModifier.collapsed),
                  identity: CollapseModifier(heightScale: 1))
    }
}
