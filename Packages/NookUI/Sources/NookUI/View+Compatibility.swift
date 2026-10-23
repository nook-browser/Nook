// Licensed under GPL-3.0. See LICENSE.

import SwiftUI

extension View {
    /// Keep the search controls above scrolling content on Sequoia, with the system edge effect on Tahoe.
    @ViewBuilder
    public func nookScrollHeader<Header: View>(@ViewBuilder content: () -> Header) -> some View {
        if #available(macOS 26, iOS 26, *) {
            self.safeAreaBar(edge: .top, spacing: 0, content: content)
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self.safeAreaInset(edge: .top, spacing: 0) {
                content().background(.regularMaterial)
            }
        }
    }
}

extension ToolbarContent {
    @ToolbarContentBuilder
    public func nookHiddenToolbarBackground() -> some ToolbarContent {
        if #available(macOS 26, iOS 26, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
