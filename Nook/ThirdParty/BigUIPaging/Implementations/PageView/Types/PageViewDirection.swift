import SwiftUI

/// Represents the direction of travel in a page view.
public struct PageViewDirection: OptionSet {
    
    public var rawValue: Int
    
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }
    
    /// Represents navigating to the next item.
    public static let forwards = PageViewDirection(rawValue: 1 << 1)
    
    /// Represents navigating to the previous item.
    public static let backwards = PageViewDirection(rawValue: 1 << 2)
    
}
