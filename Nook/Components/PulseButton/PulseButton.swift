//
//  NookButton.swift
//  NookDev
//
//  Created by Maciek Bagiński on 04/08/2025.
//

import SwiftUI

/// A unified, highly configurable button component that provides a consistent button experience.
/// 
/// NookButton provides a consistent button experience with support for:
/// - Multiple visual variants (primary, secondary, destructive)
/// - Icon animations (checkmark, custom icons)
/// - Different shadow styles (none, subtle, prominent)
/// - Custom color schemes
/// - Keyboard shortcuts
/// - 3D depth effects with press animations
///
/// ## Usage Examples
///
/// ### Basic Buttons
/// ```swift
/// // Simple button
/// NookButton.createButton(
///     text: "Cancel",
///     variant: .secondary,
///     action: onCancel,
///     keyboardShortcut: .escape
/// )
///
/// // Animated create button
/// NookButton.animatedCreateButton(
///     text: "Create Profile",
///     iconName: "plus",
///     variant: .primary,
///     action: handleSave,
///     keyboardShortcut: .return
/// )
/// ```
///
/// ### Custom Configuration
/// ```swift
/// // Fully custom button
/// NookButton(
///     text: "Favorite",
///     iconName: "heart",
///     variant: .primary,
///     action: toggleFavorite,
///     animationType: .custom("heart.fill"),
///     shadowStyle: .subtle,
///     customColors: NookButton.CustomColors(
///         backgroundColor: .purple,
///         textColor: .white,
///         borderColor: .clear,
///         shadowColor: .purple.opacity(0.3),
///         shadowOffset: CGSize(width: 0, height: 4)
///     )
/// )
/// 
/// // Programmatically trigger animation
/// button.triggerAnimation()
/// ```
struct NookButton: View {
    @EnvironmentObject var gradientColorManager: GradientColorManager

    // MARK: - Types
    
    /// Visual style variants for the button
    enum Variant {
        /// Primary action button - typically accent colored with white text
        case primary
        /// Secondary action button - typically subtle background with primary text
        case secondary
        /// Destructive action button - typically red with white text
        case destructive
    }
    
    /// Animation types for icon transitions
    enum AnimationType: Equatable {
        /// No animation - icon remains static
        case none
        /// Animates to checkmark icon when pressed
        case checkmark
        /// Animates to a custom icon when pressed
        case custom(String)
    }
    
    /// Shadow/depth styles for the button
    enum ShadowStyle {
        /// No shadow outline
        case none
        /// Subtle black outline with 2px offset (standard buttons)
        case subtle
        /// Prominent gray background with white stroke, 6px offset (create buttons)
        case prominent
    }
    
    // MARK: - Properties
    
    /// The text displayed on the button
    let text: String
    
    /// Optional SF Symbol name for the icon displayed next to the text
    let iconName: String?
    
    /// Visual variant determining the button's appearance
    let variant: Variant
    
    /// Action to perform when the button is tapped
    let action: () -> Void
    
    /// Optional keyboard shortcut that triggers the button action
    let keyboardShortcut: KeyEquivalent?
    
    /// Type of animation to perform on the icon when pressed
    let animationType: AnimationType
    
    /// Shadow/depth style for the button's 3D effect
    let shadowStyle: ShadowStyle
    
    /// Optional custom color scheme overriding the variant's default colors
    let customColors: CustomColors?
    
    // MARK: - Private State
    @State private var isHovered: Bool = false
    @State private var isPressed: Bool = false
    @State private var currentIconName: String?
    @State private var hasAnimated: Bool = false
    
    // MARK: - Custom Colors
    
    /// Custom color scheme for complete button appearance control
    struct CustomColors {
        /// Background color of the button
        let backgroundColor: Color
        /// Text and icon color
        let textColor: Color
        /// Border color (if any)
        let borderColor: Color
        /// Shadow outline color
        let shadowColor: Color
        /// Shadow outline offset from the button
        let shadowOffset: CGSize
    }
    
    // MARK: - Initializers
    
    /// Creates a fully configurable NookButton
    /// - Parameters:
    ///   - text: The text displayed on the button
    ///   - iconName: Optional SF Symbol name for the icon
    ///   - variant: Visual style variant (default: .primary)
    ///   - action: Action to perform when tapped (default: empty closure)
    ///   - keyboardShortcut: Optional keyboard shortcut (default: nil)
    ///   - animationType: Icon animation type (default: .none)
    ///   - shadowStyle: Shadow/depth style (default: .subtle)
    ///   - customColors: Optional custom color scheme (default: nil)
    init(
        text: String,
        iconName: String? = nil,
        variant: Variant = .primary,
        action: @escaping () -> Void = {},
        keyboardShortcut: KeyEquivalent? = nil,
        animationType: AnimationType = .none,
        shadowStyle: ShadowStyle = .subtle,
        customColors: CustomColors? = nil
    ) {
        self.text = text
        self.iconName = iconName
        self.variant = variant
        self.action = action
        self.keyboardShortcut = keyboardShortcut
        self.animationType = animationType
        self.shadowStyle = shadowStyle
        self.customColors = customColors
    }
    
