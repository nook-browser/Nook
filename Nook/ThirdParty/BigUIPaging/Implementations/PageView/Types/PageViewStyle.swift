import SwiftUI

/// The appearance and behaviour of a page view.
///
/// To configure the style for a single ``PageView`` or for all page view instances in a view hierarchy, use the
/// ``SwiftUI/View/pageViewStyle(_:)`` modifier. You can specify one of the built-in page styles, like plain or scroll:
///
/// ```swift
/// PageViewExample()
///     .pageViewStyle(.scroll)
/// ```
/// Alternatively, you can create and apply a custom style.
///
/// ### Custom Styles
///
/// To create a custom style, declare a type that conforms to the `PageViewStyle` protocol and implement
///  the required ``PageViewStyle/makeBody(configuration:)`` method. 
///
/// Here's how ``PlainPageViewStyle`` is implemented:
///
///  ```swift
/// public struct PlainPageViewStyle: PageViewStyle {
///
///     public init() { }
///
///     public func makeBody(configuration: Configuration) -> some View {
///         ZStack {
///             configuration.content(configuration.selection.wrappedValue)
///         }
///     }
/// }
/// ```
///
/// Inside the method you use the configuration parameter, which is an instance of the
/// ``PageViewStyleConfiguration`` structure. This allows you to access the currently selected value
/// and the page content view builder.
///
/// The following example shows how you might display the next and previous page alongside the currently
/// selected page:
///
/// ```swift
/// struct MyCustomPageViewStyle: PageViewStyle {
///
///     func makeBody(configuration: Configuration) -> some View {
///         ZStack {
///             let current = configuration.selection.wrappedValue
///             // Get the previous page's value, relative to the current
///             if let previous = configuration.previous(current) {
///                 // Call the page's content view builder
///                 configuration.content(previous)
///                     .scaleEffect(0.3)
///                     .offset(x: -120)
///             }
///             // Repeat for the next page...
///             if let next = configuration.next(current) {
///                 configuration.content(next)
///                     .scaleEffect(0.3)
///                     .offset(x: 120)
///             }
///             // ...and finally call the content for the current page
///             configuration.content(current)
///                 .scaleEffect(0.6)
///         }
///     }
/// }
/// ```
///
/// This results in a layout that looks like this:
///
/// ![Custom layout](MyCustomPageViewStyle)
///
public protocol PageViewStyle: DynamicProperty {
    
    associatedtype Body : View
    
    typealias Configuration = PageViewStyleConfiguration

    @ViewBuilder func makeBody(configuration: Self.Configuration) -> Self.Body

}

struct PageViewStyle_Previews: PreviewProvider {
    
    static var previews: some View {
        PageViewBasicExample()
    }
}
