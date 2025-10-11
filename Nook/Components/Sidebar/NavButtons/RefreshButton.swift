//
//  RefreshButton.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct RefreshButton: View {
    @Environment(BrowserManager.self) private var browserManager
    @Environment(\.colorScheme) var colorScheme
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
        .padding(4)
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
            return colorScheme == .dark ? AppColors.iconHoverLight : AppColors.iconHoverDark
        } else {
            return Color.clear
        }
    }
    private var iconColor: Color {
        if disabled {
            return colorScheme == .dark ? AppColors.iconDisabledLight : AppColors.iconDisabledDark
        } else {
            return colorScheme == .dark ? AppColors.iconActiveLight : AppColors.iconActiveDark
        }
    }
}
