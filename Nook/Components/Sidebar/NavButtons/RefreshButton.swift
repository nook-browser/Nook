//
//  RefreshButton.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct RefreshButton: View {
    @EnvironmentObject var browserManager: BrowserManager
    var disabled: Bool
    var action: (() -> Void)?
    @State private var isHovering: Bool = false
    @State private var animateFlag = false
    
    init(disabled: Bool = false, action: (() -> Void)? = nil) {
        self.action = action
        self.disabled = disabled
    }
    
    var body: some View {
        Button {
            action?()
            animateFlag.toggle()
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
                .padding(4)
                .symbolEffect(.rotate.clockwise.byLayer, options: .speed(1.5), value: animateFlag)
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
