// Licensed under GPL-3.0. See LICENSE.

import SwiftUI

extension View {
    /// A header the rows scroll under with the system's soft edge on macOS 26. Sequoia has no
    /// scroll edge effect, so there the header sits above the rows instead.
    @ViewBuilder
    public func nookScrollHeader<Header: View>(@ViewBuilder content: () -> Header) -> some View {
        if #available(macOS 26, iOS 26, *) {
            self.safeAreaBar(edge: .top, spacing: 0, content: content)
                .scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            VStack(spacing: 0) {
                content()
                self
            }
        }
    }
}
