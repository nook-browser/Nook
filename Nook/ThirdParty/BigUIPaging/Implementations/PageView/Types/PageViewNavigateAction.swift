import SwiftUI

/// An action that moves the page view in the provided direction.
///
/// As the action implements callAsFunction you call it directly:
///
/// ```swift
/// @Environment(\.navigatePageView) private var navigate
///
/// var body: some View {
///     Button {
///         navigate(.forward)
///     } label: {
///         Label("Forward", systemImage: "chevron.down")
///     }
/// }
/// ```
public struct PageViewNavigateAction {
    
    let id: UUID?
    let handler: (PageViewDirection) -> Void
    
    /// Navigates the page view in a specific direction.
    public func callAsFunction(_ direction: PageViewDirection) {
        handler(direction)
    }
}

extension PageViewNavigateAction: Equatable {
    
    static let `default` = PageViewNavigateAction(id: nil) { _ in }
    
    public static func == (lhs: PageViewNavigateAction, rhs: PageViewNavigateAction) -> Bool {
        lhs.id == rhs.id
    }
}
