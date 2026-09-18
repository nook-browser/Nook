// Licensed under GPL-3.0 with the App Store exception in LICENSE-EXCEPTION.md.
import SwiftUI

struct URLBarFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

