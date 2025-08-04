//
//  SpacesListItem.swift
//  Pulse
//
//  Created by Maciek Bagiński on 04/08/2025.
//
import SwiftUI

struct SpacesListItem: View {
    @EnvironmentObject var browserManager: BrowserManager
    var space: Space
    @State private var isHovering: Bool = false

    private var currentSpaceID: UUID? {
        browserManager.tabManager.currentSpace?.id
    }
    
    var body: some View {
        Button {
            browserManager.tabManager.setActiveSpace(space)
        } label: {
            Image(systemName: space.icon)
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
                .padding(4)
                .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering ? AppColors.controlBackgroundHover : Color.clear)
                .frame(width: 24, height: 24) // Fixed 20x20 square
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
