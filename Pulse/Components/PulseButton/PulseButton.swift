//
//  PulseButton.swift
//  PulseDev
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

struct PulseButton: View {
    // MARK: - Types
    enum Variant {
        case primary
        case secondary
        case destructive
    }
    
    // MARK: - Properties
    let text: String
    let iconName: String?
    let variant: Variant
    let action: () -> Void
    
    @State private var isHovered: Bool = false
    
    // MARK: - Initializers
    init(
        text: String,
        iconName: String? = nil,
        variant: Variant = .primary,
        action: @escaping () -> Void = {}
    ) {
        self.text = text
        self.iconName = iconName
        self.variant = variant
        self.action = action
    }
    
    // MARK: - Body
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(text)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(textColor)
                
                if let iconName = iconName {
                    Image(systemName: iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(textColor)
                }
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(PlainButtonStyle())
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
    
    // MARK: - Computed Properties
    private var backgroundColor: Color {
        switch variant {
        case .primary:
            return isHovered ? Color.accentColor.opacity(0.8) : Color.accentColor
        case .secondary:
            return isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05)
        case .destructive:
            return isHovered ? Color.red.opacity(0.8) : Color.red
        }
    }
    
    private var textColor: Color {
        switch variant {
        case .primary:
            return Color.white
        case .secondary:
            return Color.primary
        case .destructive:
            return Color.white
        }
    }
    
    private var borderColor: Color {
        switch variant {
        case .primary, .destructive:
            return Color.clear
        case .secondary:
            return isHovered ? Color.primary.opacity(0.2) : Color.primary.opacity(0.1)
        }
    }
    
    private var borderWidth: CGFloat {
        switch variant {
        case .primary, .destructive:
            return 0
        case .secondary:
            return 1
        }
    }
}
