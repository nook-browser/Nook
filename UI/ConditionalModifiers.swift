// atelier-core @aeastr

import SwiftUI

/// A view extension that provides clean conditional modifier application based on OS availability.
public extension View {
    /// Conditionally applies a modifier only if the current OS version supports it.
    ///
    /// - Parameters:
    ///   - condition: A boolean expression that determines if the modifier should be applied.
    ///                Uses `@autoclosure` so you can pass expressions directly without wrapping in `{ }`.
    ///   - modifier: The modifier to apply when the condition is met
    /// - Returns: The view with the modifier applied conditionally
    ///
    /// The `@autoclosure` parameter allows clean syntax - you can write `OSVersion.supportsGlassEffect`
    /// instead of `{ OSVersion.supportsGlassEffect }`. The expression is automatically wrapped in a
    /// closure and only evaluated when needed, providing lazy evaluation.
    ///
    /// Example:
    /// ```swift
    /// Text("Hello")
    ///     .conditionally(if: someCondition) { view in
    ///         view.padding(.large)
    ///     }
    /// ```
    @ViewBuilder
    func conditionally<Content: View>(
        if condition: @autoclosure () -> Bool,
        @ViewBuilder apply modifier: (Self) -> Content
    ) -> some View {
        if condition() {
            modifier(self)
        } else {
            self
        }
    }
    
    /// Conditionally applies a modifier with a fallback for older OS versions.
    ///
    /// - Parameters:
    ///   - condition: A closure that returns true if the primary modifier should be applied
    ///   - primary: The modifier to apply when the condition is met
    ///   - fallback: The fallback modifier to apply when the condition is not met
    /// - Returns: The view with either the primary or fallback modifier applied
    ///
    /// Example:
    /// ```swift
    /// Text("Hello")
    ///     .conditionally(
    ///         if: { someCondition },
    ///         apply: { $0.compatibleGlassEffect(.clear.interactive()) },
    ///         otherwise: { $0.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8)) }
    ///     )
    /// ```
    @ViewBuilder
    func conditionally<PrimaryContent: View, FallbackContent: View>(
        if condition: () -> Bool,
        apply primary: (Self) -> PrimaryContent,
        otherwise fallback: (Self) -> FallbackContent
    ) -> some View {
        if condition() {
            primary(self)
        } else {
            fallback(self)
        }
    }

    /// Conditionally applies modifiers with full control over availability checks.
    ///
    /// This version passes the view to a closure where you can perform your own
    /// `if #available` checks and apply different modifiers accordingly.
    ///
    /// - Parameter modifier: A closure that receives the view and can apply conditional modifiers
    /// - Returns: The view with conditionally applied modifiers
    ///
    /// Example:
    /// ```swift
    /// Text("Hello")
    ///     .conditionally { view in
    ///         if #available(iOS 26.0, *) {
    ///             view.glassEffect(.clear.interactive())
    ///         } else if #available(iOS 15.0, *) {
    ///             view.background(.regularMaterial, in: .rect(cornerRadius: 8))
    ///         } else {
    ///             view.background(Color.gray.opacity(0.3), in: .rect(cornerRadius: 8))
    ///         }
    ///     }
    /// ```
    @ViewBuilder
    func conditionally<Content: View>(
        @ViewBuilder apply modifier: (Self) -> Content
    ) -> some View {
        modifier(self)
    }
}

// MARK: - OS Version Helpers

/// Helper functions for checking OS availability in a clean, readable way.
public enum OSVersion {
    // MARK: - Convenience Helpers

    /// Check if running on iOS 26 or later (when glass effects were introduced)
    public static var supportsGlassEffect: Bool {
        if #available(iOS 18.0, *) {
            return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26
        }
        return false
    }
}
