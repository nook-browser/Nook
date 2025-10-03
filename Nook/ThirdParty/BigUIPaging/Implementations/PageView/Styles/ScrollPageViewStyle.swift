import SwiftUI

/// A style that allows for swiping between pages.
///
/// Pages are laid side-by-side. A swipe gesture allows the user to swipe anywhere on the page to begin
///  moving to the next view. 
///
/// On macOS swiping is achieved through the track pad or Magic Mouse surface.
public struct ScrollPageViewStyle: PageViewStyle {
    
    @Environment(\.pageViewOrientation) private var orientation
    @Environment(\.pageViewSpacing) private var spacing
    
    /// Creates a new instance
    public init() { }
    
    public func makeBody(configuration: Configuration) -> some View {
        PlatformPageViewStyle(
            options: .init(
                transition: .scroll,
                orientation: orientation,
                spacing: spacing ?? 0
            )
        )
        .makeBody(configuration: configuration)
    }
}

extension PageViewStyle where Self == ScrollPageViewStyle {
    
    /// A style that allows for swiping between pages.
    public static var scroll: ScrollPageViewStyle {
        ScrollPageViewStyle()
    }
}

struct ScrollablePageViewStyle_Previews: PreviewProvider {
    
    public static var previews: some View {
        PageViewBasicExample()
            .pageViewStyle(.scroll)
    }
}
