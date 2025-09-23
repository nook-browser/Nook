//
//  RefreshButton.swift
//  Nook
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct RefreshButton: View {
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
                .foregroundStyle(disabled ? AppColors.textQuaternary : .black.opacity(0.55))
                .padding(4)
                .symbolEffect(.rotate.clockwise.byLayer, options: .speed(1.5), value: animateFlag)
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
