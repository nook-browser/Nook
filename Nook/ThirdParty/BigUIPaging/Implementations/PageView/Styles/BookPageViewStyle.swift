import SwiftUI

/// A style that mimics turning pages of a book.
///
/// To navigate the user "turns" the page by swiping from the edges of the view.
/// The transition applies a 3D book style effect with pages that curl.
/// 
@available(iOS 16.0, *)
@available(macOS, unavailable)
public struct BookPageViewStyle: PageViewStyle {
    
    @Environment(\.pageViewOrientation) private var orientation

    /// Creates a new instance
    public init() { }
    
    public func makeBody(configuration: Configuration) -> some View {
        PlatformPageViewStyle(
            options: .init(
                transition: .book,
                orientation: orientation,
                spacing: 0
            )
        )
        .makeBody(configuration: configuration)
    }
}

@available(iOS 16.0, *)
@available(macOS, unavailable)
extension PageViewStyle where Self == BookPageViewStyle {
    
    /// A style that mimics turning pages of a book.
    public static var book: BookPageViewStyle {
        BookPageViewStyle()
    }
}

@available(iOS 16.0, *)
@available(macOS, unavailable)
struct BookPageViewStyle_Previews: PreviewProvider {
    
    public static var previews: some View {
        PageViewBasicExample()
            .pageViewStyle(.book)
    }
}

