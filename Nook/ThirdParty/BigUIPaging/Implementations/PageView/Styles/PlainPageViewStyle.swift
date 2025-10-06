import SwiftUI

/// A style that presents only the currently selected page.
///
/// Plain page style has no controls or transitions. This style is useful for views where navigation is secondary,
///  for example in the Mail app where buttons in the toolbar allow a user to move next. 
///
/// Combine this style with use of ``PageViewNavigationButton`` or ``PageViewNavigateAction``.
///
public struct PlainPageViewStyle: PageViewStyle {
    
    public init() { }
    
    public func makeBody(configuration: Configuration) -> some View {
        configuration.content(configuration.selection.wrappedValue)
    }
}

extension PageViewStyle where Self == PlainPageViewStyle {
    
    /// A style that presents only the currently selected page.
    public static var plain: PlainPageViewStyle {
        PlainPageViewStyle()
    }
}

struct PlainPageViewStyle_Previews: PreviewProvider {
    
    public static var previews: some View {
        PageViewBasicExample()
            .pageViewStyle(.plain)
            .pageViewOrientation(.vertical)
    }
}
