// Licensed under GPL-3.0. See LICENSE.
//
//  SplitHalfLabel.swift
//  NookUI
//
//  One half of the sidebar's split row: everything but the drag source, which is an
//  AppKit view the app wraps around this.
//

import SwiftUI
import NookDesign
import NookTabsCore
import NookWeb

public struct SplitHalfLabel: View {
    let item: Item

    @State private var isHovering: Bool = false
    @State private var isCloseHovering: Bool = false
    @Environment(TabsController.self) private var tabs
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(\.tabActions) private var actions

    public init(item: Item) {
        self.item = item
    }

    public var body: some View {
        let title = tabs.title(for: item)
        let session = tabs.session(for: item.id)
        Button(action: { tabs.select(item.id, in: windowState) }) {
            HStack(spacing: NookDesign.Spacing.md) {
                ItemFavicon(item: item, session: session)
                    .frame(width: NookDesign.Size.favicon, height: NookDesign.Size.favicon)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))
                Text(title)
                    .font(NookDesign.Font.body)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: NookDesign.Spacing.xs)
                if isHovering {
                    Button(action: { tabs.close(item.id) }) {
                        Image(systemName: "xmark")
                            .font(NookDesign.Font.secondary)
                            .foregroundColor(.primary)
                            .frame(width: NookDesign.Size.rowButton, height: NookDesign.Size.rowButton)
                            .background(isCloseHovering ? NookDesign.Surface.fillPressed : Color.clear)
                            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                    }
                    .buttonStyle(PlainButtonStyle())
                    .onHoverTracking { state in
                        isCloseHovering = state
                    }
                }
            }
            .padding(.horizontal, NookDesign.Spacing.rowPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
                isHovering = hovering
            }
        }
        .contextMenu {
            TabContextMenu(itemID: item.id, context: .split)
                .environment(windowState)
                .environment(tabs)
                .environment(\.tabActions, actions)
        }
        .background(isHovering ? NookDesign.Surface.fill : Color.clear)
    }
}
