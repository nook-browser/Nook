//
//  SidebarMenuTab.swift
//  Nook
//
//  Created by Maciek Bagiński on 23/09/2025.
//

import SwiftUI

struct SidebarMenuTab: View {
    var image: String
    var activeImage: String
    var title: String
    var isActive: Bool = true
    let action: () -> Void
    @State private var isHovering: Bool = false
    @State private var shouldWiggle: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: isActive ? activeImage : image)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isActive ? .green : .white)
                .symbolRenderingMode(.hierarchical)
                .symbolEffect(.wiggle, value: shouldWiggle)
                .contentTransition(.symbolEffect(.replace.magic(fallback: .downUp.byLayer), options: .nonRepeating))

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(height: 80)
        .frame(maxWidth: .infinity)
        .background(isActive ?.white.opacity(0.1) : isHovering ? .white.opacity(0.05) : .clear)
        .animation(.linear(duration: 0.1), value: isHovering)
        .animation(.linear(duration: 0.2), value: isActive)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .onHover { state in
            isHovering = state
        }
        .onTapGesture {
            action()
            shouldWiggle.toggle()
        }
    }
}
