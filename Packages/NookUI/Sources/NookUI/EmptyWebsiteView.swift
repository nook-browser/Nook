// Licensed under GPL-3.0. See LICENSE.
//
//  EmptyWebsiteView.swift
//  Nook
//
//  Created by Maciek Bagiński on 28/07/2025.
//

import SwiftUI
import NookDesign

public struct EmptyWebsiteView: View {
    @Environment(\.colorScheme) var colorScheme

    public init() {}

    public var body: some View {
        ZStack {
            #if os(iOS)
            NookDesign.Surface.windowBackground
            #endif

            VStack(spacing: 16) {
                Image(systemName: "moon.stars")
                    .font(NookDesign.Font.display)
                    .blendMode(.overlay)

                Text("Ah, peace.")
                    .font(NookDesign.Font.title)
                    .foregroundColor(colorScheme == .dark ? .white.opacity(0.7) : .black.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
