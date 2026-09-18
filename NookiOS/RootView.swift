// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  RootView.swift
//  NookiOS
//
//  The page fills the scene and the bar floats over it. SwiftUI raises the
//  stack's bottom safe area when the keyboard appears, which is what lets the
//  bar ride the keyboard with no keyboard-frame observer. The page keeps its
//  full height and gets a scroll inset instead, so content behind the glass is
//  still reachable, the way Safari does it.
//

import SwiftUI
import WebKit
import NookDesign
import NookWeb

struct RootView: View {
    @EnvironmentObject private var model: BrowserModel
    @State private var barHeight: CGFloat = 0

    var body: some View {
        ZStack(alignment: .bottom) {
            if let session = model.selectedSession {
                WebViewContainer(webView: session.activeWebView, bottomInset: barHeight)
                    .ignoresSafeArea(.container, edges: .top)
            } else {
                Color.clear
            }

            BottomBar()
                .padding(.horizontal, NookDesign.Spacing.md)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { barHeight = $0 }
        }
        .sheet(item: $model.sheet) { sheet in
            // A sheet does not inherit the scene's environment values.
            Group {
                switch sheet {
                case .tabs: TabSheet()
                case .settings: SettingsSheet()
                }
            }
            .nookEnvironment(model)
        }
        .task {
            await model.start()
            model.openDebugSheetIfRequested()
        }
        .onOpenURL { model.navigate($0.absoluteString) }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView
    /// How much of the page the floating bar covers.
    let bottomInset: CGFloat

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ view: UIView, context: Context) {
        if webView.superview !== view {
            view.subviews.forEach { $0.removeFromSuperview() }
            webView.frame = view.bounds
            webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(webView)
        }
        let scroll = webView.scrollView
        guard scroll.contentInset.bottom != bottomInset else { return }
        scroll.contentInset.bottom = bottomInset
        scroll.verticalScrollIndicatorInsets.bottom = bottomInset
    }
}
