// Licensed under GPL-3.0. See LICENSE.
//
//  RootView.swift
//  NookiOS
//
//  Two layouts chosen by horizontal size class, and the modifiers they share.
//  Compact: the page fills the scene and the bar floats over it. SwiftUI raises
//  the stack's bottom safe area when the keyboard appears, which is what lets
//  the bar ride the keyboard with no keyboard-frame observer. The page keeps its
//  full height and gets a scroll inset instead, so content behind the glass is
//  still reachable, the way Safari does it.
//

import SwiftUI
import WebKit
import NookDesign
import NookWeb

struct RootView: View {
    @EnvironmentObject private var model: BrowserModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .compact {
                CompactRootView()
            } else {
                RegularRootView()
            }
        }
        // Every shared modifier stays on this outer view, so the two layouts
        // cannot drift apart.
        .sheet(item: $model.sheet) { sheet in
            // A sheet does not inherit the scene's environment values.
            Group {
                switch sheet {
                case .tabs: TabSheet()
                case .settings: SettingsSheet()
                }
            }
            .nookEnvironment(model)
            .dialogHost()
        }
        .dialogHost(enabled: model.sheet == nil)
        .task {
            await model.start()
            model.openDebugSheetIfRequested()
        }
        .onOpenURL { model.navigate($0.absoluteString) }
    }
}

struct CompactRootView: View {
    @EnvironmentObject private var model: BrowserModel
    @State private var barHeight: CGFloat = 0
    @State private var condensed = false

    var body: some View {
        ZStack(alignment: .bottom) {
            if let session = model.selectedSession {
                WebViewContainer(
                    webView: session.activeWebView,
                    bottomInset: barHeight,
                    onScrollDirection: { condensed = $0 }
                )
                .ignoresSafeArea(.container, edges: .top)
            } else {
                Color.clear
            }

            BottomBar(condensed: $condensed)
                .padding(.horizontal, NookDesign.Spacing.md)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    // Only the expanded height insets the page, so condensing
                    // does not reflow what you are reading.
                    guard !condensed else { return }
                    barHeight = height
                }
        }
        .onChange(of: model.selectedSession?.itemID) { _, _ in condensed = false }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    /// How much of the page the floating bar covers.
    let bottomInset: CGFloat
    /// True when the reader is moving down the page and the bar should condense.
    var onScrollDirection: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ view: UIView, context: Context) {
        if webView.superview !== view {
            view.subviews.forEach { $0.removeFromSuperview() }
            webView.frame = view.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(webView)
        }
        context.coordinator.onScrollDirection = onScrollDirection
        context.coordinator.observe(webView.scrollView)

        let scroll = webView.scrollView
        guard scroll.contentInset.bottom != bottomInset else { return }
        scroll.contentInset.bottom = bottomInset
        scroll.verticalScrollIndicatorInsets.bottom = bottomInset
    }

    /// Reads the scroll direction off the pan gesture rather than observing
    /// contentOffset, which would fire every frame of every scroll.
    @MainActor
    final class Coordinator {
        var onScrollDirection: ((Bool) -> Void)?
        private weak var observed: UIScrollView?

        func observe(_ scroll: UIScrollView) {
            guard observed !== scroll else { return }
            observed?.panGestureRecognizer.removeTarget(self, action: nil)
            observed = scroll
            scroll.panGestureRecognizer.addTarget(self, action: #selector(panned(_:)))
        }

        @objc private func panned(_ gesture: UIPanGestureRecognizer) {
            guard let scroll = observed else { return }
            // The top of a page always shows the whole bar; there is nothing to
            // reclaim and the page has not been read into yet.
            if scroll.contentOffset.y <= scroll.adjustedContentInset.top {
                onScrollDirection?(false)
                return
            }
            let velocity = gesture.velocity(in: scroll).y
            if velocity < -80 {
                onScrollDirection?(true)
            } else if velocity > 80 {
                onScrollDirection?(false)
            }
        }
    }
}
