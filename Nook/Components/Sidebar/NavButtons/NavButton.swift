//
//  NavButton.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct NavButton: View {
    @EnvironmentObject var browserManager: BrowserManager
    var iconName: String
    var disabled: Bool
    var action: (() -> Void)?
    @State private var isHovering: Bool = false
    
    init(iconName: String, disabled: Bool = false, action: (() -> Void)? = nil) {
        self.iconName = iconName
        self.action = action
        self.disabled = disabled
    }
    
    var body: some View {
        Button {
            action?()
        } label: {
            Image(systemName: iconName)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .padding(4)
                .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(backgroundColor)
                .frame(width: 32, height: 32)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var backgroundColor: Color {
        if isHovering {
            return browserManager.gradientColorManager.isDark ? AppColors.iconHoverDark : AppColors.iconHoverLight
        } else {
            return Color.clear
        }
    }
    private var iconColor: Color {
        if disabled {
            return browserManager.gradientColorManager.isDark ? AppColors.iconDisabledDark : AppColors.iconDisabledLight
        } else {
            return browserManager.gradientColorManager.isDark ? AppColors.iconActiveDark : AppColors.iconActiveLight
        }
    }
}
