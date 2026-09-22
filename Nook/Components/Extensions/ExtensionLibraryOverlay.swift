// Licensed under GPL-3.0. See LICENSE.
//
//  ExtensionLibraryOverlay.swift
//  Nook
//
//  Created by Bain Gurley on 21/09/2026.
//

import SwiftUI
import NookDesign
import NookWeb

/// Where the URL bar's overflow button sits, reported so the overlay can hang off it.
struct ExtensionLibraryAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

/// The extension library and its overflow menu, drawn inside the window rather than in an
/// `NSPanel`. Only the key window renders the active Liquid Glass appearance, so a panel is
/// always foggy, and a key panel gets a heavier window shadow that squares off at its own edge.
/// In-window has neither problem and needs no event monitors to dismiss.
struct ExtensionLibraryOverlay: View {
    let anchor: Anchor<CGRect>?

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isShowingMoreMenu = false

    private let menuWidth: CGFloat = 300
    private let gap: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            if windowState.isExtensionLibraryVisible,
               let settings = browserManager.nookSettings,
               let anchor {
                let buttonFrame = proxy[anchor]

                ZStack(alignment: .topLeading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { close() }

                    HStack(alignment: .top, spacing: gap) {
                        ExtensionLibraryView(
                            browserManager: browserManager,
                            windowState: windowState,
                            settings: settings,
                            onDismiss: { close() },
                            onShowMoreMenu: { isShowingMoreMenu.toggle() }
                        )
                        .frame(width: menuWidth)
                        .nookGlassEffect(in: NookDesign.Radius.shape(NookDesign.Radius.lg))

                        if isShowingMoreMenu {
                            MoreMenuView(
                                browserManager: browserManager,
                                windowState: windowState,
                                onDismiss: { isShowingMoreMenu = false }
                            )
                            .nookGlassEffect(in: NookDesign.Radius.shape(NookDesign.Radius.lg))
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                        }
                    }
                    .fixedSize()
                    .offset(x: originX(buttonFrame: buttonFrame, container: proxy.size),
                            y: buttonFrame.maxY + gap)
                }
                .animation(NookDesign.Motion.quick, value: isShowingMoreMenu)
                .onExitCommand { close() }
                .onChange(of: windowState.selectedItemID) { _, _ in close() }
            }
        }
        .ignoresSafeArea()
    }

    /// Centred under the button, clamped so a narrow window cannot push it off screen. Centring
    /// uses the library's own width, not the pair's, so the library stays put when the overflow
    /// menu opens beside it.
    private func originX(buttonFrame: CGRect, container: CGSize) -> CGFloat {
        let preferred = buttonFrame.midX - menuWidth / 2
        let maxX = max(gap, container.width - menuWidth - gap)
        return min(max(gap, preferred), maxX)
    }

    private func close() {
        isShowingMoreMenu = false
        windowState.isExtensionLibraryVisible = false
    }
}
