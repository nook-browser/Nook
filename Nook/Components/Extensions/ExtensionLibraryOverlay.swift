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
/// `NSPanel`: a key panel gets a heavier window shadow that squares off at its own edge, and
/// in-window needs no event monitors to dismiss.
struct ExtensionLibraryOverlay: View {
    let anchor: Anchor<CGRect>?

    @EnvironmentObject var browserManager: BrowserManager
    @Environment(BrowserWindowState.self) private var windowState
    @State private var isShowingMoreMenu = false
    @State private var appeared = false

    private let menuWidth: CGFloat = 300
    private let gap: CGFloat = 10
    private let notchWidth: CGFloat = 18
    private let notchHeight: CGFloat = 8

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
                        .nookFloatingSurface(in: NookDesign.Radius.shape(NookDesign.Radius.xl))
                        // Arc's notch, pointing at the button the panel came from.
                        .overlay(alignment: .topLeading) {
                            PanelNotch()
                                .fill(NookDesign.Surface.raised)
                                .frame(width: notchWidth, height: notchHeight)
                                .offset(x: buttonFrame.midX - originX(buttonFrame: buttonFrame, container: proxy.size) - notchWidth / 2,
                                        y: -notchHeight + 1)
                        }
                        // Grows out of the button rather than appearing whole.
                        .scaleEffect(appeared ? 1 : 0.88, anchor: UnitPoint(
                            x: (buttonFrame.midX - originX(buttonFrame: buttonFrame, container: proxy.size)) / menuWidth, y: 0))
                        .opacity(appeared ? 1 : 0)
                        .onAppear {
                            withAnimation(.interpolatingSpring(Spring(response: 0.3, dampingRatio: 0.86))) { appeared = true }
                        }
                        .onDisappear { appeared = false }

                        if isShowingMoreMenu {
                            MoreMenuView(
                                browserManager: browserManager,
                                windowState: windowState,
                                onDismiss: { isShowingMoreMenu = false }
                            )
                            .nookFloatingSurface(in: NookDesign.Radius.shape(NookDesign.Radius.lg))
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)))
                        }
                    }
                    .fixedSize()
                    .offset(x: originX(buttonFrame: buttonFrame, container: proxy.size),
                            y: buttonFrame.maxY + gap)
                }
                .animation(NookDesign.Motion.quick, value: isShowingMoreMenu)
                .transition(.opacity)
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
        withAnimation(.interpolatingSpring(Spring(response: 0.25, dampingRatio: 1))) {
            windowState.isExtensionLibraryVisible = false
        }
    }
}

/// A small rounded triangle pointing up.
private struct PanelNotch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.midX - rect.width * 0.18, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX + rect.width * 0.18, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
