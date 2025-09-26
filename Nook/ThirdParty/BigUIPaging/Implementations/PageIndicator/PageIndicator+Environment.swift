import SwiftUI

@available(macOS, unavailable)
@available(iOS 16.0, *)
extension View {
    
    /// The tint color to apply to the page indicator.
    public func pageIndicatorColor(_ color: Color?) -> some View {
        self.environment(\.pageIndicatorColor, color)
    }
    
    /// The tint color to apply to the current page indicator.
    public func pageIndicatorCurrentColor(_ color: Color?) -> some View {
        self.environment(\.pageIndicatorCurrentColor, color)
    }
    
    /// A Boolean value that determines whether the page control allows continuous interaction.
    public func allowsContinuousInteraction(_ enabled: Bool = true) -> some View {
        self.environment(\.allowsContinuousInteraction, enabled)
    }
    
    /// The preferred background style.
    public func pageIndicatorBackgroundStyle(_ style: PageIndicator.BackgroundStyle) -> some View {
        self.environment(\.pageIndicatorBackgroundStyle, style)
    }
    
    /// Controls whether the page indicator is hidden when there is only one page.
    public func singlePageVisibility(_ visibility: Visibility) -> some View {
        self.environment(\.singlePageVisibility, visibility)
    }
    
    /// An interval after which the page indicator should advance to the next page.
    @available(iOS 17.0, *)
    public func pageIndicatorDuration(_ duration: TimeInterval?) -> some View {
        self.environment(\.pageDuration, duration)
    }
}

@available(macOS, unavailable)
extension EnvironmentValues {

    struct IndicatorColorKey: EnvironmentKey {
        static var defaultValue: Color? = nil
    }

    var pageIndicatorColor: Color? {
        get { self[IndicatorColorKey.self] }
        set { self[IndicatorColorKey.self] = newValue }
    }
    
    struct IndicatorCurrentColorKey: EnvironmentKey {
        static var defaultValue: Color? = nil
    }

    var pageIndicatorCurrentColor: Color? {
        get { self[IndicatorCurrentColorKey.self] }
        set { self[IndicatorCurrentColorKey.self] = newValue }
    }
    
    struct AllowsContinuousInteractionKey: EnvironmentKey {
        static var defaultValue: Bool = true
    }
    
    var allowsContinuousInteraction: Bool {
        get { self[AllowsContinuousInteractionKey.self] }
        set { self[AllowsContinuousInteractionKey.self] = newValue }
    }
    
    struct BackgroundStyleKey: EnvironmentKey {
        static var defaultValue: PageIndicator.BackgroundStyle = .automatic
    }
    
    var pageIndicatorBackgroundStyle: PageIndicator.BackgroundStyle {
        get { self[BackgroundStyleKey.self] }
        set { self[BackgroundStyleKey.self] = newValue }
    }
    
    struct SinglePageVisibilityKey: EnvironmentKey {
        static var defaultValue: Visibility = .visible
    }
    
    var singlePageVisibility: Visibility {
        get { self[SinglePageVisibilityKey.self] }
        set { self[SinglePageVisibilityKey.self] = newValue }
    }
    
    struct PageDurationKey: EnvironmentKey {
        static var defaultValue: TimeInterval? = nil
    }
    
    var pageDuration: TimeInterval? {
        get { self[PageDurationKey.self] }
        set { self[PageDurationKey.self] = newValue }
    }
}
