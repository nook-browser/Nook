//
//  ToastView.swift
//  Nook
//
//  Unified toast container component with standardized FindBar-style styling.
//

import SwiftUI
import UniversalGlass

/// A reusable toast container that provides standardized visual styling.
/// Use with `.transition(.toast)` and `.animation(.smooth(duration: 0.25), value: condition)` in parent.
struct ToastView<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(12)
            .fixedSize(horizontal: true, vertical: false)
            .background(Color(.windowBackgroundColor).opacity(0.35))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .universalGlassEffect(
                .regular.tint(Color(.windowBackgroundColor).opacity(0.35)),
                in: .rect(cornerRadius: 16)
            )
            .shadow(color: .black.opacity(0.15), radius: 6, x: 0, y: 2)
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
    var iconForeground: Color = .white
    var textForeground: Color = .white

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(iconForeground)
                .frame(width: 14, height: 14)
                .padding(4)
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.4), lineWidth: 1)
                }

            Text(text)
                .font(.system(size: 12, weight: .medium))
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
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .padding(4)
                .background(Color.white.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(.white.opacity(0.4), lineWidth: 1)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}