    // MARK: - Convenience Initializers
    
    /// Creates a standard button without animations
    /// - Parameters:
    ///   - text: The text displayed on the button
    ///   - iconName: Optional SF Symbol name for the icon
    ///   - variant: Visual style variant (default: .primary)
    ///   - action: Action to perform when tapped
    ///   - keyboardShortcut: Optional keyboard shortcut
    /// - Returns: A NookButton configured for standard use
    static func createButton(
        text: String,
        iconName: String? = nil,
        variant: Variant = .primary,
        action: @escaping () -> Void = {},
        keyboardShortcut: KeyEquivalent? = nil
    ) -> NookButton {
        NookButton(
            text: text,
            iconName: iconName,
            variant: variant,
            action: action,
            keyboardShortcut: keyboardShortcut,
            animationType: .none,
            shadowStyle: .subtle
        )
    }
    
    /// Creates an animated create button that transitions to checkmark
    /// - Parameters:
    ///   - text: The text displayed on the button
    ///   - iconName: SF Symbol name for the initial icon (default: "plus")
    ///   - variant: Visual style variant (default: .primary)
    ///   - action: Action to perform when tapped
    ///   - keyboardShortcut: Optional keyboard shortcut
    /// - Returns: A NookButton configured for create actions with animation
    static func animatedCreateButton(
        text: String,
        iconName: String = "plus",
        variant: Variant = .primary,
        action: @escaping () -> Void = {},
        keyboardShortcut: KeyEquivalent? = nil
    ) -> NookButton {
        NookButton(
            text: text,
            iconName: iconName,
            variant: variant,
            action: action,
            keyboardShortcut: keyboardShortcut,
            animationType: .checkmark,
            shadowStyle: .prominent
        )
    }
    
    // MARK: - Public Methods
    
    /// Manually triggers the button's icon animation
    /// 
    /// This method can be used to programmatically trigger the button's icon animation
    /// without relying on the button's internal animation system. The animation will
    /// follow the button's configured `animationType`.
    func triggerAnimation() {
        if animationType != .none && !hasAnimated {
            hasAnimated = true
            withAnimation(.easeInOut(duration: 0.3)) {
                switch animationType {
                case .none:
                    break
                case .checkmark:
                    currentIconName = "checkmark"
                case .custom(let iconName):
                    currentIconName = iconName
                }
            }
        }
    }
    
