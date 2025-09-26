import SwiftUI

/// Buttons that navigate a page view.
public struct PageViewNavigationButton: View {
    
    let direction: PageViewDirection?
    
    /// Creates a new button instance.
    /// - Parameter direction:If specified a single button representing that direction will
    ///  be presented instead of a group of buttons.
    public init(_ direction: PageViewDirection? = nil) {
        self.direction = direction
    }
    
    public var body: some View {
        if let direction {
            PageViewNavigationDirectionButton(direction: direction)
        } else {
            ControlGroup {
                PageViewNavigationDirectionButton(direction: .backwards)
                PageViewNavigationDirectionButton(direction: .forwards)
            }
            .controlGroupStyle(.navigation)
        }
    }
}

private struct PageViewNavigationDirectionButton: View {
    
    let direction: PageViewDirection

    @Environment(\.navigatePageView) private var navigate
    @Environment(\.canNavigatePageView) private var canNavigate
    @Environment(\.pageViewOrientation) private var orientation
        
    var body: some View {
        Button {
            navigate(direction)
        } label: {
            Label(direction.name, 
                  systemImage: direction.symbol(for: orientation))
        }
        .disabled(canNavigate.contains(direction) == false)
        .help("Go \(direction.name)")
    }
}

extension PageViewDirection {
    
    var name: String {
        switch self {
        case .forwards:
            return "Forwards"
        case .backwards:
            return "Backwards"
        default:
            return ""
        }
    }
    
    func symbol(for orientation: Axis) -> String {
        switch orientation {
        case .horizontal:
            switch self {
            case .forwards:
                return "chevron.right"
            case .backwards:
                return "chevron.left"
            default:
                return ""
            }
        case .vertical:
            switch self {
            case .forwards:
                return "chevron.down"
            case .backwards:
                return "chevron.up"
            default:
                return ""
            }
        }
    }
}
