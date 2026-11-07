// Licensed under GPL-3.0. See LICENSE.
import SwiftUI
import AppKit
import NookWeb
import NookDesign
import NookUI

struct MiniBrowserWindowView: View {
    let page: PageSession
    @EnvironmentObject private var gradientColorManager: GradientColorManager
    @State private var showCopyToast = false

    var body: some View {
        // On macOS 26 the page runs up under the toolbar; the load bar sits just below it.
        ZStack(alignment: .top) {
            DetachedPageHost(page: page)
                .underToolbar()
            BlockedPageView(session: page)
            TranslationTaskHost(session: page)
            if let webView = page.webView {
                PageLoadBar(webView: webView, tint: gradientColorManager.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(alignment: .bottom) {
            if showCopyToast {
                CopyURLToast()
                    .padding(.bottom, NookDesign.Spacing.xxxl)
            }
        }
        .animation(.smooth(duration: 0.25), value: showCopyToast)
        .onReceive(NotificationCenter.default.publisher(for: .miniWindowCopiedURL, object: page)) { _ in
            showCopyToast = true
            Task {
                try? await Task.sleep(for: .seconds(2))
                showCopyToast = false
            }
        }
    }
}

extension Notification.Name {
    /// Posted with the page as object when Copy URL ran on a mini window.
    static let miniWindowCopiedURL = Notification.Name("nook.miniWindowCopiedURL")
}

private extension View {
    /// Sequoia's WKWebView has no `obscuredContentInsets`, so there the page starts below the toolbar.
    @ViewBuilder func underToolbar() -> some View {
        if #available(macOS 26, *) {
            ignoresSafeArea(.container, edges: .top)
        } else {
            self
        }
    }
}
