import SwiftUI

/// A style that stacks pages.
///
/// Pages are stacked on top of each other. Pages animate out to the left to reveal the next page. Previous pages animate in from the left.
@available(iOS, unavailable)
@available(macOS 13.0, *)
public struct BookStackPageViewStyle: PageViewStyle {
        
    /// Creates a new instance
    public init() { }
    
    public func makeBody(configuration: Configuration) -> some View {
        PlatformPageViewStyle(
            options: .init(
                transition: .bookStack,
                orientation: .horizontal,
                spacing: 0
            )
        )
        .makeBody(configuration: configuration)
    }
}

@available(iOS, unavailable)
@available(macOS 13.0, *)
extension PageViewStyle where Self == BookStackPageViewStyle {
    
    /// A style that stacks pages.
    public static var bookStack: BookStackPageViewStyle {
        BookStackPageViewStyle()
    }
}

@available(iOS, unavailable)
@available(macOS 13.0, *)
struct BookStackPageViewStyle_Previews: PreviewProvider {
    
    public static var previews: some View {
        PageViewBasicExample()
            .pageViewStyle(.bookStack)
    }
}
