// Licensed under GPL-3.0. See LICENSE.
//
//  PDFControlsView.swift
//  Nook
//
//  The PDF viewer's controls: zoom, open in the default PDF app, print, save. They replace WebKit's own
//  bar, which BrowserConfiguration switches off, and float over the page as one glass pill.
//

import SwiftUI
import WebKit
import NookDesign
import NookUI
import NookWeb

struct PDFControlsView: View {
    let session: PageSession
    let webView: WKWebView

    @EnvironmentObject var browserManager: BrowserManager
    @State private var isAutoHidden = false
    @State private var isHovered = false

    private static let autoHideDelay: Duration = .seconds(3)

    /// Like WebKit's own bar: shown on load and whenever the pointer moves over the page, gone
    /// three seconds later unless the pointer is on it.
    private var isVisible: Bool { !isAutoHidden || isHovered }

    var body: some View {
        HStack(spacing: 0) {
            Button("Zoom Out", systemImage: "minus.magnifyingglass") {
                browserManager.zoomManager.zoomOut(for: webView, tabId: session.itemID)
                browserManager.shouldShowZoomPopup = true
            }
            divider
            Button("Zoom In", systemImage: "plus.magnifyingglass") {
                browserManager.zoomManager.zoomIn(for: webView, tabId: session.itemID)
                browserManager.shouldShowZoomPopup = true
            }
            divider
            Button("Open in Preview", systemImage: "arrow.up.forward.app") {
                session.openPDFInDefaultApp(from: webView)
            }
            divider
            Button("Print", systemImage: "printer") {
                webView.nookPrint()
            }
            divider
            Button("Save PDF", systemImage: "arrow.down.circle") {
                session.savePDF(from: webView)
            }
        }
        // Dividers take any height offered; the pill is the buttons' height.
        .frame(height: NookDesign.Size.glassControl)
        .nookGlassControls(in: Capsule())
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .animation(NookDesign.Motion.standard, value: isVisible)
        .onHoverTracking { isHovered = $0 }
        .task(id: session.pdfControlsReveal) {
            isAutoHidden = false
            try? await Task.sleep(for: Self.autoHideDelay)
            guard !Task.isCancelled else { return }
            isAutoHidden = true
        }
    }

    private var divider: some View {
        Divider().padding(.vertical, NookDesign.Spacing.sm)
    }
}
