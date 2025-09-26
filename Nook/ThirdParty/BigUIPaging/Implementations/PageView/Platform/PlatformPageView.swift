import SwiftUI

/// Internal interface for a platform specific page view.
struct PlatformPageView<SelectionValue, Content> where SelectionValue: Hashable, Content: View {
    
    @Binding var selection: SelectionValue
    let configuration: PlatformPageViewConfiguration
    let next: (SelectionValue) -> SelectionValue?
    let previous: (SelectionValue) -> SelectionValue?
    @ViewBuilder let content: (SelectionValue) -> Content
}

struct PlatformPageViewConfiguration {
    
    enum Transition {
        // iOS
        case scroll
        case book
        // macOS
        case historyStack
        case bookStack
    }
    
    let transition: Transition
    let orientation: Axis
    let spacing: Double
}
