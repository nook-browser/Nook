// Licensed under GPL-3.0. See LICENSE.
//
//  DetachedPageView.swift
//  Nook
//
//  A detached page's live web view, for Peek and the mini window, and the load bar over it.
//

import AppKit
import Combine
import NookDesign
import NookWeb
import SwiftUI
import WebKit

/// Hosts the page's web view in a container SwiftUI owns, so moving the view into a tab leaves
/// the container empty instead of pulling the tab's view back out. Corners come from the
/// container's own layer: a SwiftUI clip or shadow over a WKWebView flashes its video black.
/// Reads `webView`, never `activeWebView`: a redraw after the page ended must not reload it.
struct DetachedPageHost: NSViewRepresentable {
    let page: PageSession
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSView {
        let container = DetachedPageContainer()
        container.wantsLayer = true
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        container.pendingPage = page.webView
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        container.layer?.cornerRadius = cornerRadius
    }
}

/// Holds the page until the container is in a window, then keeps it at the container's bounds.
/// SwiftUI sizes a new container before it is in a window (2000x1500, then the card's size), and
/// WebKit resizes its inner drawing view only for the first of those: the page then drew at
/// 2000x1500, offset by (-201, -402.5), in an 1848x1195 Peek card. Tabs never resize off-window.
private final class DetachedPageContainer: NSView {
    /// Attached once; after a move to a tab the view belongs to the tab.
    weak var pendingPage: NSView?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // A page moved to a tab before the card reached the window stays in the tab.
        guard window != nil, let page = pendingPage, page.superview == nil else { return }
        pendingPage = nil
        page.frame = bounds
        addSubview(page)
    }

    override func resizeSubviews(withOldSize oldSize: NSSize) { pinSubviews() }

    override func layout() {
        super.layout()
        pinSubviews()
    }

    private func pinSubviews() {
        for subview in subviews where subview.frame != bounds { subview.frame = bounds }
    }
}

/// A thin bar showing how far the page has loaded; hidden once it finishes.
struct PageLoadBar: View {
    let webView: WKWebView
    let tint: Color
    @State private var progress = 0.0
    @State private var isLoading = false

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(tint)
                .frame(width: geometry.size.width * progress)
        }
        .frame(height: NookDesign.Size.loadBar)
        .opacity(isLoading ? 1 : 0)
        .animation(NookDesign.Motion.quick, value: progress)
        .animation(NookDesign.Motion.quick, value: isLoading)
        .allowsHitTesting(false)
        .onReceive(webView.publisher(for: \.estimatedProgress)) { progress = $0 }
        .onReceive(webView.publisher(for: \.isLoading)) { isLoading = $0 }
    }
}
