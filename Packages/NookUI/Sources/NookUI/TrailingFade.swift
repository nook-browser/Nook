// Licensed under GPL-3.0. See LICENSE.
//
//  TrailingFade.swift
//  NookUI
//

import SwiftUI
import NookDesign

public extension View {
    /// Fades the trailing edge instead of truncating with an ellipsis, the way tab titles end.
    /// Put it on a frame wider than nothing, over text that is `fixedSize` inside it. `reserving`
    /// keeps that much of the edge clear, so text ends before a button that shows on hover.
    func nookTrailingFade(reserving: CGFloat = 0) -> some View {
        mask {
            HStack(spacing: 0) {
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: NookDesign.Spacing.titleFade)
                Color.clear
                    .frame(width: reserving)
            }
        }
    }
}
