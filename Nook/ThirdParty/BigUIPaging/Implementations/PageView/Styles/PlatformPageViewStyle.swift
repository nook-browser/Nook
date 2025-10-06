import SwiftUI

/// Internal style that maps to a platform specific style
struct PlatformPageViewStyle: PageViewStyle {
    
    let options: PlatformPageViewConfiguration
    
    func makeBody(configuration: Configuration) -> some View {
        PlatformPageView(
            selection: configuration.selection,
            configuration: options
        ) { value in
            configuration.next(value)
        } previous: { value in
            configuration.previous(value)
        } content: { value in
            configuration.content(value)
        }
    }
}
