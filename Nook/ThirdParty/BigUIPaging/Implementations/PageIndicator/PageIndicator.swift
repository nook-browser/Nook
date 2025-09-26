import SwiftUI

/// A control that displays a horizontal series of dots, each of which corresponds to a page.
///
/// When a user taps a page indictor to move to the next or previous page, the control updates the selection
/// binding. A user can also drag along the indicator to move between pages.
///
/// ```swift
/// @State private var selection = 0
///
/// var body: some View {
///     PageIndicator(selection: $selection, total: total)
///     Text("Current Page: \(selection)")
/// }
/// ```
///
/// ![PageIndicator on iOS](PageIndicator)
///
/// ## Styling
///
/// You can set the tint color of the indicator by using the built-in view modifiers:
///
/// ```swift
/// PageIndicator(selection: $selection, total: total)
///     .pageIndicatorCurrentColor(.purple)
///     .pageIndicatorColor(.purple.opacity(0.3))
/// ```
///
/// ![PageIndicator on iOS with customised tint colors](PageIndicator-colors)
///
/// The background and color scheme of the indicator can also be set like so:
///
/// ```swift
/// PageIndicator(selection: $selection, total: total)
///     .pageIndicatorBackgroundStyle(.prominent)
///     .colorScheme(.dark)
/// ```
///
/// ## Indicator Icons
///
/// You can customise an indicator's icon to denote special pages, such as how the Weather app uses the
/// first page to represent the user's current location:
///
/// ![PageIndicator on iOS with customised icon](PageIndicator-icons)
///
/// Icon customisations are provided in the form of a view builder passed to the
/// ``PageIndicator/init(selection:total:icons:)`` initialiser.
/// The first parameter represents the page index and the second the selected state. Here's an example that
/// replaces the first page with a location symbol:
///
/// ```swift
/// PageIndicator(selection: $selection, total: total) { (page, selected) in
///     if page == 0 {
///         Image(systemName: "location.fill")
///     }
/// }
/// ```
///
/// Here's how you might vary the icon depending on the currently selected page:
///
/// ```swift
/// PageIndicator(selection: $selection, total: total) { (page, selected) in
///     if selected {
///         Image(systemName: "folder.fill")
///     } else {
///         Image(systemName: "folder")
///     }
/// }
/// ```
///
/// ## Page Progress
///
/// A page indicator can automatically advance to the next page after a set duration.
///
/// ```swift
/// PageIndicator...
///     .pageIndicatorDuration(3.0)
/// ```
/// This can also be used to drive a ``PageView`` if the selection binding is shared between the two views.
///
@available(macOS, unavailable)
@available(iOS 16.0, *)
public struct PageIndicator: View {
    
    /// The background styles of the page indicator.
    public enum BackgroundStyle {
        /// The default background style, which adapts in response to changes in the page control’s interaction state.
        case automatic
        /// The background style that shows a full background regardless of the interaction.
        case prominent
        /// The background style that shows a minimal background regardless of the interaction.
        case minimal
    }

    /// The current page selection.
    @Binding var selection: Int
    
    /// The total number of pages.
    let total: Int

    /// Indicator icons. Page index represented by key. Tuple value represents selected and unselected states respectively.
    let icons: [Int: (Image?, Image?)]

    /// Whether the page indicator timer in resumed or paused.
    @State private var isProgressing = false
    
    /// Creates a new page indicator instance.
    /// - Parameter selection: A binding to the current page shown as a dot.
    /// - Parameter total: The total number of pages (dots).
    public init(
        selection: Binding<Int>,
        total: Int
    ) {
        self._selection = selection
        self.total = total
        self.icons = [:]
    }
    
    /// Creates a new page indicator instance.
    /// - Parameter selection: A binding to the current page shown as a dot.
    /// - Parameter total: The total number of pages (dots).
    /// - Parameter icons: A view builder to provide custom indicator icons. The first parameter represents
    /// the page index and the second is a boolean indicating whether the page is selected. Only system images
    /// are currently supported.
    public init<Icons>(
        selection: Binding<Int>,
        total: Int,
        @ViewBuilder icons: @escaping (Int, Bool) -> Icons
    ) where Icons : View {
        self._selection = selection
        self.total = total
        
        var indicatorIcons = [Int: (Image?, Image?)]()
        for page in 0 ..< total {
            let selected = icons(page, true)
                ._firstImage()
            let unselected = icons(page, false)
                ._firstImage()
            indicatorIcons[page] = (selected, unselected)
        }
        self.icons = indicatorIcons
    }
    
    public var body: some View {
        #if canImport(UIKit)
        PlatformPageIndicator(
            selection: $selection,
            total: total,
            isProgressing: $isProgressing,
            icons: icons
        )
        .onAppear {
            isProgressing = true
        }
        .onDisappear {
            isProgressing = false
        }
        #endif
    }
}

@available(macOS, unavailable)
struct PageIndicator_Previews: PreviewProvider {
    
    static var previews: some View {
        PageIndicatorExample()
    }
}
