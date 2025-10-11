//
//  TabSuggestionItem.swift
//  Nook
//
//  Created by Maciek Bagiński on 18/08/2025.
//

import SwiftUI

struct TabSuggestionItem: View {
    let tab: Tab
    var isSelected: Bool = false
    
    @State private var isHovered: Bool = false
    @Environment(\.colorScheme) var colorScheme
    @Environment(GradientColorManager.self) private var gradientColorManager
    
    var body: some View {
        let isDark = colorScheme == .dark
        
        HStack(alignment: .center, spacing: 0) {
            HStack(spacing: 9) {
                ZStack {
                    tab.favicon
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 14, height: 14)
                }
                .frame(width: 24, height: 24)
                .background(isSelected ? .white : .clear)
                .clipShape(
                    RoundedRectangle(cornerRadius: 4)
                )
                Text(tab.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? .white : isDark ? .white.opacity(0.6) : .black.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            HStack(spacing: 10) {
                Text("Switch to Tab")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(isSelected ? .white : isDark ? .white.opacity(0.3) : .black.opacity(0.3))
                ZStack {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isSelected ? gradientColorManager.primaryColor : isDark ? .white.opacity(0.5) : .black.opacity(0.5))
                        .frame(width: 16, height: 16)
                }
                .frame(width: 24, height: 24)
                .background(isSelected ? .white : isDark ? .white.opacity(0.05) : .black.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))

            }
        }
        .frame(maxWidth: .infinity)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
