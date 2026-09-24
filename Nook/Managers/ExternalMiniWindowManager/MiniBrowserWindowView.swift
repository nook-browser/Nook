// Licensed under GPL-3.0. See LICENSE.
import SwiftUI
import AppKit
import NookWeb

struct MiniBrowserWindowView: View {
    let page: PageSession
    @EnvironmentObject private var gradientColorManager: GradientColorManager

    var body: some View {
        // The page runs up under the glass toolbar; the load bar sits just below it.
        ZStack(alignment: .top) {
            DetachedPageHost(page: page)
                .ignoresSafeArea(.container, edges: .top)
            if let webView = page.webView {
                PageLoadBar(webView: webView, tint: gradientColorManager.accentColor)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }
}
