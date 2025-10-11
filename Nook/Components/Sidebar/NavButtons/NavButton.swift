//
//  NavButton.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct NavButton: View {
    @Environment(BrowserManager.self) private var browserManager
    @Environment(\.colorScheme) var colorScheme
    var iconName: String
    var disabled: Bool
    var action: (() -> Void)?
    @State private var isHovering: Bool = false
    @State private var isPressing: Bool = false

    init(iconName: String, disabled: Bool = false, action: (() -> Void)? = nil) {
        self.iconName = iconName
        self.action = action
        self.disabled = disabled
    }
    
    var body: some View {
        Button {
            action?()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
                    .frame(width: 32, height: 32)

                Image(systemName: iconName)
                    .font(.system(size: 16))
                    .foregroundStyle(iconColor)
            }
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
        .scaleEffect(isPressing && !disabled ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPressing)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !disabled && !isPressing {
                        isPressing = true
                    }
                }
                .onEnded { _ in
                    isPressing = false
                }
        )
    }
    
    private var backgroundColor: Color {
        if (isHovering || isPressing) && !disabled {
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
