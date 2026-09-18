// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  RootView.swift
//  NookiOS
//
//  Milestone one: the selected page above a URL field. The bottom bar, tab sheet and space
//  dots replace this in the second plan.
//

import SwiftUI
import WebKit
import NookDesign
import NookWeb

struct RootView: View {
    @EnvironmentObject private var model: BrowserModel
    @State private var address = ""

    var body: some View {
        VStack(spacing: 0) {
            if let session = model.selectedSession {
                WebViewContainer(webView: session.activeWebView)
            } else {
                Color.clear
            }
            TextField("Search or enter address", text: $address)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.webSearch)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.go)
                .onSubmit { model.navigate(address) }
                .padding(NookDesign.Spacing.md)
        }
        .task { await model.start() }
        .onOpenURL { model.navigate($0.absoluteString) }
    }
}

struct WebViewContainer: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> UIView { UIView() }

    func updateUIView(_ view: UIView, context: Context) {
        guard webView.superview !== view else { return }
        view.subviews.forEach { $0.removeFromSuperview() }
        webView.frame = view.bounds
        webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(webView)
    }
}
