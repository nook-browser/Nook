import SwiftUI

extension View {
    
    /// Populates the environment with a page view context.
    ///
    /// This modifier allows for the use of ``PageViewNavigationButton`` and ``PageViewNavigateAction``.
    ///
    /// ```swift
    /// NavigationStack {
    ///     PageViewExample()
    ///         .toolbar {
    ///             PageViewNavigationButton()
    ///         }
    /// }
    /// .pageViewEnvironment()
    /// ```
    ///
    public func pageViewEnvironment() -> some View {
        modifier(PageViewEnvironmentModifier())
    }
}

struct PageViewEnvironmentModifier: ViewModifier {
    
    @State private var canNavigate = PageViewDirection()
    @State private var navigate: PageViewNavigateAction?
    
    func body(content: Content) -> some View {
        content
            .environment(\.canNavigatePageView, canNavigate)
            .environment(\.navigatePageView, navigate ?? .default)
            .onPreferenceChange(PageViewCanNavigatePreference.self) { value in
                self.canNavigate = value
            }
            .onPreferenceChange(PageViewNavigateActionPreference.self) { value in
                self.navigate = value
            }
    }
}
