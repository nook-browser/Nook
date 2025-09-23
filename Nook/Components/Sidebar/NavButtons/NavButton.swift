//
//  NavButton.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//

import SwiftUI

struct NavButton: View {
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
                .foregroundStyle(disabled ? AppColors.textQuaternary : .black.opacity(0.55))
                .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovering && !disabled ? AppColors.controlBackgroundHover : Color.clear)
                .frame(width: 32, height: 32)
                .animation(.easeInOut(duration: 0.15), value: isHovering)
        )
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