    // MARK: - Body
    var body: some View {
        ZStack {
            // Shadow outline (bottom layer) - only if shadow style is not none
            if shadowStyle != .none {
                shadowOutline
            }
            
            // Main button (top layer)
            Button(action: handleAction) {
                buttonContent
            }
            .buttonStyle(PlainButtonStyle())
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .modifier(KeyboardShortcutModifier(shortcut: keyboardShortcut))
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
        .onLongPressGesture(minimumDuration: 0, maximumDistance: .infinity, pressing: { pressing in
            withAnimation(.easeInOut(duration: 0.1)) {
                isPressed = pressing
            }
        }, perform: {})
        .onAppear {
            currentIconName = iconName
        }
    }
    
    // MARK: - Subviews
    private var shadowOutline: some View {
        HStack(spacing: shadowStyle == .prominent ? 7 : 8) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.clear)
            
            if let iconName = currentIconName ?? iconName {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.clear)
            }
        }
        .padding(.vertical, shadowStyle == .prominent ? 11 : 12)
        .padding(.horizontal, 12)
        .background(shadowBackgroundColor)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(shadowStrokeColor, lineWidth: 1)
        )
        .offset(shadowOffset)
    }
    
    private var buttonContent: some View {
        HStack(spacing: 8) {
            Text(text)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(textColor)
            
            if let iconName = currentIconName ?? iconName {
                Image(systemName: iconName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(textColor)
                    .contentTransition(.symbolEffect(.replace))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .overlay(
            // Top and left borders (highlight)
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.3),
                            Color.white.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .offset(y: isPressed ? 2 : 0)
    }
    
    // MARK: - Action Handling
    private func handleAction() {
        // Trigger animation if configured
        triggerAnimation()
        
        // Execute the action
        action()
    }
    
    // MARK: - Computed Properties
    private var backgroundColor: Color {
        if let customColors = customColors {
            return customColors.backgroundColor
        }
        
        switch variant {
        case .primary:
            return isHovered ? gradientColorManager.primaryColor.opacity(0.8) : gradientColorManager.primaryColor
        case .secondary:
            return isHovered ? Color.primary.opacity(0.08) : Color.primary.opacity(0.05)
        case .destructive:
            return isHovered ? Color.red.opacity(0.8) : Color.red
        }
    }
    
    private var textColor: Color {
        if let customColors = customColors {
            return customColors.textColor
        }
        
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
        if let customColors = customColors {
            return customColors.borderColor
        }
        
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
    
    // MARK: - Shadow Properties
    private var shadowBackgroundColor: Color {
        if let customColors = customColors {
            return customColors.shadowColor
        }
        
        switch shadowStyle {
        case .none:
            return Color.clear
        case .subtle:
            return Color.clear
        case .prominent:
            return Color.gray
        }
    }
    
    private var shadowStrokeColor: Color {
        if let customColors = customColors {
            return customColors.shadowColor
        }
        
        switch shadowStyle {
        case .none:
            return Color.clear
        case .subtle:
            return Color.black.opacity(0.3)
        case .prominent:
            return Color.white.opacity(1)
        }
    }
    
    private var shadowOffset: CGSize {
        if let customColors = customColors {
            return customColors.shadowOffset
        }
        
        switch shadowStyle {
        case .none:
            return CGSize.zero
        case .subtle:
            return CGSize(width: 0, height: 2)
        case .prominent:
            return CGSize(width: 0, height: 6)
        }
    }
}

// MARK: - Keyboard Shortcut Modifier

// MARK: - Backward Compatibility

/// Backward compatibility alias for legacy PulseButton usage
/// 
/// This allows existing code using `PulseButton` to continue working
/// while encouraging migration to the new `NookButton` API.
typealias PulseButton = NookButton

// MARK: - Keyboard Shortcut Modifier

/// Internal modifier for handling optional keyboard shortcuts
struct KeyboardShortcutModifier: ViewModifier {
    let shortcut: KeyEquivalent?
    
    func body(content: Content) -> some View {
        if let shortcut = shortcut {
            content.keyboardShortcut(shortcut, modifiers: [])
        } else {
            content
        }
    }
}

// MARK: - Migration Guide

/*
 ## Migration from Legacy Button Components to NookButton
 
 ### Legacy NookButton → NookButton.createButton()
 
 **Before:**
 ```swift
 NookButton(
     text: "Cancel",
     variant: .secondary,
     action: onCancel
 )
 ```
 
 **After:**
 ```swift
 NookButton.createButton(
     text: "Cancel",
     variant: .secondary,
     action: onCancel
 )
 ```
 
 ### AnimatedCreateButton → NookButton.animatedCreateButton()
 
 **Before:**
 ```swift
 AnimatedCreateButton(
     text: "Create Profile",
     iconName: "plus",
     variant: .primary,
     isCreating: $isCreating,
     onSave: handleSave
 )
 ```
 
 **After:**
 ```swift
 NookButton.animatedCreateButton(
     text: "Create Profile",
     iconName: "plus",
     variant: .primary,
     action: handleSave
 )
 ```
 
 ### Legacy PulseButton → NookButton (Backward Compatible)
 
 **Legacy code still works:**
 ```swift
 PulseButton.createButton(
     text: "Cancel",
     variant: .secondary,
     action: onCancel
 )
 ```
 
 **Recommended migration:**
 ```swift
 NookButton.createButton(
     text: "Cancel",
     variant: .secondary,
     action: onCancel
 )
 ```
 
 ### Key Changes:
 - `isCreating` binding is no longer needed (animation is handled internally)
 - `onSave` parameter is now `action`
 - `animateToCheckmark()` method is now `triggerAnimation()` (works with any animation type)
 - All existing functionality is preserved
 - New features available: custom animations, shadow styles, custom colors
 
 ### New Features Available:
 
 **Custom Icon Animation:**
 ```swift
 NookButton(
     text: "Favorite",
     iconName: "heart",
     variant: .primary,
     action: toggleFavorite,
     animationType: .custom("heart.fill")
 )
 ```
 
 **Custom Colors:**
 ```swift
 NookButton(
     text: "Special",
     variant: .primary,
     action: specialAction,
     customColors: NookButton.CustomColors(
         backgroundColor: .purple,
         textColor: .white,
         borderColor: .clear,
         shadowColor: .purple.opacity(0.3),
         shadowOffset: CGSize(width: 0, height: 4)
     )
 )
 ```
 */
