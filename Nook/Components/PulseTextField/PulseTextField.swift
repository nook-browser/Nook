//
//  PulseTextField.swift
//  Nook
//
//  Created by Maciek Bagiński on 05/08/2025.
//

import SwiftUI

struct NookTextField: View {
    // MARK: - Types

    enum Variant {
        case `default`
        case error
    }

    // MARK: - Properties

    let placeholder: String
    let variant: Variant
    let hasError: Bool
    let iconName: String?

    @Binding var text: String
    @FocusState private var isFocused: Bool

    // MARK: - Initializers

    init(
        text: Binding<String>,
        placeholder: String,
        variant: Variant = .default,
        hasError: Bool = false,
        iconName: String? = nil
    ) {
        _text = text
        self.placeholder = placeholder
        self.variant = variant
        self.hasError = hasError
        self.iconName = iconName
    }

    // MARK: - Body

    var body: some View {
        HStack(spacing: 12) {
            if let iconName = iconName {
                Image(systemName: iconName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 16, height: 16)
            }

            TextField(placeholder, text: $text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(textColor)
                .textFieldStyle(PlainTextFieldStyle())
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .focused($isFocused)
        .animation(.easeInOut(duration: 0.15), value: isFocused)
        .animation(.easeInOut(duration: 0.15), value: hasError)
        .accessibilityLabel(placeholder)
        .accessibilityHint(hasError ? "Error state" : "Text input field")
    }

    // MARK: - Computed Properties

    private var backgroundColor: Color {
        if hasError {
            return Color.red.opacity(0.05)
        }

        switch variant {
        case .default:
            return isFocused ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05)
        case .error:
            return Color.red.opacity(0.05)
        }
    }

    private var textColor: Color {
        if hasError {
            return Color.red
        }

        switch variant {
        case .default, .error:
            return Color.primary
        }
    }

    private var iconColor: Color {
        if hasError {
            return Color.red
        }

        switch variant {
        case .default, .error:
            return Color.primary.opacity(0.6)
        }
    }

    private var borderColor: Color {
        if hasError {
            return Color.red
        }

        switch variant {
        case .default:
            return isFocused ? Color.primary.opacity(0.2) : Color.primary.opacity(0.1)
        case .error:
            return Color.red
        }
    }

    private var borderWidth: CGFloat {
        if isFocused || hasError {
            return 1.5
        }
        return 1
    }
}
