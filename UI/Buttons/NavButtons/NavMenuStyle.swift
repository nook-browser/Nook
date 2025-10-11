//
//  NavMenuStyle.swift
//  Nook
//
//  Created by Aether Aurelia on 11/10/2025.
//

import SwiftUI

struct NavMenuStyle: MenuStyle {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.isEnabled) var isEnabled
    @Environment(\.controlSize) var controlSize
    @State private var isHovering: Bool = false
    @State private var isPressed: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        Menu(configuration)
            .overlay {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(.primary.opacity(backgroundColorOpacity))
                        .frame(width: size, height: size)

                    configuration.label
                        .font(.system(size: iconSize))
                        .foregroundStyle(.primary)
                }
                .allowsHitTesting(false)
            }
            .contentTransition(.symbolEffect(.replace.upUp.byLayer, options: .nonRepeating))
            .scaleEffect(isPressed && isEnabled ? 0.95 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: isPressed)
            .animation(.easeInOut(duration: 0.15), value: isHovering)
            .onHover { hovering in
                isHovering = hovering
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if !isPressed {
                            isPressed = true
                        }
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
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

    private var backgroundColorOpacity: Double {
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
        Menu("Options", systemImage: "ellipsis") {
            Button("Item 1") { }
            Button("Item 2") { }
        }
        .labelStyle(.iconOnly)
        .menuStyle(NavMenuStyle())

        // With foregroundStyle
        Menu("More", systemImage: "ellipsis.circle") {
            Button("Option A") { }
            Button("Option B") { }
        }
        .labelStyle(.iconOnly)
        .menuStyle(NavMenuStyle())
        .foregroundStyle(.red)

        // Different sizes
        HStack {
            Menu("", systemImage: "star") {
                Button("Item") { }
            }
            .labelStyle(.iconOnly)
            .menuStyle(NavMenuStyle())
            .controlSize(.mini)

            Menu("", systemImage: "star") {
                Button("Item") { }
            }
            .labelStyle(.iconOnly)
            .menuStyle(NavMenuStyle())
            .controlSize(.small)

            Menu("", systemImage: "star") {
                Button("Item") { }
            }
            .labelStyle(.iconOnly)
            .menuStyle(NavMenuStyle())

            Menu("", systemImage: "star") {
                Button("Item") { }
            }
            .labelStyle(.iconOnly)
            .menuStyle(NavMenuStyle())
            .controlSize(.large)
        }

        // Disabled
        Menu("Disabled", systemImage: "gear") {
            Button("Item") { }
        }
        .labelStyle(.iconOnly)
        .menuStyle(NavMenuStyle())
        .disabled(true)
    }
    .padding()
}

