//
//  NavButton.swift
//  Nook
//
//  Created by Maciek Bagiński on 30/07/2025.
//  Updated by Aether Aurelia on 11/10/2025.
//

import SwiftUI

struct NavButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.controlSize) var controlSize
    @State private var isHovering: Bool = false
    
    func makeBody(configuration: Configuration) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(.primary.opacity(backgroundColorOpacity(isPressed: configuration.isPressed)))
                .frame(width: size, height: size)
            
            configuration.label
                .foregroundStyle(.primary)
                .font(.system(size: iconSize))
        }
        .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
        .scaleEffect(configuration.isPressed && isEnabled ? 0.95 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
        .animation(.easeInOut(duration: 0.15), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
    
    private var size: CGFloat {
        switch controlSize {
        case .mini: 24
        case .small: 28
        case .regular: 32
        case .large: 40
        case .extraLarge: 48
        @unknown default: 32
        }
    }
    
    private var iconSize: CGFloat {
        switch controlSize {
        case .mini: 12
        case .small: 14
        case .regular: 16
        case .large: 20
        case .extraLarge: 24
        @unknown default: 16
        }
    }
    
    private var cornerRadius: CGFloat {
        6
    }
    
    private func backgroundColorOpacity(isPressed: Bool) -> Double {
        if (isHovering || isPressed) && isEnabled {
            return colorScheme == .dark ? 0.2 : 0.1
        } else {
            return 0.0
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        // Default
        Button {
            print("Tapped")
        } label: {
            Image(systemName: "arrow.left")
        }
        .buttonStyle(NavButtonStyle())
        .foregroundStyle(Color.primary)
        
        // With foregroundStyle
        Button {
            print("Tapped")
        } label: {
            Image(systemName: "heart.fill")
        }
        .buttonStyle(NavButtonStyle())
        .foregroundStyle(.red)
        
        // Different sizes
        HStack {
            Button { } label: { Image(systemName: "star") }
                .buttonStyle(NavButtonStyle())
                .foregroundStyle(Color.pink)
                .controlSize(.mini)
            
            Button { } label: { Image(systemName: "star") }
                .buttonStyle(NavButtonStyle())
                .foregroundStyle(Color.purple)
                .controlSize(.small)
            
            Button { } label: { Image(systemName: "star") }
                .buttonStyle(NavButtonStyle())
                .foregroundStyle(Color.yellow)
            
            Button { } label: { Image(systemName: "star") }
                .buttonStyle(NavButtonStyle())
                .foregroundStyle(Color.orange)
                .controlSize(.large)
        }
        
        // Disabled
        Button {
            print("Tapped")
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(NavButtonStyle())
        .foregroundStyle(Color.primary)
    }
    .padding()
}
