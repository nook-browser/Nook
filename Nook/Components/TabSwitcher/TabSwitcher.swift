// Licensed under GPL-3.0. See LICENSE.
//
//  TabSwitcher.swift
//  Nook
//
//  Arc's Control-Tab: hold Control, press Tab to step through this window's recent tabs on a
//  card of page pictures, let go to switch; Shift goes back, Escape stays put.
//

import AppKit
import SwiftUI
import NookDesign
import NookTabsCore
import NookWeb
import NookUI

@MainActor
enum TabSwitcher {
    /// Watches for Control being let go (and Escape) while the card is open, and only then:
    /// a modifier release reaches no view, so nothing else can see it.
    private static var monitor: Any?
    private static let maxTabs = 8

    /// Control-Tab (`step` 1) or Control-Shift-Tab (-1): opens the card, or moves along it.
    static func step(_ step: Int, in window: BrowserWindowState, tabs: TabsController) {
        if var state = window.tabSwitcher {
            state.advance(by: step)
            window.tabSwitcher = state
            return
        }
        guard let state = TabSwitcherState.start(items: Array(tabs.recentItems(in: window).prefix(maxTabs)), step: step) else { return }
        // A quick tap can let Control go before this runs: then it is a plain flip to the last tab.
        guard NSEvent.modifierFlags.contains(.control) else {
            tabs.select(state.highlighted, in: window)
            return
        }
        window.tabSwitcher = state
        install(window: window, tabs: tabs)
    }

    /// Switches to the highlighted tab, or to `itemID` when one was clicked.
    static func commit(_ window: BrowserWindowState, tabs: TabsController, to itemID: UUID? = nil) {
        guard let state = window.tabSwitcher else { return }
        finish(window)
        tabs.select(itemID ?? state.highlighted, in: window)
    }

    static func cancel(_ window: BrowserWindowState) { finish(window) }

    private static func finish(_ window: BrowserWindowState) {
        window.tabSwitcher = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private static func install(window: BrowserWindowState, tabs: TabsController) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.flagsChanged, .keyDown]) { [weak window] event in
            guard let window, window.tabSwitcher != nil else { return event }
            switch event.type {
            case .flagsChanged where !event.modifierFlags.contains(.control):
                commit(window, tabs: tabs)
            case .keyDown where event.keyCode == 53: // Escape
                cancel(window)
                return nil
            default:
                break
            }
            return event
        }
    }
}

/// The card: a row of recent tabs, each its page's picture over its icon and title.
struct TabSwitcherOverlay: View {
    @Environment(BrowserWindowState.self) private var windowState
    @Environment(TabsController.self) private var tabs

    private let tileWidth: CGFloat = 180
    private let pictureHeight: CGFloat = 112

    var body: some View {
        if let state = windowState.tabSwitcher {
            HStack(spacing: NookDesign.Spacing.sm) {
                ForEach(Array(state.items.enumerated()), id: \.element) { index, itemID in
                    if let item = tabs.item(itemID) {
                        tile(item, selected: index == state.index)
                    }
                }
            }
            .padding(NookDesign.Spacing.md)
            .nookFloatingSurface(in: NookDesign.Radius.shape(NookDesign.Radius.xl))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }

    private func tile(_ item: Item, selected: Bool) -> some View {
        let session = tabs.session(for: item.id)
        return VStack(alignment: .leading, spacing: NookDesign.Spacing.sm) {
            Group {
                if let picture = session?.switcherSnapshot {
                    Image(platformImage: picture)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    // A tab with no picture yet (never left while on screen) shows its icon large.
                    ItemFavicon(item: item, session: session)
                        .frame(width: NookDesign.Size.essentialsTile, height: NookDesign.Size.essentialsTile)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(NookDesign.Surface.fill)
                }
            }
            .frame(width: tileWidth - NookDesign.Spacing.md, height: pictureHeight)
            .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
            .overlay(NookDesign.Radius.shape(NookDesign.Radius.md).strokeBorder(NookDesign.Surface.hairline))

            HStack(spacing: NookDesign.Spacing.sm) {
                ItemFavicon(item: item, session: session)
                    .frame(width: NookDesign.Size.favicon, height: NookDesign.Size.favicon)
                Text(tabs.title(for: item))
                    .font(NookDesign.Font.body)
                    .lineLimit(1)
            }
        }
        .padding(NookDesign.Spacing.sm)
        .frame(width: tileWidth)
        .nookRowSelection(selected, radius: NookDesign.Radius.lg)
        .contentShape(NookDesign.Radius.shape(NookDesign.Radius.lg))
        .onTapGesture { TabSwitcher.commit(windowState, tabs: tabs, to: item.id) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
