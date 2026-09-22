// Licensed under GPL-3.0. See LICENSE.
//
//  TabLayoutStage.swift
//  Nook
//
//  Created by Maciek Bagiński on 17/02/2026.
//

import NookSettings
import NookDesign
import SwiftUI

struct TabLayoutStage: View {
    @Binding var selectedLayout: TabLayout

    var body: some View {
        VStack(spacing: 24){
            Text("Tab Layout")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
            HStack(spacing: 24) {
                layoutOption(image: "top-of-window", label: "Top of window", layout: .topOfWindow)
                layoutOption(image: "sidebar", label: "Sidebar", layout: .sidebar)
            }
        }
    }

    @ViewBuilder
    private func layoutOption(image: String, label: String, layout: TabLayout) -> some View {
        VStack(spacing: 12) {
            Button {
                selectedLayout = layout
            } label: {
                Image(image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 180, height: 140)
                    .clipShape(NookDesign.Radius.shape(NookDesign.Radius.md))
                    .overlay {
                        NookDesign.Radius.shape(NookDesign.Radius.md)
                            .stroke(.black.opacity(0.2), lineWidth: selectedLayout == layout ? 4 : 0)
                    }
                    .animation(.easeInOut(duration: 0.1), value: selectedLayout == layout)
            }
            .buttonStyle(.plain)

            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
