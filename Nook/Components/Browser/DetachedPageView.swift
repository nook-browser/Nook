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
        let container = NSView()
        container.wantsLayer = true
        container.layer?.cornerCurve = .continuous
        container.layer?.masksToBounds = true
        if let webView = page.webView {
            webView.frame = container.bounds
            webView.autoresizingMask = [.width, .height]
            container.addSubview(webView)
        }
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        container.layer?.cornerRadius = cornerRadius
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
