// Licensed under GPL-3.0. See LICENSE.
//
//  SplitPaneView.swift
//  Nook
//
//  One pane of the split view: the page, with controls floating over it. The compositor keeps
//  panes across refreshes so a web view never leaves its superview while the pair holds.
//

import AppKit
import SwiftUI
import NookDesign
import NookSettings
import NookTabsCore
import NookUI
import NookWeb

final class SplitPaneView: NSView {
    // A CGColor is frozen at creation; re-resolve it when light/dark changes.
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        }
    }

    let side: SplitViewManager.Side
    let itemID: UUID
    /// The page view's parent. It fills the pane; the controls float over it.
    let content = NSView()
    private let maskLayer = CAShapeLayer()
    private weak var settings: NookSettingsService?

    init(frame: NSRect, side: SplitViewManager.Side, itemID: UUID, browserManager: BrowserManager, windowState: BrowserWindowState, hoverManager: HoverSidebarManager) {
        self.side = side
        self.itemID = itemID
        self.settings = browserManager.nookSettings
        super.init(frame: frame)
        wantsLayer = true
        layer?.mask = maskLayer
        viewDidChangeEffectiveAppearance()
        content.frame = bounds
        content.autoresizingMask = [.width, .height]
        addSubview(content)

        // Each control is its own hosting view sized to its content, so the rest of the pane
        // passes clicks to the page.
        func host(_ view: some View, textCursor: Bool = false) -> NSView {
            let host = SplitControlHostingView(rootView: view
                .environment(browserManager.tabs)
                .environment(windowState)
                .environment(\.tabActions, browserManager))
            host.usesTextCursor = textCursor
            host.translatesAutoresizingMaskIntoConstraints = false
            host.safeAreaRegions = []
            addSubview(host)
            return host
        }
        let title = host(URLBarView(isSidebarHovered: false, splitItemID: itemID)
            .environmentObject(browserManager)
            .environmentObject(hoverManager), textCursor: true)
        let buttons = host(SplitPaneButtons(itemID: itemID))
        let inset = NookDesign.Spacing.md
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: inset),
            title.trailingAnchor.constraint(lessThanOrEqualTo: buttons.leadingAnchor, constant: -inset),
            buttons.topAnchor.constraint(equalTo: topAnchor, constant: inset),
            buttons.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -inset),
        ])
        updateMask()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Puts `view` in the pane, leaving it alone when it is already there.
    func show(_ view: NSView) {
        if view.superview !== content {
            content.subviews.forEach { $0.removeFromSuperview() }
            content.addSubview(view)
        }
        view.frame = content.bounds
        view.autoresizingMask = [.width, .height]
        view.isHidden = false
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateMask()
    }

    private func updateMask() {
        let radius = NookDesign.Radius.page
        // Toggling the border resizes the pane, so this reruns through setFrameSize.
        let outer = settings?.hideWebContentBorder == true ? 0 : radius
        maskLayer.path = TabCompositorWrapper.createUnevenRoundedRectPath(
            rect: bounds,
            topLeadingRadius: side == .left ? 0 : radius,
            bottomLeadingRadius: side == .left ? outer : radius,
            bottomTrailingRadius: side == .right ? outer : radius,
            topTrailingRadius: side == .right ? 0 : radius
        )
    }
}

/// Separate and close, floating at the pane's top trailing corner in one group.
private struct SplitPaneButtons: View {
    let itemID: UUID

    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.tabActions) private var actions

    var body: some View {
        HStack(spacing: NookDesign.Spacing.xxs) {
            SplitPaneButton(systemImage: "rectangle.split.2x1.slash", help: "Separate Tabs") {
                actions?.separateSplit(in: windowState)
            }
            SplitPaneButton(systemImage: "xmark", help: "Close Tab") {
                tabs.close(itemID)
            }
        }
        .padding(.horizontal, NookDesign.Spacing.xs)
        .frame(height: NookDesign.Size.navRow)
        .nookFloatingSurface(in: NookDesign.Radius.shape(NookDesign.Radius.md))
    }
}

private struct SplitPaneButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(NookDesign.Font.secondary)
                .foregroundStyle(.primary)
                .frame(width: NookDesign.Size.rowButton, height: NookDesign.Size.rowButton)
                .background(isHovering ? NookDesign.Surface.fillPressed : Color.clear)
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
        }
        .buttonStyle(PlainButtonStyle())
        .help(help)
        .onHoverTracking { isHovering = $0 }
    }
}

/// The title is hosted above WKWebView, which manages its own cursors. Register the
/// text cursor on that native host so the page and SwiftUI button cannot replace it.
private final class SplitControlHostingView<Content: View>: NSHostingView<Content> {
    var usesTextCursor = false
    private var textCursorTracking: NSTrackingArea?

    override func resetCursorRects() {
        super.resetCursorRects()
        if usesTextCursor { addCursorRect(bounds, cursor: .iBeam) }
    }

    override func updateTrackingAreas() {
        if let textCursorTracking { removeTrackingArea(textCursorTracking) }
        textCursorTracking = nil
        super.updateTrackingAreas()
        if usesTextCursor {
            let area = NSTrackingArea(rect: .zero,
                                      options: [.cursorUpdate, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
            addTrackingArea(area)
            textCursorTracking = area
        }
    }

    override func cursorUpdate(with event: NSEvent) {
        if usesTextCursor { NSCursor.iBeam.set() }
        else { super.cursorUpdate(with: event) }
    }
}
