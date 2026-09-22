// Licensed under GPL-3.0. See LICENSE.
//
//  TabSuggestionItem.swift
//  Nook
//
//  Created by Maciek Bagiński on 18/08/2025.
//

import SwiftUI
import NookDesign
import NookWeb
import NookUI

struct TabSuggestionItem: View {
    let tab: SearchManager.TabMatch
    var isSelected: Bool = false
    
    @State private var isHovered: Bool = false
    @EnvironmentObject var gradientColorManager: GradientColorManager

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 9) {
                ZStack {
                    tab.favicon
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 14)
                }
                .frame(width: 24, height: 24)
                .background(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(NookDesign.Surface.fill))
                .clipShape(
                    NookDesign.Radius.shape(NookDesign.Radius.xs)
                )
                Text(tab.title)
                    .font(NookDesign.Font.label)
                    .foregroundStyle(isSelected ? .white : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            HStack(spacing: 10) {
                Text("Switch to Tab")
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(isSelected ? .white : .secondary)
                ZStack {
                    Image(systemName: "arrow.right")
                        .font(NookDesign.Font.label)
                        .foregroundStyle(isSelected ? gradientColorManager.accentColor : .secondary)
                        .frame(width: 16, height: 16)
                }
                .frame(width: 24, height: 24)
                .background(isSelected ? .white : NookDesign.Surface.fill)
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.xs))

            }
        }
        .frame(maxWidth: .infinity)
        .onHoverTracking { hovering in
            withAnimation(NookDesign.Motion.quick) {
                isHovered = hovering
            }
        }
    }
}
