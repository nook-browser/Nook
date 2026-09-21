// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
//
//  ToastView.swift
//  Nook
//
//  Unified toast container component with standardized FindBar-style styling.
//

import SwiftUI
import NookDesign

/// A reusable toast container that provides standardized visual styling.
/// Use with `.transition(.toast)` and `.animation(NookDesign.Motion.standard, value: condition)` in parent.
struct ToastView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .fixedSize(horizontal: true, vertical: false)
            .nookGlassEffect(in: NookDesign.Radius.shape(NookDesign.Radius.xl))
    }
}

/// Custom toast transition matching FindBar animation exactly (opacity + blur)
extension AnyTransition {
    static var toast: AnyTransition {
        .modifier(
            active: ToastTransitionModifier(opacity: 0, blur: 8),
            identity: ToastTransitionModifier(opacity: 1, blur: 0)
        )
    }
}

private struct ToastTransitionModifier: ViewModifier {
    let opacity: Double
    let blur: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .blur(radius: blur)
    }
}

// MARK: - Toast Content Helpers

/// Standard icon + text toast content with the default icon styling
struct ToastContent: View {
    let icon: String
    let text: String
    var iconForeground: Color = .primary
    var textForeground: Color = .primary

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(NookDesign.Font.secondary)
                .foregroundStyle(iconForeground)
                .frame(width: 14, height: 14)
                .padding(4)
                .background(NookDesign.Surface.fill)
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                .overlay {
                    NookDesign.Radius.shape(NookDesign.Radius.sm)
                        .stroke(NookDesign.Surface.hairline, lineWidth: 1)
                }

            Text(text)
                .font(NookDesign.Font.secondary)
                .foregroundStyle(textForeground)
        }
    }
}

/// Multi-line toast content for showing a title with a subtitle
struct ToastContentWithSubtitle: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(NookDesign.Font.secondary)
                .foregroundStyle(.primary)
                .frame(width: 14, height: 14)
                .padding(4)
                .background(NookDesign.Surface.fill)
                .clipShape(NookDesign.Radius.shape(NookDesign.Radius.sm))
                .overlay {
                    NookDesign.Radius.shape(NookDesign.Radius.sm)
                        .stroke(NookDesign.Surface.hairline, lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(NookDesign.Font.secondary)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(NookDesign.Font.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
