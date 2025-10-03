import SwiftUI

/// A style that stacks pages.
///
/// Pages are stacked on top of each other. Pages animate out to the right to reveal the previous page. Next pages animate in from the right.
@available(iOS, unavailable)
@available(macOS 13.0, *)
public struct HistoryStackPageViewStyle: PageViewStyle {
    
    /// Creates a new instance
    public init() { }
    
    public func makeBody(configuration: Configuration) -> some View {
        PlatformPageViewStyle(
            options: .init(
                transition: .historyStack,
                orientation: .horizontal,
                spacing: 0
            )
        )
        .makeBody(configuration: configuration)
    }
}

@available(iOS, unavailable)
@available(macOS 13.0, *)
extension PageViewStyle where Self == HistoryStackPageViewStyle {
    
    /// A style that stacks pages.
    public static var historyStack: HistoryStackPageViewStyle {
        HistoryStackPageViewStyle()
    }
}

@available(iOS, unavailable)
@available(macOS 13.0, *)
struct HistoryStackPageViewStyle_Previews: PreviewProvider {
    
    public static var previews: some View {
        PageViewBasicExample()
            .pageViewStyle(.historyStack)
    }
}
