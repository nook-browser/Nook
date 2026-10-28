import SwiftUI

extension View {
    
    /// Sets the style of the page view within the current environment.
    public func pageViewStyle<S>(_ style: S) -> some View where S: PageViewStyle {
        self.environment(\.pageViewStyle, style)
    }
    
    /// Sets the orientation of the page view within the current environment.
    public func pageViewOrientation(_ axis: Axis) -> some View {
        self.environment(\.pageViewOrientation, axis)
    }
    
    /// Sets the spaces between pages, in points.
    ///
    /// This will only have effect on styles that support spacing, such as ``ScrollPageViewStyle``.
    public func pageViewSpacing(_ spacing: Double?) -> some View {
        self.environment(\.pageViewSpacing, spacing)
    }
    
    /// Specifies the visibility of the background of pages within this view.
    public func pageContentBackground(_ visibility: Visibility) -> some View {
        self.environment(\.contentBackground, visibility)
    }

    /// Calls `action` as a swipe moves the pages, and with nil once they settle. macOS only.
    public func onPageSwipe(_ action: @escaping (PageSwipePosition?) -> Void) -> some View {
        self.environment(\.pageSwipeAction, action)
    }

    /// Whether a swipe pages at all. Off while something over the pages owns the gesture.
    public func pageSwipeEnabled(_ enabled: Bool) -> some View {
        self.environment(\.pageSwipeEnabled, enabled)
    }

    /// Hands a pull past the first page to `action`, finger distance as it moves and the
    /// release with its velocity, instead of rubber-banding the page. macOS only.
    public func onPageOverscrollLeading(_ action: @escaping (PageLeadingPull) -> Void) -> some View {
        self.environment(\.pageLeadingOverscrollAction, action)
    }
}

/// A pull past the first page: points the fingers have travelled, then the release with its
/// velocity in points a second (positive is still pulling).
public enum PageLeadingPull {
    case changed(distance: CGFloat)
    case ended(distance: CGFloat, velocity: CGFloat)
}

/// Where a swipe sits: `progress` of the way from the page `from` to the page `to`.
public struct PageSwipePosition {
    public let from: AnyHashable
    public let to: AnyHashable
    public let progress: Double
}

extension EnvironmentValues {
    
    struct StyleKey: EnvironmentKey {
        static var defaultValue: any PageViewStyle = PlainPageViewStyle()
    }
    
    var pageViewStyle: any PageViewStyle {
        get { self[StyleKey.self] }
        set { self[StyleKey.self] = newValue }
    }
    
    struct OrientationKey: EnvironmentKey {
        static var defaultValue: Axis = .horizontal
    }
    
    var pageViewOrientation: Axis {
        get { self[OrientationKey.self] }
        set { self[OrientationKey.self] = newValue }
    }
    
    struct SpacingKey: EnvironmentKey {
        static var defaultValue: Double? = nil
    }
    
    var pageViewSpacing: Double? {
        get { self[SpacingKey.self] }
        set { self[SpacingKey.self] = newValue }
    }
    
    struct ContentBackgroundVisibilityKey: EnvironmentKey {
        static var defaultValue: Visibility = .automatic
    }
    
    var contentBackground: Visibility {
        get { self[ContentBackgroundVisibilityKey.self] }
        set { self[ContentBackgroundVisibilityKey.self] = newValue }
    }
    
    struct PageSwipeActionKey: EnvironmentKey {
        static var defaultValue: ((PageSwipePosition?) -> Void)? = nil
    }

    var pageSwipeAction: ((PageSwipePosition?) -> Void)? {
        get { self[PageSwipeActionKey.self] }
        set { self[PageSwipeActionKey.self] = newValue }
    }

    struct PageSwipeEnabledKey: EnvironmentKey {
        static var defaultValue = true
    }

    var pageSwipeEnabled: Bool {
        get { self[PageSwipeEnabledKey.self] }
        set { self[PageSwipeEnabledKey.self] = newValue }
    }

    struct PageLeadingOverscrollKey: EnvironmentKey {
        static var defaultValue: ((PageLeadingPull) -> Void)? = nil
    }

    var pageLeadingOverscrollAction: ((PageLeadingPull) -> Void)? {
        get { self[PageLeadingOverscrollKey.self] }
        set { self[PageLeadingOverscrollKey.self] = newValue }
    }

    struct NavigateActionKey: EnvironmentKey {
        static var defaultValue: PageViewNavigateAction = .default
    }
        
    /// Navigates the page view in the environment.
    public var navigatePageView: PageViewNavigateAction {
        get { self[NavigateActionKey.self] }
        set { self[NavigateActionKey.self] = newValue }
    }
    
    struct CanNavigateKey: EnvironmentKey {
        static var defaultValue = PageViewDirection()
    }
    
    /// A set of the currently allowed directions of travel.
    ///
    /// Check the set for a specific direction to to disable navigation UI elements.
    ///
    /// ```swift
    /// @Environment(\.canNavigatePageView) private var canNavigate
    ///
    /// var body: some View {
    ///     Button {
    ///         ...
    ///     } label: {
    ///         ...
    ///     }
    ///     .disabled(canNavigate.contains(direction) == false)
    /// }
    /// ```
    public var canNavigatePageView: PageViewDirection {
        get { self[CanNavigateKey.self] }
        set { self[CanNavigateKey.self] = newValue }
    }
}

