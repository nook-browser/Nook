// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  SplitPaneView.swift
//  Nook
//
//  One pane of the split view: a header strip above the page. The compositor keeps
//  panes across refreshes so a web view never leaves its superview while the pair holds.
//

import AppKit
import SwiftUI
import NookDesign
import NookTabsCore
import NookUI
import NookWeb

final class SplitPaneView: NSView {
    let side: SplitViewManager.Side
    let itemID: UUID
    /// The page view's parent, below the header.
    let content = NSView()
    private let header: NSView
    private let maskLayer = CAShapeLayer()
    private let borderLayer = CAShapeLayer()

    init(frame: NSRect, side: SplitViewManager.Side, itemID: UUID, browserManager: BrowserManager, windowState: BrowserWindowState) {
        self.side = side
        self.itemID = itemID
        header = NSHostingView(rootView: SplitPaneHeader(itemID: itemID)
            .environment(browserManager.tabs)
            .environment(windowState)
            .environment(\.tabActions, browserManager))
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.mask = maskLayer
        borderLayer.fillColor = NSColor.clear.cgColor
        borderLayer.lineWidth = 1
        borderLayer.zPosition = 1
        layer?.addSublayer(borderLayer)
        addSubview(content)
        addSubview(header)
        layoutPane()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setActive(_ isActive: Bool, accent: NSColor) {
        borderLayer.strokeColor = isActive ? accent.withAlphaComponent(0.9).cgColor : NSColor.clear.cgColor
    }

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
        layoutPane()
    }

    private func layoutPane() {
        let headerHeight = NookDesign.Size.navRow
        header.frame = NSRect(x: 0, y: bounds.height - headerHeight, width: bounds.width, height: headerHeight)
        content.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, bounds.height - headerHeight))
        let radius = NookDesign.Radius.md
        let path = TabCompositorWrapper.createUnevenRoundedRectPath(
            rect: bounds,
            topLeadingRadius: side == .left ? 0 : radius,
            bottomLeadingRadius: radius,
            bottomTrailingRadius: radius,
            topTrailingRadius: side == .right ? 0 : radius
        )
        maskLayer.path = path
        borderLayer.path = path
    }
}

/// The strip above a split pane: what the pane shows, plus separate and close.
private struct SplitPaneHeader: View {
    let itemID: UUID

    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.tabActions) private var actions

    var body: some View {
        HStack(spacing: NookDesign.Spacing.sm) {
            if let item = tabs.item(itemID) {
                ItemFavicon(item: item, session: tabs.session(for: itemID))
                    .frame(width: NookDesign.Size.favicon, height: NookDesign.Size.favicon)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
                Text(tabs.title(for: item))
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(isActive ? .primary : .secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: NookDesign.Spacing.xs)
            SplitPaneButton(systemImage: "rectangle.split.2x1.slash", help: "Separate Tabs") {
                actions?.separateSplit(in: windowState)
            }
            SplitPaneButton(systemImage: "xmark", help: "Close Tab") {
                tabs.close(itemID)
            }
        }
        .padding(.horizontal, NookDesign.Spacing.rowPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isActive ? NookDesign.Surface.raised : NookDesign.Surface.fill)
        .contentShape(Rectangle())
        .onTapGesture { tabs.select(itemID, in: windowState) }
    }

    private var isActive: Bool {
        tabs.selectedItemID(in: windowState) == itemID
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
