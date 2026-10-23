// Licensed under GPL-3.0. See LICENSE.
import SwiftUI
import AppKit
import NookWeb

struct MiniBrowserWindowView: View {
    let page: PageSession
    @EnvironmentObject private var gradientColorManager: GradientColorManager

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
    }
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
