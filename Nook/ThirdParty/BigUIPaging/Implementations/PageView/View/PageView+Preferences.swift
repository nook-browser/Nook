import SwiftUI

struct PageViewCanNavigatePreference: PreferenceKey {
    
    static var defaultValue: PageViewDirection = []
    
    static func reduce(value: inout PageViewDirection, nextValue: () -> PageViewDirection) {
        value = value.union(nextValue())
    }
}

struct PageViewNavigateActionPreference: PreferenceKey {
    
    static var defaultValue: PageViewNavigateAction?
    
    static func reduce(value: inout PageViewNavigateAction?, nextValue: () -> PageViewNavigateAction?) {
        value = nextValue() ?? value
    }
}
